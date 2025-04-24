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
    test_reports_locals_scope_nested_variables/1,
    test_reports_registers_scope_when_locals_not_available/1,
    test_reports_messages_scope/1
]).

all() ->
    [
        test_reports_locals_scope,
        test_reports_locals_scope_nested_variables,
        test_reports_registers_scope_when_locals_not_available,
        test_reports_messages_scope
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

test_reports_locals_scope_nested_variables(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [~"""
                    -module(foo).            %L01\n
                    -export([go/2]).         %L02\n
                    go(L, X) ->              %L03\n
                        M = [4, [], {6, 7}], %L04\n
                        {L ++ M, X}.         %L05\n
                """]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 5}]}]),
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
                            variablesReference => 1
                        }
                },
                Scopes
            ),

            VarRef = maps:get(variablesReference, maps:get(~"Locals", Scopes)),
            LocalVars = edb_dap_test_support:get_variables(Client, VarRef),
            ?assertEqual(
                #{
                    ~"L" => #{name => ~"L", value => ~"[1,2,3]", variablesReference => 2},
                    ~"M" => #{name => ~"M", value => ~"[4,[],{6,7}]", variablesReference => 3},
                    ~"X" => #{name => ~"X", value => ~"#{life => 42}", variablesReference => 4}
                },
                LocalVars
            ),

            ChildListVarRef = maps:get(variablesReference, maps:get(~"M", LocalVars)),
            ChildrenListVars = edb_dap_test_support:get_variables(Client, ChildListVarRef),
            ?assertEqual(
                #{
                    ~"1" => #{name => ~"1", value => ~"4", variablesReference => 0},
                    ~"2" => #{name => ~"2", value => ~"[]", variablesReference => 5},
                    ~"3" => #{name => ~"3", value => ~"{6,7}", variablesReference => 6}
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
                    ~"Y0" := #{name := ~"Y0", value := _, variablesReference := 2},
                    ~"Y1" := #{name := ~"Y1", value := _, variablesReference := 0},
                    ~"Y2" := #{name := ~"Y2", value := _, variablesReference := 0}
                },
                RegVars
            )
    end,
    ok.

test_reports_messages_scope(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).      %L01\n",
                    ~"-export([go/2]).   %L02\n",
                    ~"go(X, Y) ->        %L03\n",
                    ~"    self() ! hola, %L04\n",
                    ~"    X + 2 * Y.     %L05\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 5}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [42, 7]}),
    case ST of
        [_, #{id := NonTopFrameId} | _] ->
            Scopes = edb_dap_test_support:get_scopes(Client, NonTopFrameId),
            ?assertEqual(
                #{
                    ~"Messages" =>
                        #{
                            name => ~"Messages",
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

            VarRef = maps:get(variablesReference, maps:get(~"Messages", Scopes)),
            RegVars = edb_dap_test_support:get_variables(Client, VarRef),
            ?assertMatch(
                #{
                    ~"0" := #{name := ~"0", value := _, variablesReference := 0}
                },
                RegVars
            )
    end,
    ok.
