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

%% Stepping tests for the EDB DAP adapter

-module(edb_dap_steps_SUITE).

%% erlfmt:ignore
% @fb-only
-typing([eqwalizer]).

-include_lib("assert/include/assert.hrl").

%% CT callbacks
-export([all/0]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases
-export([test_next_works/1]).
-export([test_step_out_works/1]).
-export([test_step_in_works/1]).
-export([test_stepping_errors_if_process_not_paused/1]).
-export([test_step_in_errors_on_wrong_target/1]).
-export([test_step_in_error_on_module_not_found/1]).
-export([test_step_in_error_on_function_not_found/1]).

all() ->
    [
        test_next_works,
        test_step_out_works,
        test_step_in_works,

        test_stepping_errors_if_process_not_paused,
        test_step_in_errors_on_wrong_target,
        test_step_in_error_on_module_not_found,
        test_step_in_error_on_function_not_found
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_next_works(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).             %L01\n",
                    ~"-export([go/0]).          %L02\n",
                    ~"go() ->                   %L03\n",
                    ~"    X = f(23),            %L04\n",
                    ~"    Y = h(                %L05\n",
                    ~"         Z = f(X),        %L06\n",
                    ~"        [foo, bar]        %L07\n",
                    ~"    ),                    %L08\n",
                    ~"    Y + Z.                %L09\n",
                    ~"                          %L10\n",
                    ~"f(X) ->                   %L11\n",
                    ~"    X * 3 + 1.            %L12\n",
                    ~"                          %L13\n",
                    "h(X, Y) ->                 %L14\n",
                    ~"    X + 2 * length(Y).    %L15\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, ThreadId, ST0} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, []}),

    % Sanity-check: we are on line 4
    ?assertMatch([#{name := ~"foo:go/0", line := 4} | _], ST0),

    % Next!
    do_next_and_wait_until_stopped(Client, ThreadId),
    ?assertEqual(
        #{name => ~"foo:go/0", line => 5, vars => #{~"X" => ~"70"}},
        edb_dap_test_support:get_top_frame(Client, ThreadId)
    ),

    % Next again
    do_next_and_wait_until_stopped(Client, ThreadId),
    ?assertEqual(
        #{name => ~"foo:go/0", line => 6, vars => #{~"X" => ~"70"}},
        edb_dap_test_support:get_top_frame(Client, ThreadId)
    ),

    % Next one more time
    do_next_and_wait_until_stopped(Client, ThreadId),
    ?assertEqual(
        #{name => ~"foo:go/0", line => 7, vars => #{~"Z" => ~"211"}},
        edb_dap_test_support:get_top_frame(Client, ThreadId)
    ),

    ok.

test_step_out_works(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).             %L01\n",
                    ~"-export([go/0]).          %L02\n",
                    ~"go() ->                   %L03\n",
                    ~"    X = f(23),            %L04\n",
                    ~"    X + 42.               %L05\n",
                    ~"                          %L06\n",
                    ~"f(X) ->                   %L07\n",
                    ~"    Y = g(X * 3 + 1),     %L08\n",
                    ~"    Y * X.                %L09\n",
                    ~"                          %L10\n",
                    "g(X) ->                    %L11\n",
                    ~"    Y = X + 2,            %L12\n",
                    ~"    Y * 3.                %L13\n",
                    ~""
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 12}]}]),
    {ok, ThreadId, ST0} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, []}),

    % Sanity-check: we are on line 12
    ?assertMatch([#{name := ~"foo:g/1", line := 12} | _], ST0),

    % Step-out!
    do_step_out_and_wait_until_stopped(Client, ThreadId),
    ?assertEqual(
        #{name => ~"foo:f/1", line => 9, vars => #{~"X" => ~"23", ~"Y" => ~"216"}},
        edb_dap_test_support:get_top_frame(Client, ThreadId)
    ),

    % Step-out! again
    do_step_out_and_wait_until_stopped(Client, ThreadId),
    ?assertEqual(
        #{name => ~"foo:go/0", line => 5, vars => #{~"X" => ~"4968"}},
        edb_dap_test_support:get_top_frame(Client, ThreadId)
    ),

    ok.

test_step_in_works(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).             %L01\n",
                    ~"-export([go/0]).          %L02\n",
                    ~"go() ->                   %L03\n",
                    ~"    f(23).                %L04\n",
                    ~"                          %L05\n",
                    ~"f(X) ->                   %L06\n",
                    ~"    X + 1.                %L07\n",
                    ~""
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, ThreadId, ST0} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, []}),

    % Sanity-check: we are on line 4
    ?assertMatch([#{name := ~"foo:go/0", line := 4} | _], ST0),

    % Step-in!
    do_step_in_and_wait_until_stopped(Client, ThreadId),
    ?assertEqual(
        #{name => ~"foo:f/1", line => 7, vars => #{~"X" => ~"23"}},
        edb_dap_test_support:get_top_frame(Client, ThreadId)
    ),

    ok.

test_stepping_errors_if_process_not_paused(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).             %L01\n",
                    ~"-export([go/0]).          %L02\n",
                    ~"go() ->                   %L03\n",
                    ~"    receive               %L04\n",
                    ~"        _ -> ok           %L05\n",
                    ~"    end.                  %L06\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, ThreadId, _ST0} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, []}),

    ContinueResponse = edb_dap_test_client:continue(Client, #{threadId => ThreadId}),
    ?assertMatch(#{success := true, body := #{allThreadsContinued := true}}, ContinueResponse),

    NextResponse = edb_dap_test_client:next(Client, #{threadId => ThreadId}),
    ?assertMatch(
        #{
            command := ~"next",
            success := false,
            body := #{
                error := #{format := ~"Process is not paused"}
            }
        },
        NextResponse
    ),

    StepInResponse = edb_dap_test_client:step_in(Client, #{threadId => ThreadId}),
    ?assertMatch(
        #{
            command := ~"stepIn",
            success := false,
            body := #{
                error := #{format := ~"Process is not paused"}
            }
        },
        StepInResponse
    ),

    StepOutResponse = edb_dap_test_client:step_out(Client, #{threadId => ThreadId}),
    ?assertMatch(
        #{
            command := ~"stepOut",
            success := false,
            body := #{
                error := #{format := ~"Process is not paused"}
            }
        },
        StepOutResponse
    ),
    ok.

test_step_in_errors_on_wrong_target(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).             %L01\n",
                    ~"-export([go/0]).          %L02\n",
                    ~"go() ->                   %L03\n",
                    ~"    ok.                   %L04\n",
                    ~""
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, ThreadId, _ST0} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, []}),

    StepInResponse = edb_dap_test_client:step_in(Client, #{threadId => ThreadId}),
    ?assertMatch(
        #{
            command := ~"stepIn",
            success := false,
            body := #{
                error := #{format := ~"Couldn't determine call target"}
            }
        },
        StepInResponse
    ),

    ok.

test_step_in_error_on_module_not_found(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).                     %L01\n",
                    ~"-export([go/0]).                  %L02\n",
                    ~"go() ->                           %L03\n",
                    ~"    non_existent_mod:blah().      %L04\n",
                    ~""
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, ThreadId, _ST0} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, []}),

    StepInResponse = edb_dap_test_client:step_in(Client, #{threadId => ThreadId}),
    ?assertMatch(
        #{
            command := ~"stepIn",
            success := false,
            body := #{
                error := #{format := ~"Target module 'non_existent_mod' couldn't be loaded"}
            }
        },
        StepInResponse
    ),

    ok.

test_step_in_error_on_function_not_found(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).           %L01\n",
                    ~"-export([go/0]).        %L02\n",
                    ~"go() ->                 %L03\n",
                    ~"    erlang:blah().      %L04\n",
                    ~""
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, ThreadId, _ST0} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, []}),

    StepInResponse = edb_dap_test_client:step_in(Client, #{threadId => ThreadId}),
    ?assertMatch(
        #{
            command := ~"stepIn",
            success := false,
            body := #{
                error := #{format := ~"Target function 'erlang:blah/0' not found"}
            }
        },
        StepInResponse
    ),

    ok.

%%--------------------------------------------------------------------
%% Helpers
%% -------------------------------------------------------------------

-spec do_next_and_wait_until_stopped(Client, ThreadId) -> ok when
    Client :: edb_dap_test_client:client(),
    ThreadId :: integer().
do_next_and_wait_until_stopped(Client, ThreadId) ->
    NextResponse = edb_dap_test_client:next(Client, #{threadId => ThreadId}),
    ?assertMatch(
        #{command := ~"next", type := response, success := true},
        NextResponse
    ),
    wait_for_stopped_event_with_step_reason(Client, ThreadId).

-spec do_step_out_and_wait_until_stopped(Client, ThreadId) -> ok when
    Client :: edb_dap_test_client:client(),
    ThreadId :: integer().
do_step_out_and_wait_until_stopped(Client, ThreadId) ->
    NextResponse = edb_dap_test_client:step_out(Client, #{threadId => ThreadId}),
    ?assertMatch(
        #{command := ~"stepOut", type := response, success := true},
        NextResponse
    ),
    wait_for_stopped_event_with_step_reason(Client, ThreadId).

-spec do_step_in_and_wait_until_stopped(Client, ThreadId) -> ok when
    Client :: edb_dap_test_client:client(),
    ThreadId :: integer().
do_step_in_and_wait_until_stopped(Client, ThreadId) ->
    NextResponse = edb_dap_test_client:step_in(Client, #{threadId => ThreadId}),
    ?assertMatch(
        #{command := ~"stepIn", type := response, success := true},
        NextResponse
    ),
    wait_for_stopped_event_with_step_reason(Client, ThreadId).

-spec wait_for_stopped_event_with_step_reason(Client, ThreadId) -> ok when
    Client :: edb_dap_test_client:client(),
    ThreadId :: integer().
wait_for_stopped_event_with_step_reason(Client, ThreadId) ->
    {ok, [StoppedEvent]} = edb_dap_test_client:wait_for_event(~"stopped", Client),
    ?assertMatch(
        #{
            event := ~"stopped",
            body := #{reason := ~"step", preserveFocusHint := false, threadId := ThreadId, allThreadsStopped := true}
        },
        StoppedEvent
    ),
    ok.
