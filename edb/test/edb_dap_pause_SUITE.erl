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

%% Pause/continue for the EDB DAP adapter

-module(edb_dap_pause_SUITE).

%% erlfmt:ignore
% @fb-only

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
    test_can_pause_and_continue/1
]).

all() ->
    [
        test_can_pause_and_continue
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_can_pause_and_continue(Config) ->
    {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),
    {ok, Client, _Cwd} = edb_dap_test_support:start_session(Config, Node, Cookie),
    ModuleSource = erlang:iolist_to_binary([
        ~"-module(foo).               %L01\n",
        ~"-export([go/0]).            %L02\n",
        ~"go() ->                     %L03\n",
        ~"    timer:sleep(infinity),  %L04\n",
        ~"    ok.                     %L05\n"
    ]),
    {ok, ThreadId, ST0} = edb_dap_test_support:ensure_process_in_bp(
        Config, Client, Peer, {source, ModuleSource}, go, [], {line, 4}
    ),

    % Sanity-check: we are on line 4
    ?assertMatch([#{name := ~"foo:go/0", line := 4} | _], ST0),

    % Continue!
    ContinueResponse = edb_dap_test_client:continue(Client, ThreadId),
    ?assertMatch(
        #{
            command := ~"continue",
            type := response,
            success := true,
            body := #{
                allThreadsContinued := true
            }
        },
        ContinueResponse
    ),

    % Pause!
    PauseResponse = edb_dap_test_client:pause(Client, ThreadId),
    EmptyBody = #{},
    ?assertMatch(
        #{
            command := ~"pause",
            type := response,
            success := true,
            body := EmptyBody
        },
        PauseResponse
    ),

    wait_for_stopped_event_with_pause_reason(Client),

    ok.

%%--------------------------------------------------------------------
%% Helpers
%% -------------------------------------------------------------------

-spec wait_for_stopped_event_with_pause_reason(Client) -> ok when
    Client :: edb_dap_test_client:client().
wait_for_stopped_event_with_pause_reason(Client) ->
    {ok, [StoppedEvent]} = edb_dap_test_client:wait_for_event(~"stopped", Client),
    ?assertMatch(
        #{
            event := ~"stopped",
            body := #{
                reason := ~"pause",
                preserveFocusHint := true,
                allThreadsStopped := true
            }
        },
        StoppedEvent
    ),
    ok.
