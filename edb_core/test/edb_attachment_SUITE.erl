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
-typing([eqwalizer]).

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

    test_fails_to_attach_if_debuggee_not_in_debugging_mode/1,

    test_attach_changes_node_in_focus/1
]).

%% Reverse-attach test-cases
-export([
    test_raises_error_until_reverse_attached/1,
    test_reverse_attaching_picks_the_right_node/1,
    test_can_reverse_attach_to_node_with_dynamic_name/1,
    test_can_reverse_attach_to_node_with_no_dist/1,
    test_injectable_code_can_be_composed/1,
    test_reverse_attach_blocks_further_evals/1,
    test_reverse_attaching_blocks_further_attachs/1,
    test_reverse_attach_fails_after_timeout/1,
    test_reverse_attach_fails_if_debuggee_not_in_debugging_mode/1,
    test_reverse_attach_detects_domain_mismatch/1,

    test_reverse_attach_validates_args/1,
    test_reverse_attach_additional_node_sends_event/1,
    test_reverse_attach_without_instrument_erl_aflags_on_attach/1,
    test_reverse_attach_fails_when_instrument_erl_aflags_on_attach_false/1,
    test_reverse_attach_second_node_goes_down/1,
    test_reverse_attach_original_node_goes_down_second_remains/1
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
    test_reverse_attaching_to_a_node_detaches_from_old_node/1,

    test_subscribing_before_attaching_works/1
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

            test_fails_to_attach_if_debuggee_not_in_debugging_mode,

            test_subscribing_before_attaching_works,

            test_attach_changes_node_in_focus
        ]},

        {test_reverse_attach, [
            test_raises_error_until_reverse_attached,

            test_reverse_attaching_picks_the_right_node,
            test_can_reverse_attach_to_node_with_dynamic_name,
            test_can_reverse_attach_to_node_with_no_dist,

            test_injectable_code_can_be_composed,
            test_reverse_attach_blocks_further_evals,
            test_reverse_attaching_blocks_further_attachs,
            test_reverse_attach_fails_after_timeout,
            test_reverse_attach_detects_domain_mismatch,

            test_reverse_attach_validates_args,
            test_reverse_attach_fails_if_debuggee_not_in_debugging_mode,
            test_reverse_attach_additional_node_sends_event,
            test_reverse_attach_without_instrument_erl_aflags_on_attach,
            test_reverse_attach_fails_when_instrument_erl_aflags_on_attach_false,
            test_reverse_attach_second_node_goes_down,
            test_reverse_attach_original_node_goes_down_second_remains
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
    Config1 = edb_test_support:start_debugger_node(Config0),
    Config1.
end_per_testcase(_TestCase, _Config) ->
    ok = edb_test_support:stop_event_collector(),
    ok = edb_test_support:stop_all_peers(),
    ok.

test_raises_error_until_attached(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        % Initially, we are not attached to any node, so error on operations
        ?assertError(not_attached, edb:attached_node()),
        ?assertError(not_attached, edb:processes([])),
        ?assertEqual(#{}, edb:nodes()),

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
        ?assertMatch(#{}, edb:processes([])),
        ?assertEqual(#{Node => []}, edb:nodes()),

        % After detaching, we error again
        ok = edb:detach(),
        ?assertError(not_attached, edb:attached_node()),
        ?assertError(not_attached, edb:processes([])),
        ?assertEqual(#{}, edb:nodes()),

        ok
    end).

test_attaching_injects_edb_server(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
        Node = edb_test_support:random_node("non-existent-debuggee"),
        {error, nodedown} = edb:attach(#{node => Node, timeout => 100}),
        ok
    end).

test_can_attach_with_specific_cookie(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, {missing, node}}, edb:attach(#{})),
        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, #{node := ~"not a node"}}, edb:attach(#{node => ~"not a node"})),

        Args = #{node => edb_test_support:random_node("debuggee")},
        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, #{timeout := nan}}, edb:attach(Args#{timeout => nan})),
        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, #{cookie := ~"blah"}}, edb:attach(Args#{cookie => ~"blah"})),

        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, {unknown, [foo]}}, edb:attach(Args#{foo => bar})),
        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, {unknown, [foo, hey]}}, edb:attach(Args#{foo => bar, hey => ho})),
        ok
    end).

test_fails_to_attach_if_debuggee_not_in_debugging_mode(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        {ok, #{node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{
            enable_debugging_mode => false
        }),

        ?assertEqual(
            {error, {bootstrap_failed, {no_debugger_support, not_enabled}}},
            edb:attach(#{node => Node, cookie => Cookie})
        ),

        ok
    end).

test_subscribing_before_attaching_works(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        % Subscribe to events before attaching
        {ok, Subscription} = edb:subscribe(),

        {ok, #{node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),

        % Attach to the node - this should sync the local subscription with the server
        ok = edb:attach(#{node => Node, cookie => Cookie}),

        ?assertEqual(Node, edb:attached_node()),

        % Send a sync event to test that the subscription works after attachment
        {ok, SyncRef} = edb:send_sync_event(Subscription),

        % Verify we receive the event from the server
        receive
            {edb_event, Subscription, {sync, SyncRef}} ->
                ok
        after 1000 ->
            error(sync_event_not_received)
        end,

        ok
    end).

test_attach_changes_node_in_focus(Config) ->
    TestSource = create_test_source_that_spawns_node(),
    edb_test_support:on_debugger_node(Config, fun() ->
        % Perform reverse attach to the first node
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames, multi_node_enabled => true, instrument_erl_aflags_on_attach => true
        }),

        % Subscribe to debugger events to receive reverse attach results
        {ok, Subscription} = edb:subscribe(),

        % Start the first peer node and execute the injected code to trigger reverse attach
        {ok, #{peer := Peer1, node := Node1, cookie := _Cookie, modules := #{test_mod := _}}} = edb_test_support:start_peer_node(
            Config, #{
                extra_args => ["-eval", InjectedCode],
                modules => [{source, TestSource}],
                copy_code_path => true
            }
        ),

        % Wait for the reverse attach event from the first node
        {ok, Node1} = wait_reverse_attach_event(Subscription, Ref),

        ok = edb:add_breakpoint(test_mod, 10),

        Receiver = self(),
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer1, test_mod, test_fun, [Receiver, Config])
        end),

        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),

        SecondNode =
            receive
                {node_created, Node} -> Node
            after 5000 ->
                error(timeout_waiting_for_node)
            end,

        % Wait for the node_attached event for the second node
        {ok, SecondNode} = wait_reverse_attach_event(Subscription, Ref),

        ok = edb:attach(#{node => SecondNode}),

        % Verify that the node in focus is the second node
        ?assertEqual(SecondNode, edb:attached_node()),

        ok = edb:attach(#{node => Node1}),

        % Verify that the node in focus is back to the first node
        ?assertEqual(Node1, edb:attached_node()),

        {ok, #{peer := _Peer3, node := Node3, cookie := Cookie3}} = edb_test_support:start_peer_node(Config, #{}),

        ?assertError(
            cannot_attach_to_new_node_when_multi_node_enabled, edb:attach(#{node => Node3, cookie => Cookie3})
        ),

        {ok, resumed} = edb:continue(),

        ok
    end).

%%--------------------------------------------------------------------
%% REVERSE ATTACH TEST CASES
%%--------------------------------------------------------------------
test_raises_error_until_reverse_attached(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        % Initially, we are not attached to any node, so error on operations
        ?assertError(not_attached, edb:attached_node()),
        ?assertError(not_attached, edb:processes([])),

        % We are now waiting for a new node to attach
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % Subscribe to events to receive reverse attach result
        {ok, Subscription} = edb:subscribe(),

        % Launch new node, injecting special code to reverse-attach
        {ok, #{node := Node}} = edb_test_support:start_peer_node(Config, #{extra_args => ["-eval", InjectedCode]}),

        % We eventually attach, and no longer error
        {ok, Node} = wait_reverse_attach_event(Subscription, Ref),
        ?assertEqual(Node, edb:attached_node()),
        ?assertMatch(#{}, edb:processes([])),

        % After detaching, we error again
        ok = edb:detach(),
        ?assertError(not_attached, edb:attached_node()),
        ?assertError(not_attached, edb:processes([])),

        ok
    end).

test_reverse_attaching_picks_the_right_node(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        % We are waiting for a node to attach
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % Subscribe to events to receive reverse attach result
        {ok, Subscription} = edb:subscribe(),

        % Launch two nodes, only of the them contains the injected code
        {ok, #{node := NodeWithInjectedCode}} = edb_test_support:start_peer_node(Config, #{
            extra_args => ["-eval", InjectedCode]
        }),
        {ok, #{node := TheOtherNode}} = edb_test_support:start_peer_node(Config, #{}),
        % Sanity-check: different nodes
        ?assertNotEqual(NodeWithInjectedCode, TheOtherNode),

        % We eventually attach to the node with injected code
        {ok, NodeWithInjectedCode} = wait_reverse_attach_event(Subscription, Ref),
        ?assertEqual(NodeWithInjectedCode, edb:attached_node()),
        ok
    end).

test_can_reverse_attach_to_node_with_dynamic_name(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        % We are waiting for a node to attach
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % Subscribe to events to receive reverse attach result
        {ok, Subscription} = edb:subscribe(),

        % Launch new node using -sname undefined, injecting special code to reverse-attach
        {ok, #{peer := Peer, node := undefined}} = edb_test_support:start_peer_node(Config, #{
            extra_args => ["-eval", InjectedCode],
            node => undefined
        }),

        % We eventually attach, and no longer error
        {ok, _} = wait_reverse_attach_event(Subscription, Ref),

        ?assertMatch(#{}, edb:processes([])),

        {ok, resumed} = edb:continue(),

        ActualNode = peer:call(Peer, erlang, node, []),
        ?assertEqual(ActualNode, edb:attached_node()),
        ok
    end).

test_can_reverse_attach_to_node_with_no_dist(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        % We are waiting for a node to attach
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % Subscribe to events to receive reverse attach result
        {ok, Subscription} = edb:subscribe(),

        % Launch new peer with no distribution, special code to inject
        {ok, #{peer := Peer}} = edb_test_support:start_peer_no_dist(Config, #{
            extra_args => ["-eval", InjectedCode]
        }),

        % We eventually attach, and no longer error
        {ok, _} = wait_reverse_attach_event(Subscription, Ref),

        ?assertMatch(#{}, edb:processes([])),

        {ok, resumed} = edb:continue(),

        ActualNode = peer:call(Peer, erlang, node, []),
        ?assertEqual(ActualNode, edb:attached_node()),
        ok
    end).

test_injectable_code_can_be_composed(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        % We are waiting for a node to attach
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % Subscribe to events to receive reverse attach result
        {ok, Subscription} = edb:subscribe(),

        % We create more complex code
        ComplexInjectedCode = list_to_binary(
            io_lib:format("~s, register(foo, self()), timer:sleep(infinity)", [InjectedCode])
        ),

        % Launch a node with the complex code
        {ok, #{peer := Peer, node := Node}} = edb_test_support:start_peer_node(Config, #{
            extra_args => ["-eval", ComplexInjectedCode]
        }),

        % We eventually attach
        {ok, Node} = wait_reverse_attach_event(Subscription, Ref),
        ?assertEqual(Node, edb:attached_node()),

        % The rest of the code was also executed
        {ok, resumed} = edb:continue(),
        ?assertMatch(
            Pid when is_pid(Pid),
            peer:call(Peer, erlang, whereis, [foo])
        ),

        ok
    end).

test_reverse_attach_blocks_further_evals(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        % We are waiting for a node to attach
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % Subscribe to events to receive reverse attach result
        {ok, Subscription} = edb:subscribe(),

        % Register running process with a name, so it can receive messages from debuggee
        Name = ?MODULE,
        erlang:register(Name, self()),

        % Send-me-a-message code
        SendMsgCode =
            case
                unicode:characters_to_binary(io_lib:format("erlang:send({'~ts', '~ts'}, cheers)", [?MODULE, node()]))
            of
                Bin when is_binary(Bin) -> Bin
            end,

        % Launch a node that should send us a message only after resumed
        {ok, #{node := Node}} = edb_test_support:start_peer_node(Config, #{
            extra_args => ["-eval", InjectedCode, "-eval", SendMsgCode]
        }),

        % Wait for the node to be attached
        {ok, Node} = wait_reverse_attach_event(Subscription, Ref),

        % Sanity-check: the node was paused on attachment
        ?assert(edb:is_paused()),

        receive
            cheers -> error(~"-eval block was evaluated before resuming")
        after 0 ->
            ok
        end,

        {ok, resumed} = edb:continue(),

        receive
            cheers -> ok
        after 2_000 ->
            error(~"timeout waiting for message from debuggee")
        end,
        ok
    end).

test_reverse_attaching_blocks_further_attachs(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        % Start a reverse-attach that will never succeed
        {ok, _} = edb:reverse_attach(#{name_domain => shortnames}),

        % Attaching fails
        {error, attachment_in_progress} = edb:attach(#{node => node()}),

        % Reverse attaching fails
        {error, attachment_in_progress} = edb:reverse_attach(#{name_domain => shortnames}),

        ok
    end).

test_reverse_attach_fails_after_timeout(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := _}} = edb:reverse_attach(#{
            name_domain => shortnames,
            timeout => 500
        }),

        % Subscribe to events to receive reverse attach result
        {ok, Subscription} = edb:subscribe(),

        % No node is started, so waiting fails after 0.5s
        timeout = wait_reverse_attach_event(Subscription, Ref),

        ok
    end).

test_reverse_attach_fails_if_debuggee_not_in_debugging_mode(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % Subscribe to events to receive reverse attach result
        {ok, Subscription} = edb:subscribe(),

        % start a node with debugging mode off
        {ok, #{node := Node}} = edb_test_support:start_peer_node(Config, #{
            extra_args => ["-eval", InjectedCode],
            enable_debugging_mode => false
        }),

        ?assertEqual(
            {error, Node, {bootstrap_failed, {no_debugger_support, not_enabled}}},
            wait_reverse_attach_event(Subscription, Ref)
        ),

        ok
    end).

test_reverse_attach_detects_domain_mismatch(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, {missing, name_domain}}, edb:reverse_attach(#{})),
        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, #{name_domain := mediumnames}}, edb:reverse_attach(#{name_domain => mediumnames})),

        Args = #{name_domain => shortnames},
        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, #{timeout := nan}}, edb:reverse_attach(Args#{timeout => nan})),

        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, {unknown, [foo]}}, edb:reverse_attach(Args#{foo => bar})),
        % eqwalizer:ignore - testing bad input handling
        ?assertError({badarg, {unknown, [foo, hey]}}, edb:reverse_attach(Args#{foo => bar, hey => ho})),

        ok
    end).

test_reverse_attach_additional_node_sends_event(Config) ->
    TestSource = create_test_source_that_spawns_node(),
    edb_test_support:on_debugger_node(Config, fun() ->
        % Perform reverse attach to the first node
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames, multi_node_enabled => true, instrument_erl_aflags_on_attach => true
        }),

        % Subscribe to debugger events to receive reverse attach results
        {ok, Subscription} = edb:subscribe(),

        % Start the first peer node and execute the injected code to trigger reverse attach
        {ok, #{peer := Peer1, node := Node1, cookie := _Cookie, modules := #{test_mod := _}}} = edb_test_support:start_peer_node(
            Config, #{
                extra_args => ["-eval", InjectedCode],
                modules => [{source, TestSource}],
                copy_code_path => true
            }
        ),

        % Wait for the reverse attach event from the first node
        {ok, Node1} = wait_reverse_attach_event(Subscription, Ref),

        ok = edb:add_breakpoint(test_mod, 10),

        Receiver = self(),
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer1, test_mod, test_fun, [Receiver, Config])
        end),

        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),

        SecondNode =
            receive
                {node_created, Node} -> Node
            after 5000 ->
                error(timeout_waiting_for_node)
            end,

        % Wait for the node_attached event for the second node
        {ok, SecondNode} = wait_reverse_attach_event(Subscription, Ref),

        {ok, resumed} = edb:continue(),

        ok
    end).

test_reverse_attach_without_instrument_erl_aflags_on_attach(Config) ->
    TestSource = create_test_source_that_spawns_node(),
    edb_test_support:on_debugger_node(Config, fun() ->
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames,
            multi_node_enabled => true,
            instrument_erl_aflags_on_attach => false
        }),

        % Subscribe to debugger events to receive reverse attach results
        {ok, Subscription} = edb:subscribe(),

        % Start the first peer node and execute the injected code to trigger reverse attach
        {ok, #{peer := Peer1, node := Node1, cookie := _Cookie, modules := #{test_mod := _}}} = edb_test_support:start_peer_node(
            Config, #{
                extra_args => ["-eval", InjectedCode],
                modules => [{source, TestSource}],
                copy_code_path => true
            }
        ),

        % Wait for the reverse attach event from the first node
        {ok, Node1} = wait_reverse_attach_event(Subscription, Ref),

        % Manually inject the code to the first node
        EscapedInjectedCode = re:replace(InjectedCode, ~"[\s'\"]", ~"\\\\&", [global]),
        true = erpc:call(Node1, os, putenv, [
            "ERL_AFLAGS", io_lib:format("-eval ~s", [EscapedInjectedCode])
        ]),

        ok = edb:add_breakpoint(test_mod, 10),

        Receiver = self(),
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer1, test_mod, test_fun, [Receiver, Config])
        end),

        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),

        SecondNode =
            receive
                {node_created, Node} -> Node
            after 5000 ->
                error(timeout_waiting_for_node)
            end,

        % Wait for the node_attached event for the second node
        {ok, SecondNode} = wait_reverse_attach_event(Subscription, Ref),

        {ok, resumed} = edb:continue(),

        ok
    end).

test_reverse_attach_fails_when_instrument_erl_aflags_on_attach_false(Config) ->
    TestSource = create_test_source_that_spawns_node(),
    edb_test_support:on_debugger_node(Config, fun() ->
        % Perform reverse attach with instrument_erl_aflags_on_attach disabled
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames,
            multi_node_enabled => true,
            instrument_erl_aflags_on_attach => false
        }),

        % Subscribe to debugger events to receive reverse attach results
        {ok, Subscription} = edb:subscribe(),

        % Start the first peer node and execute the injected code to trigger reverse attach
        {ok, #{peer := Peer1, node := Node1, cookie := _Cookie, modules := #{test_mod := _}}} = edb_test_support:start_peer_node(
            Config, #{
                extra_args => ["-eval", InjectedCode],
                modules => [{source, TestSource}],
                copy_code_path => true
            }
        ),

        % Wait for the reverse attach event from the first node
        {ok, Node1} = wait_reverse_attach_event(Subscription, Ref),

        ok = edb:add_breakpoint(test_mod, 10),

        Receiver = self(),
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer1, test_mod, test_fun, [Receiver, Config])
        end),

        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),

        _SecondNode =
            receive
                {node_created, Node} -> Node
            after 5000 ->
                error(timeout_waiting_for_node)
            end,

        % Since instrument_erl_aflags_on_attach is false and the caller doesn't ensure
        % the new node runs the injected code, the second node should fail to attach
        % We expect a timeout when waiting for the second node attachment event
        timeout = wait_reverse_attach_event(Subscription, Ref),

        {ok, resumed} = edb:continue(),

        ok
    end).

test_reverse_attach_second_node_goes_down(Config) ->
    % This test verifies what happens when a second node goes down in multi-node setup
    TestSource = create_test_source_that_spawns_node(),
    edb_test_support:on_debugger_node(Config, fun() ->
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames,
            multi_node_enabled => true,
            instrument_erl_aflags_on_attach => true
        }),

        {ok, Subscription} = edb:subscribe(),

        % Start first peer and wait for it to attach
        {ok, #{peer := Peer1, node := Node1, modules := #{test_mod := _}}} = edb_test_support:start_peer_node(
            Config, #{
                extra_args => ["-eval", InjectedCode],
                modules => [{source, TestSource}],
                copy_code_path => true
            }
        ),
        {ok, Node1} = wait_reverse_attach_event(Subscription, Ref),
        ?assertEqual(#{Node1 => []}, edb:nodes()),

        ok = edb:add_breakpoint(test_mod, 10),
        ok = edb:add_breakpoint(test_mod, 11),

        % Spawn test to create second node
        Receiver = self(),
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer1, test_mod, test_fun, [Receiver, Config])
        end),

        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),

        SecondNode =
            receive
                {node_created, Node} -> Node
            after 5000 ->
                error(timeout_waiting_for_node)
            end,

        % Wait for second node to attach
        {ok, SecondNode} = wait_reverse_attach_event(Subscription, Ref),
        ?assertEqual(#{Node1 => [], SecondNode => []}, edb:nodes()),

        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),
        ?assertEqual(#{Node1 => [], SecondNode => []}, edb:nodes()),

        {ok, resumed} = edb:continue(),

        ok
    end).

test_reverse_attach_original_node_goes_down_second_remains(Config) ->
    % This test verifies what happens when the original node goes down but second remains
    TestSource = create_test_source_that_spawns_node(),
    edb_test_support:on_debugger_node(Config, fun() ->
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames,
            multi_node_enabled => true,
            instrument_erl_aflags_on_attach => true
        }),

        {ok, Subscription} = edb:subscribe(),

        % Start first peer and wait for it to attach
        {ok, #{peer := Peer1, node := Node1, modules := #{test_mod := _}}} = edb_test_support:start_peer_node(
            Config, #{
                extra_args => ["-eval", InjectedCode],
                modules => [{source, TestSource}],
                copy_code_path => true
            }
        ),
        {ok, Node1} = wait_reverse_attach_event(Subscription, Ref),
        ?assertEqual(#{Node1 => []}, edb:nodes()),

        ok = edb:add_breakpoint(test_mod, 10),

        Receiver = self(),
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer1, test_mod, test_fun, [Receiver, Config])
        end),

        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),

        SecondNode =
            receive
                {node_created, Node} -> Node
            after 5000 ->
                error(timeout_waiting_for_node)
            end,

        % Wait for second node to attach
        {ok, SecondNode} = wait_reverse_attach_event(Subscription, Ref),
        ?assertEqual(#{Node1 => [], SecondNode => []}, edb:nodes()),

        ok = edb_test_support:stop_peer(Peer1),
        ?assertEqual(#{SecondNode => []}, edb:nodes()),

        ok
    end).

%%--------------------------------------------------------------------
%% DETACH TEST CASES
%%--------------------------------------------------------------------

test_querying_on_a_vanished_node_detaches(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
        {ok, #{peer := Peer, node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),
        ok = edb:attach(#{node => Node, cookie => Cookie}),
        ok = edb_test_support:start_event_collector(),

        % Sanity check: no errors while attached
        ?assertMatch(#{}, edb:processes([])),

        % Kill the node, we will be detached
        ok = edb_test_support:stop_peer(Peer),
        ?assertError(not_attached, edb:processes([])),

        % Verify we get a nodedown event
        ?assertEqual(
            [{nodedown, Node, connection_closed}],
            edb_test_support:collected_events()
        ),
        ok
    end).

test_terminating_detaches(Config) ->
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
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
    edb_test_support:on_debugger_node(Config, fun() ->
        {ok, #{node := Node1, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{
            node => {prefix, "debuggee_1"}
        }),

        ok = edb:attach(#{node => Node1, cookie => Cookie}),
        ?assertEqual(edb:attached_node(), Node1),

        ok = edb_test_support:start_event_collector(),

        % Let the event collector get an event
        {ok, SyncRef} = edb_test_support:event_collector_send_sync(),

        % Reverse-attach to a different node
        {ok, #{reverse_attach_ref := Ref, erl_code_to_inject := InjectedCode}} = edb:reverse_attach(#{
            name_domain => shortnames
        }),

        % Subscribe to events to receive reverse attach result
        {ok, Subscription} = edb:subscribe(),

        {ok, #{node := Node2}} = edb_test_support:start_peer_node(Config, #{
            extra_args => ["-eval", InjectedCode]
        }),
        {ok, Node2} = wait_reverse_attach_event(Subscription, Ref),
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

-spec create_test_source_that_spawns_node() -> string().
create_test_source_that_spawns_node() ->
    "-module(test_mod).                                  %L01\n"
    "-export([test_fun/2]).                              %L02\n"
    "test_fun(Receiver, Config) ->                       %L03\n"
    "     {ok, #{node := Node2, peer := Peer2}} =        %L04\n"
    "        edb_test_support:start_peer_node(           %L05\n"
    "           Config,                                  %L06\n"
    "           #{copy_code_path => true}                %L07\n"
    "        ),                                          %L08\n"
    "      Receiver ! {node_created, Node2},             %L09\n"
    "      ok = edb_test_support:stop_peer(Peer2),       %L10\n"
    "     ok.                                            %L11\n".

-spec wait_reverse_attach_event(Subscription :: edb:event_subscription(), Ref :: reference()) ->
    {ok, node()} | timeout | {error, node(), {bootstrap_failed, edb:bootstrap_failure()}}.
wait_reverse_attach_event(Subscription, Ref) ->
    receive
        {edb_event, Subscription, {reverse_attach, Ref, {attached, Node}}} ->
            {ok, Node};
        {edb_event, Subscription, {reverse_attach_timeout, Ref}} ->
            timeout;
        {edb_event, Subscription, {reverse_attach, Ref, {error, Node, {bootstrap_failed, Reason}}}} ->
            {error, Node, {bootstrap_failed, Reason}};
        {edb_event, Subscription, {reverse_attach, Ref, Unexpected}} ->
            error({unexpected_reverse_attach, Unexpected})
    after 10_000 -> timeout
    end.
