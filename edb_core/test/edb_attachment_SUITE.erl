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
    suite/0,
    all/0,
    groups/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Attach test-cases
-export([
    test_raises_error_until_attached/1,
    test_attaching_injects_edb_server/1,

    test_can_attach_async_with_timeout/1,
    test_can_attach_async_with_infinity_timeout/1,
    test_fails_to_attach_after_timeout/1,
    test_can_attach_with_specific_cookie/1,
    test_attach_validates_args/1,
    test_fails_to_attach_if_debuggee_not_in_debugging_mode/1
]).

%% Detach test-cases
-export([
    test_querying_on_a_vanished_node_detaches/1,

    test_terminating_detaches/1,
    test_terminating_on_a_vanished_node_detaches/1,

    test_detaching_unsubscribes/1,

    test_reattaching_to_non_existent_node_doesnt_detach/1,
    test_reattaching_to_same_node_doesnt_detach/1,
    test_reattaching_to_different_node_detaches_from_old_node/1
]).

%% erlfmt:ignore
suite() ->
    [
        % @fb-only
        {timetrap, {seconds, 30}}
    ].

all() ->
    [
        {group, test_attach},
        {group, test_detach}
    ].

groups() ->
    [
        {test_attach, [
            test_raises_error_until_attached,
            test_attaching_injects_edb_server,

            test_can_attach_async_with_timeout,
            test_can_attach_async_with_infinity_timeout,
            test_fails_to_attach_after_timeout,
            test_can_attach_with_specific_cookie,
            test_attach_validates_args,

            test_fails_to_attach_if_debuggee_not_in_debugging_mode
        ]},

        {test_detach, [
            test_querying_on_a_vanished_node_detaches,

            test_terminating_detaches,
            test_terminating_on_a_vanished_node_detaches,

            test_detaching_unsubscribes,

            test_reattaching_to_non_existent_node_doesnt_detach,
            test_reattaching_to_same_node_doesnt_detach,
            test_reattaching_to_different_node_detaches_from_old_node
        ]}
    ].

init_per_testcase(_TestCase, Config) ->
    {ok, _} = application:ensure_all_started(edb_core),
    Config.
end_per_testcase(_TestCase, _Config) ->
    ok = edb_test_support:stop_event_collector(),
    ok = edb_test_support:stop_all_peers(),
    % ok = application:stop(edb_core),  % @oss-only
    ok.

test_raises_error_until_attached(Config) ->
    % Initially, we are not attached to any node, so error on operations
    ?assertError(not_attached, edb:attached_node()),
    ?assertError(not_attached, edb:processes()),

    {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),

    % Sanity-check: edb_server is not available in the peer
    ?assertEqual(
        non_existing,
        peer:call(Peer, code, which, [edb_server])
    ),

    % After attaching, edb_server is now loaded and we no longer error
    ok = edb:attach(#{node => Node, cookie => Cookie}),
    ?assertMatch({file, _}, peer:call(Peer, code, is_loaded, [edb_server])),
    ?assertMatch(Node, edb:attached_node()),
    ?assertMatch(#{}, edb:processes()),

    % After detaching, we error again
    ok = edb:detach(),
    ?assertError(not_attached, edb:attached_node()),
    ?assertError(not_attached, edb:processes()),

    ok.

test_attaching_injects_edb_server(Config) ->
    {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),

    % Initially edb_server is not available in the debuggee
    ?assertEqual(
        non_existing,
        peer:call(Peer, code, which, [edb_server])
    ),

    % After attaching, edb_server is now loaded and running
    ok = edb:attach(#{node => Node, cookie => Cookie}),
    ?assertMatch({file, _}, peer:call(Peer, code, is_loaded, [edb_server])),
    EdbServerPid = peer:call(Peer, edb_server, find, []),
    ?assert(is_pid(EdbServerPid)),

    % After detaching, edb_server is still running
    ok = edb:detach(),

    % Reattaching with a running edb_server doesn't change the server
    ok = edb:attach(#{node => Node}),
    ?assertEqual(
        EdbServerPid,
        peer:call(Peer, edb_server, find, [])
    ),
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

    Cookie = 'some_cookie',

    % Wait some time, then start the node
    TC = self(),
    Sentinel = spawn_link(fun() ->
        receive
        after NodeStartupDelayInMs -> ok
        end,
        {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{node => Node, cookie => Cookie}),

        % Keep node alive
        receive
            stop ->
                peer:stop(Peer),
                TC ! {self(), stopped}
        end
    end),

    % In parallel, try to attach to the node with a timeout
    ok = edb:attach(#{node => Node, cookie => Cookie, timeout => AttachTimeout}),
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

test_can_attach_with_specific_cookie(Config) ->
    CustomCookie1 = 'customcookie1',
    CustomCookie2 = 'customcookie2',

    % Start two nodes, one with each cookie
    {ok, _Peer1, Node1, CustomCookie1} = edb_test_support:start_peer_node(Config, #{cookie => CustomCookie1}),
    {ok, _Peer2, Node2, CustomCookie2} = edb_test_support:start_peer_node(Config, #{cookie => CustomCookie2}),

    % We can't attach to a node with the wrong cookie
    {error, nodedown} = edb:attach(#{node => Node1, cookie => CustomCookie2}),
    {error, nodedown} = edb:attach(#{node => Node2, cookie => CustomCookie1}),

    % We can attach to each node with the correct cookie
    ok = edb:attach(#{node => Node1, cookie => CustomCookie1}),
    ok = edb:attach(#{node => Node2, cookie => CustomCookie2}),

    ok.

test_attach_validates_args(_Config) ->
    ?assertError({badarg, {missing, node}}, edb:attach(#{})),
    ?assertError({badarg, #{node := ~"not a node"}}, edb:attach(#{node => ~"not a node"})),

    Args = #{node => edb_test_support:random_node("debuggee")},
    ?assertError({badarg, #{timeout := nan}}, edb:attach(Args#{timeout => nan})),
    ?assertError({badarg, #{cookie := ~"blah"}}, edb:attach(Args#{cookie => ~"blah"})),

    ?assertError({badarg, {unknown, [foo]}}, edb:attach(Args#{foo => bar})),
    ?assertError({badarg, {unknown, [foo, hey]}}, edb:attach(Args#{foo => bar, hey => ho})),
    ok.

test_fails_to_attach_if_debuggee_not_in_debugging_mode(Config) ->
    {ok, _Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{enable_debugging_mode => false}),

    ?assertEqual(
        {error, {no_debugger_support, not_enabled}},
        edb:attach(#{node => Node, cookie => Cookie})
    ),

    ok.

%%--------------------------------------------------------------------
%% DETACH TEST CASES
%%--------------------------------------------------------------------

test_querying_on_a_vanished_node_detaches(Config) ->
    {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),
    ok = edb:attach(#{node => Node, cookie => Cookie}),
    ok = edb_test_support:start_event_collector(),

    % Sanity check: no errors while attached
    ?assertMatch(#{}, edb:processes()),

    % Kill the node, we will be detached
    ok = edb_test_support:stop_peer(Peer),
    ?assertError(not_attached, edb:processes()),

    % Verify we get a nodedown event
    ?assertEqual(
        [{nodedown, Node, connection_closed}],
        edb_test_support:collected_events()
    ),
    ok.

test_terminating_detaches(Config) ->
    {ok, _Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),

    % Sanity check: no errors while attached
    edb:attach(#{node => Node, cookie => Cookie}),
    ?assertMatch(Node, edb:attached_node()),

    % We error after stopping the session
    ok = edb:terminate(),
    ?assertError(not_attached, edb:attached_node()),

    % No errrors if we re-attach
    edb:attach(#{node => Node, cookie => Cookie}),
    ?assertMatch(Node, edb:attached_node()),

    ok.

test_terminating_on_a_vanished_node_detaches(Config) ->
    {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),
    edb:attach(#{node => Node, cookie => Cookie}),

    % Sanity check: no errors while attached
    edb:attach(#{node => Node, cookie => Cookie}),
    ?assertEqual(Node, edb:attached_node()),

    % Kill the peer node, we now fail to stop
    ok = edb_test_support:stop_peer(Peer),

    ?assertError(not_attached, edb:terminate()),
    ?assertError(not_attached, edb:attached_node()),
    ok.

test_detaching_unsubscribes(Config) ->
    {ok, _Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),
    edb:attach(#{node => Node, cookie => Cookie}),
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
    {ok, _Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),

    ok = edb:attach(#{node => Node, cookie => Cookie}),
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
    {ok, _Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),

    ok = edb:attach(#{node => Node, cookie => Cookie}),
    ?assertEqual(edb:attached_node(), Node),

    ok = edb_test_support:start_event_collector(),

    % Let the event collector get an event
    {ok, SyncRef1} = edb_test_support:event_collector_send_sync(),

    % Re-attach to the same node, should be a no-op
    ok = edb:attach(#{node => Node, cookie => Cookie}),
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
    Cookie = 'some_cookie',
    {ok, _Peer1, Node1, Cookie} = edb_test_support:start_peer_node(Config, #{
        node => {prefix, "debuggee_1"},
        cookie => Cookie
    }),
    {ok, _Peer2, Node2, Cookie} = edb_test_support:start_peer_node(Config, #{
        node => {prefix, "debuggee_2"},
        cookie => Cookie
    }),

    ok = edb:attach(#{node => Node1, cookie => Cookie}),
    ?assertEqual(edb:attached_node(), Node1),

    ok = edb_test_support:start_event_collector(),

    % Let the event collector get an event
    {ok, SyncRef} = edb_test_support:event_collector_send_sync(),

    % Attach to a different node
    ok = edb:attach(#{node => Node2, cookie => Cookie}),
    ?assertEqual(edb:attached_node(), Node2),

    ?assertEqual(
        [{sync, SyncRef}, unsubscribed],
        edb_test_support:collected_events()
    ),

    ok.
