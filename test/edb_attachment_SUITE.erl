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
%%

-module(edb_attachment_SUITE).

%% erlfmt:ignore
% @fb-only

% @fb-only
-include_lib("stdlib/include/assert.hrl").

%% Test server callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_raises_error_until_attached/1,

    test_can_attach_async_with_timeout/1,
    test_can_attach_async_with_infinity_timeout/1,
    test_fails_to_attach_after_timeout/1,
    test_attach_validates_args/1,

    test_querying_on_a_vanished_node_detaches/1,

    test_terminating_detaches/1,
    test_terminating_on_a_vanished_node_detaches/1,

    test_detaching_unsubscribes/1,

    test_reattaching_to_non_existent_node_doesnt_detach/1,
    test_reattaching_to_same_node_doesnt_detach/1,
    test_reattaching_to_different_node_detaches_from_old_node/1
]).

all() ->
    [
        test_raises_error_until_attached,

        test_can_attach_async_with_timeout,
        test_can_attach_async_with_infinity_timeout,
        test_fails_to_attach_after_timeout,
        test_attach_validates_args,

        test_querying_on_a_vanished_node_detaches,

        test_terminating_detaches,
        test_terminating_on_a_vanished_node_detaches,

        test_detaching_unsubscribes,

        test_reattaching_to_non_existent_node_doesnt_detach,
        test_reattaching_to_same_node_doesnt_detach,
        test_reattaching_to_different_node_detaches_from_old_node
    ].

init_per_testcase(_TestCase, Config) ->
    Config.
end_per_testcase(_TestCase, _Config) ->
    ok = edb_test_support:stop_event_collector(),
    ok = edb_test_support:stop_all_peer_nodes(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES

test_raises_error_until_attached(Config) ->
    % Initially, we are not attached to any node, so error on operations
    ?assertError(not_attached, edb:attached_node()),
    ?assertError(not_attached, edb:processes()),

    {ok, _Peer, Node, _Cookie} = edb_test_support:start_peer_node(Config, "debuggee"),

    % After attaching, we no longer error
    ok = edb:attach(#{node => Node}),
    ?assertMatch(Node, edb:attached_node()),
    ?assertMatch(#{}, edb:processes()),

    % After detaching, we error again
    ok = edb:detach(),
    ?assertError(not_attached, edb:attached_node()),
    ?assertError(not_attached, edb:processes()),

    ok.

test_can_attach_async_with_timeout(Config) ->
    NodeStartupDelayInMs = 500,
    AttachTimeout = NodeStartupDelayInMs * 10,
    test_can_attach_async(Config, NodeStartupDelayInMs, AttachTimeout).

test_can_attach_async_with_infinity_timeout(Config) ->
    NodeStartupDelayInMs = 500,
    test_can_attach_async(Config, NodeStartupDelayInMs, infinity).

test_can_attach_async(Config, NodeStartupDelayInMs, AttachTimeout) ->
    Node = edb_test_support:random_node("debuggee"),

    % Wait some time, then start the node
    TC = self(),
    Sentinel = spawn_link(fun() ->
        receive
        after NodeStartupDelayInMs -> ok
        end,
        {ok, Peer, Node, _Cookie} = edb_test_support:start_peer_node(Config, {exact, Node}),

        % Keep node alive
        receive
            stop ->
                peer:stop(Peer),
                TC ! {self(), stopped}
        end
    end),

    % In parallel, try to attach to the node with a timeout
    ok = edb:attach(#{node => Node, timeout => AttachTimeout}),
    ?assertEqual(Node, edb:attached_node()),

    Sentinel ! stop,
    receive
        {Sentinel, stopped} -> ok
    end,

    ok.

test_fails_to_attach_after_timeout(_Config) ->
    Node = edb_test_support:random_node("non-existent-debuggee"),
    {error, nodedown} = edb:attach(#{node => Node, timeout => 100}),
    ok.

test_attach_validates_args(_Config) ->
    ?assertError({badarg, {missing, node}}, edb:attach(#{})),
    ?assertError({badarg, #{node := ~"not a node"}}, edb:attach(#{node => ~"not a node"})),

    Args = #{node => edb_test_support:random_node("debuggee")},
    ?assertError({badarg, #{timeout := nan}}, edb:attach(Args#{timeout => nan})),

    ?assertError({badarg, {unknown, [foo]}}, edb:attach(Args#{foo => bar})),
    ?assertError({badarg, {unknown, [foo, hey]}}, edb:attach(Args#{foo => bar, hey => ho})),
    ok.

test_querying_on_a_vanished_node_detaches(Config) ->
    {ok, Peer, Node, _Cookie} = edb_test_support:start_peer_node(Config, "debuggee"),
    ok = edb:attach(#{node => Node}),
    ok = edb_test_support:start_event_collector(),

    % Sanity check: no errors while attached
    ?assertMatch(#{}, edb:processes()),

    % Kill the node, we will be detached
    ok = edb_test_support:stop_peer_node(Peer),
    ?assertError(not_attached, edb:processes()),

    % Verify we get a nodedown event
    ?assertEqual(
        [{nodedown, Node, connection_closed}],
        edb_test_support:collected_events()
    ),
    ok.

test_terminating_detaches(Config) ->
    {ok, _Peer, Node, _Cookie} = edb_test_support:start_peer_node(Config, "debuggee"),

    % Sanity check: no errors while attached
    edb:attach(#{node => Node}),
    ?assertMatch(Node, edb:attached_node()),

    % We error after stopping the session
    ok = edb:terminate(),
    ?assertError(not_attached, edb:attached_node()),

    % No errrors if we re-attach
    edb:attach(#{node => Node}),
    ?assertMatch(Node, edb:attached_node()),

    ok.

test_terminating_on_a_vanished_node_detaches(Config) ->
    {ok, Peer, Node, _Cookie} = edb_test_support:start_peer_node(Config, "debuggee"),
    edb:attach(#{node => Node}),

    % Sanity check: no errors while attached
    edb:attach(#{node => Node}),
    ?assertEqual(Node, edb:attached_node()),

    % Kill the peer node, we now fail to stop
    ok = edb_test_support:stop_peer_node(Peer),

    ?assertError(not_attached, edb:terminate()),
    ?assertError(not_attached, edb:attached_node()),
    ok.

test_detaching_unsubscribes(Config) ->
    {ok, _Peer, Node, _Cookie} = edb_test_support:start_peer_node(Config, "debuggee"),
    edb:attach(#{node => Node}),
    ok = edb_test_support:start_event_collector(),

    ok = edb:detach(),

    ?assertEqual(
        [
            unsubscribed
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_reattaching_to_non_existent_node_doesnt_detach(Config) ->
    {ok, _Peer, Node, _Cookie} = edb_test_support:start_peer_node(Config, "debuggee"),

    ok = edb:attach(#{node => Node}),
    ok = edb_test_support:start_event_collector(),

    % Let the event collector get an event
    {ok, SyncRef1} = edb_test_support:event_collector_send_sync(),

    NonExistentNode = edb_test_support:random_node(~"nonexistent-node"),
    ?assertEqual(
        {error, nodedown},
        edb:attach(#{node => NonExistentNode})
    ),

    % The event collector should still be subscribed and receiving events
    {ok, SyncRef2} = edb_test_support:event_collector_send_sync(),

    % Still attached to the original node
    ?assertMatch(Node, edb:attached_node()),

    edb:detach(),

    % Verify that all events were received
    ?assertEqual(
        [
            {sync, SyncRef1},
            {sync, SyncRef2},
            unsubscribed
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_reattaching_to_same_node_doesnt_detach(Config) ->
    {ok, _Peer, Node, _Cookie} = edb_test_support:start_peer_node(Config, "debuggee"),

    ok = edb:attach(#{node => Node}),
    ?assertEqual(edb:attached_node(), Node),

    ok = edb_test_support:start_event_collector(),

    % Let the event collector get an event
    {ok, SyncRef1} = edb_test_support:event_collector_send_sync(),

    % Re-attach to the same node, should be a no-op
    ok = edb:attach(#{node => Node}),
    ?assertEqual(edb:attached_node(), Node),

    % The event collector should still be subscribed and receiving events
    {ok, SyncRef2} = edb_test_support:event_collector_send_sync(),

    edb:detach(),

    % Verify that all events were received
    ?assertEqual(
        [
            {sync, SyncRef1},
            {sync, SyncRef2},
            unsubscribed
        ],
        edb_test_support:collected_events()
    ),

    ok.

test_reattaching_to_different_node_detaches_from_old_node(Config) ->
    {ok, _Peer1, Node1, Cookie} = edb_test_support:start_peer_node(Config, "debuggee_1"),
    {ok, _Peer2, Node2, Cookie} = edb_test_support:start_peer_node(Config, "debuggee_2"),

    ok = edb:attach(#{node => Node1}),
    ?assertEqual(edb:attached_node(), Node1),

    ok = edb_test_support:start_event_collector(),

    % Let the event collector get an event
    {ok, SyncRef} = edb_test_support:event_collector_send_sync(),

    % Attach to a different node
    ok = edb:attach(#{node => Node2}),
    ?assertEqual(edb:attached_node(), Node2),

    ?assertEqual(
        [{sync, SyncRef}, unsubscribed],
        edb_test_support:collected_events()
    ),

    ok.