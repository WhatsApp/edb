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

%% Session management tests for the EDB DAP adapter

-module(edb_dap_session_SUITE).

%% erlfmt:ignore
% @fb-only

% @fb-only
-include_lib("stdlib/include/assert.hrl").
-include_lib("edb/include/edb_dap.hrl").

%% CT callbacks
-export([
    all/0,
    groups/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    %% Initialization
    test_fails_if_not_initialized/1,
    test_fails_if_initialized_twice/1,
    test_fails_if_invalid_launch_config/1,

    %% Shutdown
    test_handles_disconnect_request/1,
    test_terminates_when_node_goes_down/1
]).

all() ->
    [
        {group, initialization},
        {group, shutdown}
    ].

groups() ->
    [
        {initialization, [
            test_fails_if_not_initialized,
            test_fails_if_initialized_twice,
            test_fails_if_invalid_launch_config
        ]},
        {shutdown, [
            test_handles_disconnect_request,
            test_terminates_when_node_goes_down
        ]}
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES -- Initialization
%%--------------------------------------------------------------------
test_fails_if_not_initialized(Config) ->
    {ok, Client} = edb_dap_test_support:start_test_client(Config),

    AdapterID = atom_to_binary(?MODULE),
    Response1 = edb_dap_test_client:set_breakpoints(Client, #{adapterID => AdapterID}),
    ?assertMatch(
        #{
            request_seq := 1,
            type := response,
            success := false,
            body := #{error := #{id := ?ERROR_SERVER_NOT_INITIALIZED}}
        },
        Response1
    ).

test_fails_if_initialized_twice(Config) ->
    {ok, Client} = edb_dap_test_support:start_test_client(Config),

    AdapterID = atom_to_binary(?MODULE),
    Response1 = edb_dap_test_client:initialize(Client, #{adapterID => AdapterID}),
    ?assertMatch(#{request_seq := 1, type := response, success := true}, Response1),

    AdapterID = atom_to_binary(?MODULE),
    Response2 = edb_dap_test_client:initialize(Client, #{adapterID => AdapterID}),
    ?assertMatch(
        #{
            request_seq := 2,
            type := response,
            success := false,
            body := #{error := #{id := ?JSON_RPC_ERROR_INVALID_REQUEST}}
        },
        Response2
    ).

test_fails_if_invalid_launch_config(Config) ->
    % Use a lower level API to be able to pass an invalid configuration
    {ok, Client} = edb_dap_test_support:start_test_client(Config),

    AdapterID = atom_to_binary(?MODULE),
    Response1 = edb_dap_test_client:initialize(Client, #{adapterID => AdapterID}),
    ?assertMatch(#{request_seq := 1, type := response, success := true}, Response1),

    Response2 = edb_dap_test_client:launch(Client, #{
        invalid => ~"invalid"
    }),
    ?assertMatch(
        #{
            request_seq := 2,
            type := response,
            success := false,
            body := #{error := #{id := ?JSON_RPC_ERROR_INVALID_PARAMS}}
        },
        Response2
    ).

%%--------------------------------------------------------------------
%% TEST CASES -- Shutdown
%%--------------------------------------------------------------------

test_handles_disconnect_request(Config) ->
    {ok, _Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),
    {ok, Client, _Cwd} = edb_dap_test_support:start_session(Config, Node, Cookie),

    DisconnectResponse = edb_dap_test_client:disconnect(Client, #{}),
    ?assertMatch(
        #{command := <<"disconnect">>, success := true},
        DisconnectResponse
    ),

    ok.

test_terminates_when_node_goes_down(Config) ->
    {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),
    {ok, Client, _Cwd} = edb_dap_test_support:start_session(Config, Node, Cookie),

    edb_test_support:stop_peer(Peer),

    {ok, ExitedEvent} = edb_dap_test_client:wait_for_event(~"exited", Client),
    ?assertMatch([#{event := ~"exited", body := #{exitCode := 0}}], ExitedEvent),

    {ok, TerminatedEvent} = edb_dap_test_client:wait_for_event(~"terminated", Client),
    ?assertMatch([#{event := ~"terminated", body := #{}}], TerminatedEvent),

    ok.
