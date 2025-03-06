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
-include_lib("common_test/include/ct.hrl").

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
    test_can_attach_when_distribution_is_already_started/1,
    test_attaching_to_nonode_at_nohost/1,

    test_attach_validates_args/1,
    test_attach_detects_unreachable_nodes/1,

    test_fails_to_attach_if_debuggee_not_in_debugging_mode/1
]).

%% Reverse-attach test-cases
-export([
    test_raises_error_until_reverse_attached/1,

    test_reverse_attaching_picks_the_right_node/1,
    test_injectable_code_can_be_composed/1,
    test_reverse_attaching_blocks_further_attachs/1,
    test_reverse_attach_fails_after_timeout/1,
    test_reverse_attach_fails_if_debuggee_not_in_debugging_mode/1,
    test_reverse_attach_detects_domain_mismatch/1,

    test_reverse_attach_validates_args/1
]).

%% Detach test-cases
-export([
    test_querying_on_a_vanished_node_detaches/1,

    test_terminating_detaches/1,
    test_terminating_on_a_vanished_node_detaches/1,

    test_detaching_unsubscribes/1,

    test_reattaching_to_non_existent_node_doesnt_detach/1,
    test_reattaching_to_same_node_doesnt_detach/1,
    test_reattaching_to_different_node_detaches_from_old_node/1,
    test_reverse_attaching_to_a_node_detaches_from_old_node/1
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
        {group, test_reverse_attach},
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
            test_can_attach_when_distribution_is_already_started,
            test_attaching_to_nonode_at_nohost,
            test_attach_detects_unreachable_nodes,

            test_attach_validates_args,

            test_fails_to_attach_if_debuggee_not_in_debugging_mode
        ]},

        {test_reverse_attach, [
            test_raises_error_until_reverse_attached,

            test_reverse_attaching_picks_the_right_node,
            test_injectable_code_can_be_composed,
            test_reverse_attaching_blocks_further_attachs,
            test_reverse_attach_fails_after_timeout,
            test_reverse_attach_detects_domain_mismatch,

            test_reverse_attach_validates_args,
            test_reverse_attach_fails_if_debuggee_not_in_debugging_mode
        ]},

        {test_detach, [
            test_querying_on_a_vanished_node_detaches,

            test_terminating_detaches,
            test_terminating_on_a_vanished_node_detaches,

            test_detaching_unsubscribes,

            test_reattaching_to_non_existent_node_doesnt_detach,
            test_reattaching_to_same_node_doesnt_detach,
            test_reattaching_to_different_node_detaches_from_old_node,
            test_reverse_attaching_to_a_node_detaches_from_old_node
        ]}
    ].

init_per_testcase(_TestCase, Config0) ->
    Config1 = start_debugger_node(Config0),
    Config1.
end_per_testcase(_TestCase, _Config) ->
    ok = edb_test_support:stop_event_collector(),
    ok = edb_test_support:stop_all_peers(),
    ok.

test_raises_error_until_attached(Config) ->
    on_debugger_node(Config, fun() ->
        % Initially, we are not attached to any node, so error on operations
        ?assertError(not_attached, edb:attached_node()),
        ?assertError(not_attached, edb:processes()),

        {ok, #{peer := Peer, node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),

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

        ok
    end).

test_attaching_injects_edb_server(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{peer := Peer, node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),

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
        ok
    end).

test_can_attach_async_with_timeout(Config) ->
    NodeStartupDelayInMs = 500,
    AttachTimeout = NodeStartupDelayInMs * 10,
    test_can_attach_async(Config, NodeStartupDelayInMs, AttachTimeout).

test_can_attach_async_with_infinity_timeout(Config) ->
    NodeStartupDelayInMs = 500,
    test_can_attach_async(Config, NodeStartupDelayInMs, infinity).

test_can_attach_async(Config, NodeStartupDelayInMs, AttachTimeout) ->
    on_debugger_node(Config, fun() ->
        Node = edb_test_support:random_node("debuggee"),

        Cookie = 'some_cookie',

        % Wait some time, then start the node
        TC = self(),
        Sentinel = spawn_link(fun() ->
            receive
            after NodeStartupDelayInMs -> ok
            end,
            {ok, #{peer := Peer}} = edb_test_support:start_peer_node(Config, #{node => Node, cookie => Cookie}),

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

        ok
    end).

test_fails_to_attach_after_timeout(Config) ->
    on_debugger_node(Config, fun() ->
        Node = edb_test_support:random_node("non-existent-debuggee"),
        {error, nodedown} = edb:attach(#{node => Node, timeout => 100}),
        ok
    end).

test_can_attach_with_specific_cookie(Config) ->
    on_debugger_node(Config, fun() ->
        CustomCookie1 = 'customcookie1',
        CustomCookie2 = 'customcookie2',

        % Start two nodes, one with each cookie
        {ok, #{node := Node1}} = edb_test_support:start_peer_node(Config, #{cookie => CustomCookie1}),
        {ok, #{node := Node2}} = edb_test_support:start_peer_node(Config, #{cookie => CustomCookie2}),

        % We can't attach to a node with the wrong cookie
        {error, nodedown} = edb:attach(#{node => Node1, cookie => CustomCookie2}),
        {error, nodedown} = edb:attach(#{node => Node2, cookie => CustomCookie1}),

        % We can attach to each node with the correct cookie
        ok = edb:attach(#{node => Node1, cookie => CustomCookie1}),
        ok = edb:attach(#{node => Node2, cookie => CustomCookie2}),

        ok
    end).

test_can_attach_when_distribution_is_already_started(Config) ->
    on_debugger_node(Config, fun() ->
        % Sanity-check distribution is not started
        ?assertEqual(#{started => no}, net_kernel:get_state()),

        % Start distribution
        ok = start_distribution(),
        Cookie = erlang:get_cookie(),
        % Sanity-check: distribution is started
        ?assertMatch(#{started := dynamic}, net_kernel:get_state()),

        % Start a debuggee with same cookie as debugger
        {ok, #{node := DebuggeeNode, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),

        % We can attach to the DebuggeeNode, we don't need to specify a cookie
        ok = edb:attach(#{node => DebuggeeNode})
    end).

test_attaching_to_nonode_at_nohost(Config) ->
    on_debugger_node(Config, fun() ->
        % Sanity-check: no distribution, so node is nonode@nohost
        ?assertEqual(#{started => no}, net_kernel:get_state()),
        ?assertEqual(nonode@nohost, node()),

        % It is ok to attach to the current node without distribution
        ok = edb:attach(#{node => nonode@nohost}),

        % Distribution is not started when attaching to the local node
        ?assertEqual(#{started => no}, net_kernel:get_state()),
        ?assertEqual(nonode@nohost, node()),

        ok = edb:detach(),

        % Now let's start distribution
        ok = start_distribution(),
        ?assertMatch(#{started := dynamic}, net_kernel:get_state()),
        ?assertNotEqual(nonode@nohost, node()),

        % It is no longer ok to connect to nonode@nohost
        ?assertError(
            {invalid_node, nonode@nohost},
            edb:attach(#{node => nonode@nohost})
        ),

        ok
    end).

test_attach_detects_unreachable_nodes(Config) ->
    on_debugger_node(Config, fun() ->
        % When using shortnames, trying to attach using longnames should fail
        ok = start_distribution(shortnames),
        ?assertError(
            {invalid_node, 'foo@hey.ho.com'},
            edb:attach(#{node => 'foo@hey.ho.com'})
        ),

        % Sanity-check: attaching to a non-existent node with shortnames gives a nodedown
        {error, nodedown} = edb:attach(#{node => 'foo@heyho'}),

        ok = stop_distribution(),

        % Conversely, when using longnames, trying to attach using shortnames should fail
        ok = start_distribution(longnames),
        ?assertError(
            {invalid_node, 'foo@heyho'},
            edb:attach(#{node => 'foo@heyho'})
        ),

        % Sanity-check: attaching to a non-existent node with longnames gives a nodedown
        {error, nodedown} = edb:attach(#{node => 'foo@hey.ho.com'}),

        ok
    end).

test_attach_validates_args(Config) ->
    on_debugger_node(Config, fun() ->
        ?assertError({badarg, {missing, node}}, edb:attach(#{})),
        ?assertError({badarg, #{node := ~"not a node"}}, edb:attach(#{node => ~"not a node"})),

        Args = #{node => edb_test_support:random_node("debuggee")},
        ?assertError({badarg, #{timeout := nan}}, edb:attach(Args#{timeout => nan})),
        ?assertError({badarg, #{cookie := ~"blah"}}, edb:attach(Args#{cookie => ~"blah"})),

        ?assertError({badarg, {unknown, [foo]}}, edb:attach(Args#{foo => bar})),
        ?assertError({badarg, {unknown, [foo, hey]}}, edb:attach(Args#{foo => bar, hey => ho})),
        ok
    end).

test_fails_to_attach_if_debuggee_not_in_debugging_mode(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{
            enable_debugging_mode => false
        }),

        ?assertEqual(
            {error, {bootstrap_failed, {no_debugger_support, not_enabled}}},
            edb:attach(#{node => Node, cookie => Cookie})
        ),

        ok
    end).

%%--------------------------------------------------------------------
%% REVERSE ATTACH TEST CASES
%%--------------------------------------------------------------------
test_raises_error_until_reverse_attached(Config) ->
    on_debugger_node(Config, fun() ->
        % Initially, we are not attached to any node, so error on operations
        ?assertError(not_attached, edb:attached_node()),
        ?assertError(not_attached, edb:processes()),

        % We are now waiting for a new node to attach
        {ok, #{notification_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % Launch new node, injecting special code to inject
        {ok, #{node := Node}} = edb_test_support:start_peer_node(Config, #{extra_args => ["-eval", InjectedCode]}),

        % We eventually attach, and no longer error
        ok = wait_reverse_attach_notification(Ref),
        ?assertEqual(Node, edb:attached_node()),
        ?assertMatch(#{}, edb:processes()),

        % After detaching, we error again
        ok = edb:detach(),
        ?assertError(not_attached, edb:attached_node()),
        ?assertError(not_attached, edb:processes()),

        ok
    end).

test_reverse_attaching_picks_the_right_node(Config) ->
    on_debugger_node(Config, fun() ->
        % We are waiting for a node to attach
        {ok, #{notification_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % Launch two nodes, only of the them contains the injected code
        {ok, #{node := NodeWithInjectedCode}} = edb_test_support:start_peer_node(Config, #{
            extra_args => ["-eval", InjectedCode]
        }),
        {ok, #{node := TheOtherNode}} = edb_test_support:start_peer_node(Config, #{}),
        % Sanity-check: different nodes
        ?assertNotEqual(NodeWithInjectedCode, TheOtherNode),

        % We eventually attach to the node with injected code
        ok = wait_reverse_attach_notification(Ref),
        ?assertEqual(NodeWithInjectedCode, edb:attached_node()),
        ok
    end).

test_injectable_code_can_be_composed(Config) ->
    on_debugger_node(Config, fun() ->
        % We are waiting for a node to attach
        {ok, #{notification_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % We create more complex code
        ComplexInjectedCode = list_to_binary(
            io_lib:format("~s, register(foo, self()), timer:sleep(infinity)", [InjectedCode])
        ),

        % Launch a node with the complex code
        {ok, #{peer := Peer, node := Node}} = edb_test_support:start_peer_node(Config, #{
            extra_args => ["-eval", ComplexInjectedCode]
        }),

        % We eventually attach
        ok = wait_reverse_attach_notification(Ref),
        ?assertEqual(Node, edb:attached_node()),

        % The rest of the code was also executed
        {ok, resumed} = edb:continue(),
        ?assertMatch(
            Pid when is_pid(Pid),
            peer:call(Peer, erlang, whereis, [foo])
        ),

        ok
    end).

test_reverse_attaching_blocks_further_attachs(Config) ->
    on_debugger_node(Config, fun() ->
        % Start a reverse-attach that will never succeed
        {ok, _} = edb:reverse_attach(#{name_domain => shortnames}),

        % Attaching fails
        {error, attachment_in_progress} = edb:attach(#{node => node()}),

        % Reverse attaching fails
        {error, attachment_in_progress} = edb:reverse_attach(#{name_domain => shortnames}),

        ok
    end).

test_reverse_attach_fails_after_timeout(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{notification_ref := Ref, erl_code_to_inject := _}} = edb:reverse_attach(#{
            name_domain => shortnames,
            timeout => 500
        }),

        % No node is started, so waiting fails after 0.5s
        timeout = wait_reverse_attach_notification(Ref),

        ok
    end).

test_reverse_attach_fails_if_debuggee_not_in_debugging_mode(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{notification_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % start a node with debugging mode off
        {ok, #{}} = edb_test_support:start_peer_node(Config, #{
            extra_args => ["-eval", InjectedCode],
            enable_debugging_mode => false
        }),

        ?assertEqual(
            {error, {bootstrap_failed, {no_debugger_support, not_enabled}}},
            wait_reverse_attach_notification(Ref)
        ),

        ok
    end).

test_reverse_attach_detects_domain_mismatch(Config) ->
    on_debugger_node(Config, fun() ->
        % When using shortnames, trying to reverse-attach using longnames should fail
        ok = start_distribution(shortnames),
        ?assertError(
            {invalid_name_domain, longnames},
            edb:reverse_attach(#{name_domain => longnames})
        ),

        ok = stop_distribution(),

        % Conversely, when using longnames, trying to reverse-attach using shortnames should fail
        ok = start_distribution(longnames),
        ?assertError(
            {invalid_name_domain, shortnames},
            edb:reverse_attach(#{name_domain => shortnames})
        ),

        ok
    end).

test_reverse_attach_validates_args(Config) ->
    on_debugger_node(Config, fun() ->
        ?assertError({badarg, {missing, name_domain}}, edb:reverse_attach(#{})),
        ?assertError({badarg, #{name_domain := mediumnames}}, edb:reverse_attach(#{name_domain => mediumnames})),

        Args = #{name_domain => shortnames},
        ?assertError({badarg, #{timeout := nan}}, edb:reverse_attach(Args#{timeout => nan})),

        ?assertError({badarg, {unknown, [foo]}}, edb:reverse_attach(Args#{foo => bar})),
        ?assertError({badarg, {unknown, [foo, hey]}}, edb:reverse_attach(Args#{foo => bar, hey => ho})),

        ok
    end).

%%--------------------------------------------------------------------
%% DETACH TEST CASES
%%--------------------------------------------------------------------

test_querying_on_a_vanished_node_detaches(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{peer := Peer, node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),
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
        ok
    end).

test_terminating_detaches(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),

        % Sanity check: no errors while attached
        edb:attach(#{node => Node, cookie => Cookie}),
        ?assertMatch(Node, edb:attached_node()),

        % We error after stopping the session
        ok = edb:terminate(),
        ?assertError(not_attached, edb:attached_node()),

        % No errrors if we re-attach
        edb:attach(#{node => Node, cookie => Cookie}),
        ?assertMatch(Node, edb:attached_node()),

        ok
    end).

test_terminating_on_a_vanished_node_detaches(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{peer := Peer, node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),
        edb:attach(#{node => Node, cookie => Cookie}),

        % Sanity check: no errors while attached
        edb:attach(#{node => Node, cookie => Cookie}),
        ?assertEqual(Node, edb:attached_node()),

        % Kill the peer node, we now fail to stop
        ok = edb_test_support:stop_peer(Peer),

        ?assertError(not_attached, edb:terminate()),
        ?assertError(not_attached, edb:attached_node()),
        ok
    end).

test_detaching_unsubscribes(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),
        edb:attach(#{node => Node, cookie => Cookie}),
        ok = edb_test_support:start_event_collector(),

        ok = edb:detach(),

        ?assertEqual(
            [
                unsubscribed
            ],
            edb_test_support:collected_events()
        ),
        ok
    end).

test_reattaching_to_non_existent_node_doesnt_detach(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),

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
        ok
    end).

test_reattaching_to_same_node_doesnt_detach(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),

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

        ok
    end).

test_reattaching_to_different_node_detaches_from_old_node(Config) ->
    on_debugger_node(Config, fun() ->
        Cookie = 'some_cookie',
        {ok, #{node := Node1}} = edb_test_support:start_peer_node(Config, #{
            node => {prefix, "debuggee_1"},
            cookie => Cookie
        }),
        {ok, #{node := Node2}} = edb_test_support:start_peer_node(Config, #{
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

        ok
    end).

test_reverse_attaching_to_a_node_detaches_from_old_node(Config) ->
    on_debugger_node(Config, fun() ->
        {ok, #{node := Node1, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{
            node => {prefix, "debuggee_1"}
        }),

        ok = edb:attach(#{node => Node1, cookie => Cookie}),
        ?assertEqual(edb:attached_node(), Node1),

        ok = edb_test_support:start_event_collector(),

        % Let the event collector get an event
        {ok, SyncRef} = edb_test_support:event_collector_send_sync(),

        % Reverse-attach to a different node
        {ok, #{notification_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),
        {ok, #{node := Node2}} = edb_test_support:start_peer_node(Config, #{
            extra_args => ["-eval", InjectedCode]
        }),
        ok = wait_reverse_attach_notification(Ref),
        ?assertEqual(edb:attached_node(), Node2),

        ?assertEqual(
            [{sync, SyncRef}, unsubscribed],
            edb_test_support:collected_events()
        ),
        ok
    end).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------
-spec start_debugger_node(Config) -> Config when
    Config :: ct_suite:config().
start_debugger_node(Config0) ->
    {ok, #{peer := Peer}} = edb_test_support:start_peer_no_dist(Config0, #{
        copy_code_path => true
    }),
    Config1 = [{debugger_peer_key(), Peer} | Config0],
    {ok, _} = on_debugger_node(Config1, fun() ->
        application:ensure_all_started(edb_core)
    end),
    Config1.

-spec on_debugger_node(Config, fun(() -> Result)) -> Result when
    Config :: ct_suite:config().
on_debugger_node(Config, Fun) ->
    Peer = ?config(debugger_peer_key(), Config),
    peer:call(Peer, erlang, apply, [Fun, []]).

-spec debugger_peer_key() -> debugger_peer.
debugger_peer_key() -> debugger_peer.

-spec start_distribution() -> ok.
start_distribution() ->
    start_distribution(shortnames).

-spec start_distribution(NameDomain) -> ok when
    NameDomain :: longnames | shortnames.
start_distribution(NameDomain) ->
    Node = edb_test_support:random_node("debugger", NameDomain),
    {ok, _} = net_kernel:start(Node, #{name_domain => NameDomain}),
    erlang:set_cookie('234in20fmksdlkfsdfs'),
    ok.

-spec stop_distribution() -> ok.
stop_distribution() ->
    ok = net_kernel:stop().

-spec wait_reverse_attach_notification(NotificationRef :: reference()) ->
    ok | timeout | {error, {bootstrap_failed, edb:bootstrap_error()}}.
wait_reverse_attach_notification(NotificationRef) ->
    receive
        {NotificationRef, ok} -> ok;
        {NotificationRef, timeout} -> timeout;
        {NotificationRef, {error, {bootstrap_failed, Reason}}} -> {error, {bootstrap_failed, Reason}};
        {NotificationRef, Unexpected} -> error({unexpected_notification, Unexpected})
    after 2_000 -> error(timeout_waiting_for_notification)
    end.
