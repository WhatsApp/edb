%% Copyright (c) Meta Platforms, Inc. and affiliates.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%% % @format

%% Scopes/variables tests for the EDB DAP adapter

-module(edb_dap_scopes_SUITE).

%% erlfmt:ignore
% @fb-only
-typing([eqwalizer]).

% @fb-only
-include_lib("stdlib/include/assert.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_reports_locals_scope/1,
    test_reports_registers_scope_when_locals_not_available/1,
    test_reports_process_pid_info_in_process_scope/1,
    test_reports_process_registered_name_info_in_process_scope/1,
    test_reports_process_messages_info_in_process_scope/1,
    test_reports_process_label_info_in_process_scope/1,

    test_structured_variables/1,
    test_structured_variables_with_pagination/1
]).

all() ->
    [
        test_reports_locals_scope,
        test_reports_registers_scope_when_locals_not_available,
        test_reports_process_pid_info_in_process_scope,
        test_reports_process_registered_name_info_in_process_scope,
        test_reports_process_messages_info_in_process_scope,
        test_reports_process_label_info_in_process_scope,

        test_structured_variables,
        test_structured_variables_with_pagination
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_reports_locals_scope(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).     %L01\n",
                    ~"-export([go/2]).  %L02\n",
                    ~"go(X, Y) ->       %L03\n",
                    ~"    X + 2 * Y.    %L04\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [42, 7]}),
    case ST of
        [#{id := TopFrameId} | _] ->
            Scopes = edb_dap_test_support:get_scopes(Client, TopFrameId),
            ?assertEqual(
                #{
                    ~"Locals" =>
                        #{
                            name => ~"Locals",
                            expensive => false,
                            presentationHint => ~"locals",
                            variablesReference => 1
                        },
                    ~"Process" =>
                        #{
                            name => ~"Process",
                            expensive => false,
                            variablesReference => 2
                        }
                },
                Scopes
            ),

            VarRef = maps:get(variablesReference, maps:get(~"Locals", Scopes)),
            LocalVars = edb_dap_test_support:get_variables(Client, VarRef),
            ?assertEqual(
                #{
                    ~"X" => #{name => ~"X", value => ~"42", variablesReference => 0},
                    ~"Y" => #{name => ~"Y", value => ~"7", variablesReference => 0}
                },
                LocalVars
            )
    end,
    ok.

test_structured_variables(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [~"""
                    -module(foo).             %L01\n
                    -export([go/2]).          %L02\n
                    go(L, X) ->               %L03\n
                        M = [4, [], {6, 7}],  %L04\n
                        F = fun(_A) -> length(L) == length(M) orelse ok end, %L05\n
                        {L ++ M, X}.          %L06\n
                """]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 6}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(
        Client, Peer, {foo, go, [[1, 2, 3], #{life => 42}]}
    ),
    case ST of
        [#{id := TopFrameId} | _] ->
            Scopes = edb_dap_test_support:get_scopes(Client, TopFrameId),
            ?assertEqual(
                #{
                    ~"Locals" =>
                        #{
                            name => ~"Locals",
                            expensive => false,
                            presentationHint => ~"locals",
                            variablesReference => 5
                        },
                    ~"Process" =>
                        #{
                            name => ~"Process",
                            expensive => false,
                            variablesReference => 6
                        }
                },
                Scopes
            ),

            VarRef = maps:get(variablesReference, maps:get(~"Locals", Scopes)),
            LocalVars = edb_dap_test_support:get_variables(Client, VarRef),
            ?assertEqual(
                #{
                    ~"L" => #{
                        name => ~"L",
                        value => ~"[1,2,3]",
                        evaluateName => ~"L",
                        variablesReference => 2
                    },
                    ~"M" => #{
                        name => ~"M",
                        value => ~"[4,[],{6,...}]",
                        evaluateName => ~"M",
                        variablesReference => 3
                    },
                    ~"X" => #{
                        name => ~"X",
                        value => ~"#{life => 42}",
                        evaluateName => ~"X",
                        variablesReference => 4
                    }
                },
                maps:remove(~"F", LocalVars)
            ),

            FVal = maps:get(~"F", LocalVars),
            ?assertMatch(
                #{
                    name := ~"F",
                    value := <<"#Fun<foo.0.", _/binary>>,
                    evaluateName := ~"F",
                    variablesReference := 1
                },
                FVal
            ),

            ChildListVarRef = maps:get(variablesReference, maps:get(~"M", LocalVars)),
            ChildrenListVars = edb_dap_test_support:get_variables(Client, ChildListVarRef),
            ?assertEqual(
                #{
                    ~"1" => #{name => ~"1", value => ~"4", variablesReference => 0},
                    ~"2" => #{name => ~"2", value => ~"[]", variablesReference => 0},
                    ~"3" => #{
                        name => ~"3",
                        value => ~"{6,7}",
                        evaluateName => ~"lists:nth(3, M)",
                        variablesReference => 7
                    }
                },
                ChildrenListVars
            ),

            ChildMapVarRef = maps:get(variablesReference, maps:get(~"X", LocalVars)),
            ChildrenMapVars = edb_dap_test_support:get_variables(Client, ChildMapVarRef),
            ?assertEqual(
                #{
                    ~"life" => #{name => ~"life", value => ~"42", variablesReference => 0}
                },
                ChildrenMapVars
            ),

            ChildFunVarRef = maps:get(variablesReference, maps:get(~"F", LocalVars)),
            ChildrenFunVars = edb_dap_test_support:get_variables(Client, ChildFunVarRef),
            ?assertEqual(
                #{
                    ~"fun" => #{
                        name => ~"fun",
                        value => ~"foo:'-go/2-fun-0-'/1",
                        variablesReference => 0
                    },
                    ~"env" => #{
                        name => ~"env",
                        value => ~"[[1,2,3],[4,[]|...]]",
                        variablesReference => 8,
                        evaluateName => ~"erlang:element(2, erlang:fun_info(F, env))"
                    }
                },
                ChildrenFunVars
            ),

            assertEvaluateNameIsCorrect(
                Client,
                TopFrameId,
                maps:get(~"env", ChildrenFunVars),
                ~"[[1,2,3],[4,[],{6,7}]]"
            ),

            GranChildVarRef = maps:get(variablesReference, maps:get(~"3", ChildrenListVars)),
            GranChildrenVars = edb_dap_test_support:get_variables(Client, GranChildVarRef),
            ?assertEqual(
                #{
                    ~"1" => #{name => ~"1", value => ~"6", variablesReference => 0},
                    ~"2" => #{name => ~"2", value => ~"7", variablesReference => 0}
                },
                GranChildrenVars
            )
    end,
    ok.

test_structured_variables_with_pagination(Config) ->
    InitArguments = #{supportsVariablePaging => true},
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, InitArguments, #{
            modules => [
                {source, [~"""
                    -module(foo).            %L01\n
                    -export([go/3]).         %L02\n
                    go(L, T, M) ->           %L03\n
                        {L, T, M}.           %L04\n
                """]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),

    L = [10, 20, 30, 40, 50, 60, 70, 80, 90],
    T = {4, [], {6, 7}, 8, {}, 9},
    M = #{life => 42, death => 43, etc => 44, more => {45, 46, 47}, universe => 99},
    {ok, _ThreadId, [#{id := TopFrameId} | _]} = edb_dap_test_support:spawn_and_wait_for_bp(
        Client, Peer, {foo, go, [L, T, M]}
    ),

    % When client supports variable paging, scopes include variable count
    #{~"Locals" := LocalsScope} = edb_dap_test_support:get_scopes(Client, TopFrameId),
    ?assertEqual(
        #{
            name => ~"Locals",
            expensive => false,
            presentationHint => ~"locals",
            variablesReference => 4,
            indexedVariables => 3
        },
        LocalsScope
    ),

    % With variable paging support, we also get counts in variable references
    VarRef = maps:get(variablesReference, LocalsScope),
    LocalVars = edb_dap_test_support:get_variables(Client, VarRef),
    ?assertEqual(
        #{
            ~"L" => #{
                name => ~"L",
                evaluateName => ~"L",
                value => ~"[10,20,30,40|...]",
                variablesReference => 1,
                indexedVariables => 9
            },
            ~"T" => #{
                name => ~"T",
                evaluateName => ~"T",
                value => ~"{4,[],{6,...},8,...}",
                variablesReference => 3,
                indexedVariables => 6
            },
            ~"M" => #{
                name => ~"M",
                evaluateName => ~"M",
                value => ~"#{death => 43,etc => 44,life => 42,more => {45,46,47},...}",
                variablesReference => 2,
                indexedVariables => 5
            }
        },
        LocalVars
    ),

    % Test pagination for list
    ListVarsRef = maps:get(variablesReference, maps:get(~"L", LocalVars)),
    ?assertEqual(
        [
            #{name => ~"3", value => ~"30", variablesReference => 0},
            #{name => ~"4", value => ~"40", variablesReference => 0},
            #{name => ~"5", value => ~"50", variablesReference => 0}
        ],
        get_variables_page(Client, ListVarsRef, #{start => 2, count => 3})
    ),

    % Test pagination for tuples
    TupleVarsRef = maps:get(variablesReference, maps:get(~"T", LocalVars)),
    ?assertEqual(
        [
            #{name => ~"2", value => ~"[]", variablesReference => 0},
            #{
                name => ~"3",
                value => ~"{6,7}",
                evaluateName => ~"erlang:element(3, T)",
                variablesReference => 6,
                indexedVariables => 2
            },
            #{name => ~"4", value => ~"8", variablesReference => 0},
            #{name => ~"5", value => ~"{}", variablesReference => 0}
        ],
        get_variables_page(Client, TupleVarsRef, #{start => 1, count => 4})
    ),

    % Test pagination for maps
    MapVarsRef = maps:get(variablesReference, maps:get(~"M", LocalVars)),
    ?assertEqual(
        [
            #{name => ~"etc", value => ~"44", variablesReference => 0},
            #{name => ~"life", value => ~"42", variablesReference => 0},
            #{
                name => ~"more",
                value => ~"{45,46,47}",
                variablesReference => 7,
                evaluateName => ~"maps:get(more, M)",
                indexedVariables => 3
            }
        ],
        get_variables_page(Client, MapVarsRef, #{start => 1, count => 3})
    ),
    ok.

test_reports_registers_scope_when_locals_not_available(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).     %L01\n",
                    ~"-export([go/2]).  %L02\n",
                    ~"go(X, Y) ->       %L03\n",
                    ~"    X + 2 * Y.    %L04\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [42, 7]}),
    case ST of
        [_, #{id := NonTopFrameId} | _] ->
            Scopes = edb_dap_test_support:get_scopes(Client, NonTopFrameId),
            ?assertEqual(
                #{
                    ~"Process" =>
                        #{
                            name => ~"Process",
                            expensive => false,
                            variablesReference => 2
                        },
                    ~"Registers" =>
                        #{
                            name => ~"Registers",
                            expensive => false,
                            presentationHint => ~"registers",
                            variablesReference => 1
                        }
                },
                Scopes
            ),

            VarRef = maps:get(variablesReference, maps:get(~"Registers", Scopes)),
            RegVars = edb_dap_test_support:get_variables(Client, VarRef),
            ?assertMatch(
                #{
                    ~"Y0" := #{name := ~"Y0", value := _, variablesReference := 0},
                    ~"Y1" := #{name := ~"Y1", value := _, variablesReference := 0},
                    ~"Y2" := #{name := ~"Y2", value := _, variablesReference := 0}
                },
                RegVars
            )
    end,
    ok.

test_reports_process_pid_info_in_process_scope(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).      %L01\n",
                    ~"-export([go/1]).   %L02\n",
                    ~"go(X) ->           %L03\n",
                    ~"    X * 3.         %L04\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [15]}),
    case ST of
        [_, #{id := NonTopFrameId} | _] ->
            ProcessVars = get_process_vars(Client, NonTopFrameId),

            ?assertMatch(
                #{
                    name := ~"self()",
                    value := <<"<0.", _/binary>>,
                    variablesReference := 0
                },
                maps:get(~"self()", ProcessVars)
            )
    end,
    ok.

test_reports_process_registered_name_info_in_process_scope(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).                       %L01\n",
                    ~"-export([go/1]).                    %L02\n",
                    ~"go(X) ->                            %L03\n",
                    ~"    register(test_process, self()), %L04\n",
                    ~"    X * 5.                          %L05\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}, {line, 5}]}]),
    {ok, ThreadId, [#{id := FrameId1} | _]} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [10]}),
    ProcessVars1 = get_process_vars(Client, FrameId1),

    ?assertNot(maps:is_key(~"Registered name", ProcessVars1)),

    edb_dap_test_client:continue(Client, #{threadId => ThreadId}),
    {ok, _, [#{id := FrameId2} | _]} = edb_dap_test_support:wait_for_bp(Client),
    ProcessVars2 = get_process_vars(Client, FrameId2),

    ?assertEqual(
        #{
            name => ~"Registered name",
            value => ~"test_process",
            variablesReference => 0
        },
        maps:get(~"Registered name", ProcessVars2)
    ),
    ok.

test_reports_process_messages_info_in_process_scope(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).      %L01\n",
                    ~"-export([go/1]).   %L02\n",
                    ~"go(X) ->           %L03\n",
                    ~"    self() ! msg1, %L04\n",
                    ~"    self() ! msg2, %L05\n",
                    ~"    self() ! msg3, %L06\n",
                    ~"    X * 5.         %L07\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 7}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [10]}),
    case ST of
        [_, #{id := NonTopFrameId} | _] ->
            ProcessVars = get_process_vars(Client, NonTopFrameId),

            ?assertEqual(
                #{
                    name => ~"Messages in queue",
                    value => ~"3",
                    evaluateName =>
                        ~"erlang:element(2, erlang:process_info(erlang:list_to_pid(\"<0.95.0>\"), messages))",
                    variablesReference => 2
                },
                maps:get(~"Messages in queue", ProcessVars)
            ),

            MessagesVarsRefs = maps:get(variablesReference, maps:get(~"Messages in queue", ProcessVars)),
            MessagesVars = edb_dap_test_support:get_variables(Client, MessagesVarsRefs),
            ?assertMatch(
                #{
                    ~"1" := #{name := ~"1", value := ~"msg1", variablesReference := 0},
                    ~"2" := #{name := ~"2", value := ~"msg2", variablesReference := 0},
                    ~"3" := #{name := ~"3", value := ~"msg3", variablesReference := 0}
                },
                MessagesVars
            )
    end,
    ok.

test_reports_process_label_info_in_process_scope(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).                       %L01\n",
                    ~"-export([go/1]).                    %L02\n",
                    ~"go(X) ->                            %L03\n",
                    ~"    proc_lib:set_label(test_label), %L04\n",
                    ~"    X * 5.                          %L05\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}, {line, 5}]}]),
    {ok, ThreadId, [#{id := FrameId1} | _]} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [10]}),
    ProcessVars1 = get_process_vars(Client, FrameId1),

    ?assertNot(maps:is_key(~"Process label", ProcessVars1)),

    edb_dap_test_client:continue(Client, #{threadId => ThreadId}),
    {ok, _, [#{id := FrameId2} | _]} = edb_dap_test_support:wait_for_bp(Client),
    ProcessVars2 = get_process_vars(Client, FrameId2),

    ?assertEqual(
        #{
            name => ~"Process label",
            value => ~"test_label",
            variablesReference => 0
        },
        maps:get(~"Process label", ProcessVars2)
    ),
    ok.

% -----------------------------------------------------------------------------
% Helpers
% -----------------------------------------------------------------------------
-spec get_variables_page(Client, VarRef, Window) -> [edb_dap_request_variables:variable()] when
    Client :: edb_dap_test_support:client(),
    VarRef :: number(),
    Window :: #{start => non_neg_integer(), count => non_neg_integer()}.
get_variables_page(Client, VarRef, Window) ->
    Args0 = #{variablesReference => VarRef},
    Args1 =
        case Window of
            #{start := Start, count := Count} ->
                Args0#{start => Start, count => Count};
            #{start := Start} ->
                Args0#{start => Start};
            #{count := Count} ->
                Args0#{count => Count};
            _ ->
                Args0
        end,
    case edb_dap_test_client:variables(Client, Args1) of
        #{
            command := ~"variables",
            type := response,
            success := true,
            body := #{variables := Vars}
        } ->
            Vars
    end.

-spec assertEvaluateNameIsCorrect(Client, FrameId, edb_dap_request_variables:variable(), binary()) -> ok when
    Client :: edb_dap_test_support:client(),
    FrameId :: number().
assertEvaluateNameIsCorrect(Client, FrameId, #{evaluateName := EvalName}, Expected) ->
    Response = edb_dap_test_client:evaluate(Client, #{
        expression => EvalName,
        frameId => FrameId,
        context => clipboard
    }),
    case Response of
        #{command := ~"evaluate", type := response, success := true, body := #{result := Result}} ->
            ?assertEqual(Expected, Result)
    end.

-spec get_process_vars(Client, FrameId) -> #{binary() => edb_dap_request_variables:variable()} when
    Client :: edb_dap_test_support:client(),
    FrameId :: number().
get_process_vars(Client, FrameId) ->
    Scopes = edb_dap_test_support:get_scopes(Client, FrameId),
    ProcessScopeVarsRef = maps:get(variablesReference, maps:get(~"Process", Scopes)),
    edb_dap_test_support:get_variables(Client, ProcessScopeVarsRef).
