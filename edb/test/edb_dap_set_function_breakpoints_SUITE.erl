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

%% Tests for the "setFunctionBreakpoints" request of the EDB DAP server

-module(edb_dap_set_function_breakpoints_SUITE).

%% erlfmt:ignore
% @fb-only: -oncall("whatsapp_server_devx").
-typing([eqwalizer]).

-include_lib("assert/include/assert.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_simple_function_breakpoint/1,
    test_multiple_function_breakpoints/1,
    test_all_function_name_formats/1,
    test_error_invalid_name/1,
    test_error_function_not_found/1
]).

all() ->
    [
        test_simple_function_breakpoint,
        test_multiple_function_breakpoints,
        test_all_function_name_formats,
        test_error_invalid_name,
        test_error_function_not_found
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_simple_function_breakpoint(Config) ->
    {ok, Client, #{peer := Peer}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).               %L01\n",
                    ~"-export([go/0, bar/1]).     %L02\n",
                    ~"go() ->                     %L03\n",
                    ~"    bar(42).                %L04\n",
                    ~"bar(X) ->                   %L05\n",
                    ~"    X + 1.                  %L06\n"
                ]}
            ],
            compile_flags => [debug_info, beam_debug_info]
        }),

    Response = edb_dap_test_client:set_function_breakpoints(Client, #{
        breakpoints => [#{name => ~"foo:bar/1"}]
    }),

    ?assertMatch(
        #{
            command := ~"setFunctionBreakpoints",
            type := response,
            success := true,
            body := #{
                breakpoints := [#{verified := true}]
            }
        },
        Response
    ),

    ok = edb_dap_test_support:configure(Client, []),

    {ok, ThreadId, StackFrames} = spawn_and_wait_for_function_bp(Client, Peer, {foo, go, []}),

    ?assertMatch([#{name := ~"foo:bar/1", line := 6} | _], StackFrames),

    edb_dap_test_client:continue(Client, #{threadId => ThreadId}),
    ok.

test_multiple_function_breakpoints(Config) ->
    {ok, Client, #{peer := Peer}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).               %L01\n",
                    ~"-export([go/0]).            %L02\n",
                    ~"go() ->                     %L03\n",
                    ~"    bar(42),                %L04\n",
                    ~"    baz(10),                %L05\n",
                    ~"    qux(5).                 %L06\n",
                    ~"bar(X) ->                   %L07\n",
                    ~"    X + 1.                  %L08\n",
                    ~"baz(Y) ->                   %L09\n",
                    ~"    Y * 2.                  %L10\n",
                    ~"qux(Z) ->                   %L11\n",
                    ~"    Z * 3.                  %L12\n"
                ]}
            ],
            compile_flags => [debug_info, beam_debug_info]
        }),

    Response = edb_dap_test_client:set_function_breakpoints(Client, #{
        breakpoints => [
            #{name => ~"foo:bar/1"},
            #{name => ~"invalid_name"},
            #{name => ~"foo:baz/1"},
            #{name => ~"foo:nonexistent/1"},
            #{name => ~"foo:qux/1"}
        ]
    }),

    ?assertMatch(
        #{
            command := ~"setFunctionBreakpoints",
            type := response,
            success := true,
            body := #{
                breakpoints := [
                    #{verified := true},
                    #{
                        verified := false,
                        message := ~"Not a valid function name. Valid formats: `M:F/A`; `fun M:F/A`; {M, F, A}",
                        reason := ~"failed"
                    },
                    #{verified := true},
                    #{
                        verified := false,
                        message := ~"The function does not exist or the module was not found",
                        reason := ~"failed"
                    },
                    #{verified := true}
                ]
            }
        },
        Response
    ),

    ok = edb_dap_test_support:configure(Client, []),

    {ok, ThreadId1, ST1} = spawn_and_wait_for_function_bp(Client, Peer, {foo, go, []}),
    ?assertMatch([#{name := ~"foo:bar/1", line := 8} | _], ST1),

    edb_dap_test_client:continue(Client, #{threadId => ThreadId1}),

    {ok, ThreadId2, ST2} = wait_for_function_bp(Client),
    ?assertMatch([#{name := ~"foo:baz/1", line := 10} | _], ST2),

    edb_dap_test_client:continue(Client, #{threadId => ThreadId2}),

    {ok, ThreadId3, ST3} = wait_for_function_bp(Client),
    ?assertMatch([#{name := ~"foo:qux/1", line := 12} | _], ST3),

    edb_dap_test_client:continue(Client, #{threadId => ThreadId3}),
    ok.

test_all_function_name_formats(Config) ->
    {ok, Client, #{peer := Peer}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).               %L01\n",
                    ~"-export([go/0]).            %L02\n",
                    ~"go() ->                     %L03\n",
                    ~"    bar(42),                %L04\n",
                    ~"    baz(10),                %L05\n",
                    ~"    qux(5).                 %L06\n",
                    ~"bar(X) ->                   %L07\n",
                    ~"    X + 1.                  %L08\n",
                    ~"baz(Y) ->                   %L09\n",
                    ~"    Y * 2.                  %L10\n",
                    ~"qux(Z) ->                   %L11\n",
                    ~"    Z * 3.                  %L12\n"
                ]}
            ],
            compile_flags => [debug_info, beam_debug_info]
        }),

    Response = edb_dap_test_client:set_function_breakpoints(Client, #{
        breakpoints => [
            #{name => ~"foo:bar/1"},
            #{name => ~"fun foo:baz/1"},
            #{name => ~"{foo, qux, 1}"}
        ]
    }),

    ?assertMatch(
        #{
            command := ~"setFunctionBreakpoints",
            type := response,
            success := true,
            body := #{
                breakpoints := [
                    #{verified := true},
                    #{verified := true},
                    #{verified := true}
                ]
            }
        },
        Response
    ),

    ok = edb_dap_test_support:configure(Client, []),

    {ok, ThreadId1, ST1} = spawn_and_wait_for_function_bp(Client, Peer, {foo, go, []}),
    ?assertMatch([#{name := ~"foo:bar/1", line := 8} | _], ST1),

    edb_dap_test_client:continue(Client, #{threadId => ThreadId1}),

    {ok, ThreadId2, ST2} = wait_for_function_bp(Client),
    ?assertMatch([#{name := ~"foo:baz/1", line := 10} | _], ST2),

    edb_dap_test_client:continue(Client, #{threadId => ThreadId2}),

    {ok, ThreadId3, ST3} = wait_for_function_bp(Client),
    ?assertMatch([#{name := ~"foo:qux/1", line := 12} | _], ST3),

    edb_dap_test_client:continue(Client, #{threadId => ThreadId3}),
    ok.

test_error_invalid_name(Config) ->
    {ok, Client, #{}} = edb_dap_test_support:start_session_via_launch(Config, #{
        modules => [
            {source, [
                ~"-module(foo).               %L01\n",
                ~"-export([bar/1]).           %L02\n",
                ~"bar(X) ->                   %L03\n",
                ~"    X + 1.                  %L04\n"
            ]}
        ],
        compile_flags => [debug_info, beam_debug_info]
    }),
    ok = edb_dap_test_support:configure(Client, []),

    Response = edb_dap_test_client:set_function_breakpoints(Client, #{
        breakpoints => [
            #{name => ~"not_a_valid_function_name"},
            #{name => ~"foo:bar/1"}
        ]
    }),

    ?assertMatch(
        #{
            command := ~"setFunctionBreakpoints",
            type := response,
            success := true,
            body := #{
                breakpoints := [
                    #{
                        verified := false,
                        message := ~"Not a valid function name. Valid formats: `M:F/A`; `fun M:F/A`; {M, F, A}",
                        reason := ~"failed"
                    },
                    #{verified := true}
                ]
            }
        },
        Response
    ),
    ok.

test_error_function_not_found(Config) ->
    {ok, Client, #{}} = edb_dap_test_support:start_session_via_launch(Config, #{}),
    ok = edb_dap_test_support:configure(Client, []),

    Response = edb_dap_test_client:set_function_breakpoints(Client, #{
        breakpoints => [#{name => ~"nonexistent:func/0"}]
    }),

    ?assertMatch(
        #{
            command := ~"setFunctionBreakpoints",
            type := response,
            success := true,
            body := #{
                breakpoints := [
                    #{
                        verified := false,
                        message := ~"The function does not exist or the module was not found",
                        reason := ~"failed"
                    }
                ]
            }
        },
        Response
    ),
    ok.

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------
-spec spawn_and_wait_for_function_bp(Client, Peer, {M, F, Args}) -> {ok, ThreadId, StackFrames} when
    Client :: edb_dap_test_client:client(),
    Peer :: edb_test_support:peer(),
    M :: module(),
    F :: atom(),
    Args :: [term()],
    ThreadId :: integer(),
    StackFrames :: [edb_dap_request_stack_trace:stack_frame()].
spawn_and_wait_for_function_bp(Client, Peer, {M, F, Args}) ->
    erlang:spawn(fun() -> peer:call(Peer, M, F, Args) end),
    wait_for_function_bp(Client).

-spec wait_for_function_bp(Client) -> {ok, ThreadId, StackFrames} when
    Client :: edb_dap_test_client:client(),
    ThreadId :: integer(),
    StackFrames :: [edb_dap_request_stack_trace:stack_frame()].
wait_for_function_bp(Client) ->
    {ok, [StoppedEvent]} = edb_dap_test_client:wait_for_event(~"stopped", Client),
    ThreadId =
        case StoppedEvent of
            #{
                event := ~"stopped",
                body := #{
                    reason := ~"function_breakpoint",
                    preserveFocusHint := false,
                    threadId := ThreadId_,
                    allThreadsStopped := true
                }
            } when is_integer(ThreadId_) ->
                ThreadId_;
            UnexpectedStopped ->
                error({unexpected_stopped_event, UnexpectedStopped})
        end,
    case edb_dap_test_client:stack_trace(Client, #{threadId => ThreadId}) of
        #{
            type := response,
            success := true,
            body := #{stackFrames := StackFrames = _}
        } ->
            {ok, ThreadId, StackFrames};
        UnexpectedStackTrace ->
            error({unexpected_stack_trace, UnexpectedStackTrace})
    end.
