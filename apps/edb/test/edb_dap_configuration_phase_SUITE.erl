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

%% Tests handling of the "configuration phase" of the DAP protocol.
-module(edb_dap_configuration_phase_SUITE).

-oncall("whatsapp_server_devx").

%% CT callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_queries_fail_until_configured/1,
    test_setting_breakpoints_work_before_and_after_configuration/1
]).

all() ->
    [
        test_queries_fail_until_configured,
        test_setting_breakpoints_work_before_and_after_configuration
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_queries_fail_until_configured(Config) ->
    {ok, Client, _PeerInfo} = edb_dap_test_support:start_session_via_launch(Config, #{}),

    % At this point we are not configured, so querying should fail
    #{success := false, body := #{error := #{format := ~"Request sent when it was not expected"}}} =
        edb_dap_test_client:threads(Client),

    #{success := true} = edb_dap_test_client:configuration_done(Client),

    % Same request succeeds now that we are configured
    #{success := true} = edb_dap_test_client:threads(Client),

    ok.

test_setting_breakpoints_work_before_and_after_configuration(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).         % L01\n",
                    ~"-export([go/0]).      % L02\n",
                    ~"                      % L03\n",
                    ~"go() ->               % L04\n",
                    ~"    keep_going().     % L05\n",
                    ~"                      % L06\n",
                    ~"keep_going() ->       % L07\n",
                    ~"    bam.              % L08\n"
                ]}
            ]
        }),

    % Set an initial breakpoint during configuration
    ok = edb_dap_test_support:set_breakpoints(Client, FooSrc, [5]),

    % Finish configuration
    #{success := true} = edb_dap_test_client:configuration_done(Client),

    % Launch a process and check the breakpoint works
    {ok, ThreadId, [#{line := 5, name := ~"foo:go/0"} | _]} =
        edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, []}),

    % Set a new breakpoint on another line and check we get that breakpoint
    ok = edb_dap_test_support:set_breakpoints(Client, FooSrc, [8]),
    #{success := true} = edb_dap_test_client:continue(Client, #{threadId => ThreadId}),
    {ok, ThreadId, [#{line := 8, name := ~"foo:keep_going/0"} | _]} = edb_dap_test_support:wait_for_bp(Client),

    ok.
