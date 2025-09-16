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

-module(edb_node_monitor).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-moduledoc false.

-behavior(gen_statem).

%% Public API
-export([start_link/0]).
-export([attach/2, detach/0, attached_node/0, nodes/0]).
-export([expect_reverse_attach/3, reverse_attach_notification/2]).

-export([subscribe/0, unsubscribe/1]).
-export([safe_sname_hostname/0]).

%% gen_statem callbacks
-export([init/1, callback_mode/0, handle_event/4]).

%% -------------------------------------------------------------------
%% Types
%% -------------------------------------------------------------------

-type start_opts() :: [].

-type state() ::
    % NB. node is in a persistent-term while in the `up` state
    #{
        state := not_attached
    }
    | #{
        state := attachment_in_progress,
        type := attach,
        node := node(),
        caller := gen_statem:from()
    }
    | #{
        state := attachment_in_progress,
        type := reverse_attach,
        gatekeeper := edb_gatekeeper:id(),
        reverse_attach_ref => reference(),
        multi_node_reverse_attach_code => none | binary(),
        multi_node_enabled := boolean()
    }
    | #{
        state := up,
        gatekeeper := none | edb_gatekeeper:id(),
        nodes := #{node() => []},
        down_nodes := #{node() => []},
        reverse_attach_ref => reference(),
        multi_node_enabled := boolean(),
        multi_node_reverse_attach_code => none | binary()
    }.

-type data() :: #{
    event_subscribers := edb_events:subscribers()
}.

-type no_reply() ::
    keep_state_and_data
    | {keep_state, data()}
    | {next_state, state(), data()}
    | {next_state, state(), data(), action()}.

-type reply(A) ::
    {keep_state_and_data, actions(A)}
    | {keep_state, data(), {reply, gen_statem:from(), A}}
    | {next_state, state(), data(), actions(A)}.

-type action() ::
    {state_timeout, timeout(), Content :: term()}.

-type action(A) ::
    {reply, gen_statem:from(), A}.

-type actions(A) ::
    action(A) | [action() | action(A)].

-type expect_reverse_attach_args() :: #{
    gatekeeper_id := edb_gatekeeper:id(),
    reverse_attach_ref := reference(),
    timeout := timeout(),
    reverse_attach_code := none | binary(),
    multi_node_enabled := boolean()
}.

%% -------------------------------------------------------------------
%% Public API
%% -------------------------------------------------------------------

-spec start_link() -> gen_statem:start_ret().
start_link() ->
    gen_statem:start_link(
        {local, ?MODULE},
        ?MODULE,
        [],
        []
    ).

-spec attach(Node, Timeout) -> ok | {error, Reason} when
    Node :: node(),
    Timeout :: timeout(),
    Reason ::
        attachment_in_progress
        | nodedown
        | {bootstrap_failed, edb:bootstrap_failure()}.
attach(Node, AttachTimeout) when is_atom(Node), AttachTimeout =:= infinity orelse AttachTimeout >= 0 ->
    call({attach, Node, AttachTimeout}).

-spec detach() -> ok.
detach() ->
    call(detach).

-spec attached_node() -> node().
attached_node() ->
    try
        persistent_term:get({?MODULE, attached_node})
    catch
        error:badarg ->
            error(not_attached)
    end.

-spec nodes() -> #{node() => []}.
nodes() ->
    call(nodes).

-spec expect_reverse_attach(Id, ReverseAttachRef, Opts) ->
    ok | {error, Reason}
when
    Id :: edb_gatekeeper:id(),
    ReverseAttachRef :: reference(),
    Opts :: #{
        timeout := timeout(),
        reverse_attach_code := none | binary(),
        multi_node_enabled := boolean()
    },
    Reason :: attachment_in_progress.
expect_reverse_attach(Id, ReverseAttachRef, Opts) ->
    call(
        {expect_reverse_attach, Opts#{
            gatekeeper_id => Id,
            reverse_attach_ref => ReverseAttachRef
        }}
    ).

-spec reverse_attach_notification(Id, Node) -> ok | {error, edb:bootstrap_failure()} when
    Id :: edb_gatekeeper:id(),
    Node :: node().
reverse_attach_notification(Id, Node) ->
    gen_statem:cast(?MODULE, {reverse_attach_notification, Id, Node}).

-spec subscribe() -> {ok, edb:event_subscription()}.
subscribe() ->
    call({subscribe_to_events, self()}).

-spec unsubscribe(Subscription) -> ok when
    Subscription :: edb:event_subscription().
unsubscribe(Subscription) ->
    call({remove_event_subscription, Subscription}).

-doc """
Returns a host that is safe to use as a node shortname.
Normally, net_kernel uses `inet:gethostname/0` to get the hostname, when
building an sname. This is problematic in cases where you have a fleet
of hosts and the naming convention is `nnn.my.fleet.net` where `nnn` is
an integer. In this case, `inet:gethostname/0` will return `nnn`, so you
get a node name like `foo@nnn`, but if you then try to connect to this
node, inet_tcp_dist will end up calling `inet:getaddr/2` on `nnn`, which
will incorrectly interpret `nnn` as an IP address and the connection will
of course fail.

So let's try a couple of options and validate that they can be resolved
properly.
""".
-spec safe_sname_hostname() -> atom().
safe_sname_hostname() ->
    Candidates = [
        case inet:gethostname() of
            {ok, H} -> list_to_atom(H)
        end,

        'localhost',

        % This is 127.0.0.1 seen as a base-256 integer:
        % 127*256^3 + 0*256^2 + 0*256^1 + 1*256^0 = 2130706433
        '2130706433'
    ],

    InetFamily = inet_tcp:family(),
    {ok, IfAddrs} = inet:getifaddrs(),
    Ips = [Ip || {_IfName, IfOpts} <- IfAddrs, {addr, Ip} <- IfOpts],
    ResolvesCorrectly = fun(Hostname) ->
        case inet:getaddr(Hostname, InetFamily) of
            {error, _} -> false;
            {ok, Ip} -> lists:member(Ip, Ips)
        end
    end,
    case lists:search(ResolvesCorrectly, Candidates) of
        {value, Hostname} -> Hostname;
        false -> error("no suitable hostname for sname!")
    end.

%% -------------------------------------------------------------------
%% Requests
%% -------------------------------------------------------------------

-type call_request() ::
    {attach, node(), timeout()}
    | {expect_reverse_attach, expect_reverse_attach_args()}
    | {reverse_attach_notification, edb_gatekeeper:id(), node()}
    | nodes
    | detach
    | {subscribe_to_events, pid()}
    | {remove_event_subscription, edb:event_subscription()}.

-spec call(call_request()) -> dynamic().
call(Request) ->
    case gen_statem:call(?MODULE, Request, infinity) of
        badarg ->
            error(badarg);
        not_attached ->
            error(not_attached);
        {error, cannot_attach_to_new_node_when_multi_node_enabled} ->
            error(cannot_attach_to_new_node_when_multi_node_enabled);
        Result ->
            Result
    end.

-type cast_request() ::
    {try_attach, node()}.

-type info_message() ::
    {nodedown, node(), #{node_type := hidden | visible, nodedown_reason := term()}}
    | {nodeup, node(), #{node_type := hidden | visible}}
    | {'DOWN', MonitorRef :: reference(), process, pid(), Info :: term()}.

%% -------------------------------------------------------------------
%% gen_statem callbacks
%% -------------------------------------------------------------------

-spec init(start_opts()) -> {ok, state(), data()}.
init([]) ->
    State = #{state => not_attached},
    Data = #{event_subscribers => edb_events:no_subscribers()},
    ok = net_kernel:monitor_nodes(true, #{node_type => all, nodedown_reason => true}),
    {ok, State, Data}.

-spec callback_mode() -> handle_event_function.
callback_mode() -> handle_event_function.

-spec handle_event
    (cast, cast_request(), state(), data()) -> gen_statem:event_handler_result(state(), data());
    ({call, gen_statem:from()}, call_request(), state(), data()) -> gen_statem:event_handler_result(state(), data());
    (info, info_message(), state(), data()) -> gen_statem:event_handler_result(state(), data()).
handle_event(cast, {try_attach, Node}, State0, Data0) ->
    try_attach_impl(Node, State0, Data0);
handle_event({call, From}, {attach, Node, AttachTimeout}, State, Data) ->
    attach_impl(Node, AttachTimeout, From, State, Data);
handle_event(
    {call, From},
    {expect_reverse_attach, ExpectReverseAttachArgs},
    State,
    Data
) ->
    expect_reverse_attach_impl(
        ExpectReverseAttachArgs, From, State, Data
    );
handle_event(cast, {reverse_attach_notification, GatekeeperId, Node}, State, Data) ->
    reverse_attach_notification_impl(GatekeeperId, Node, State, Data);
handle_event({call, From}, nodes, State, Data) ->
    nodes_impl(From, State, Data);
handle_event({call, From}, detach, State, Data) ->
    detach_impl(From, State, Data);
handle_event({call, From}, {subscribe_to_events, Pid}, State, Data) ->
    subscribe_to_events_impl(Pid, From, State, Data);
handle_event({call, From}, {remove_event_subscription, Subscription}, State, Data) ->
    remove_event_subscription_impl(Subscription, From, State, Data);
handle_event(info, {nodedown, Node, #{node_type := _, nodedown_reason := Reason}}, State, Data) ->
    nodedown_impl(Node, Reason, State, Data);
handle_event(info, {nodeup, Node, _}, State0 = #{state := attachment_in_progress, type := attach, node := Node}, Data0) ->
    State1 = on_node_connected(State0, Data0),
    {next_state, State1, Data0};
handle_event(state_timeout, waiting_for_node, State0 = #{state := attachment_in_progress, type := attach}, Data0) ->
    State1 = #{state => not_attached},
    Caller = maps:get(caller, State0),
    {next_state, State1, Data0, {reply, Caller, {error, nodedown}}};
handle_event(info, {'DOWN', MonitorRef, process, _Pid, _Info}, _, Data0) ->
    Subs0 = maps:get(event_subscribers, Data0),
    Subs1 = edb_events:process_down(MonitorRef, Subs0),
    Data1 = Data0#{event_subscribers := Subs1},
    {keep_state, Data1};
handle_event(
    state_timeout,
    waiting_for_reverse_attach,
    _State0 = #{state := attachment_in_progress, type := reverse_attach, reverse_attach_ref := ReverseAttachRef},
    Data0
) ->
    Subs = maps:get(event_subscribers, Data0),
    ok = edb_events:broadcast({reverse_attach_timeout, ReverseAttachRef}, Subs),
    State1 = #{state => not_attached},
    {next_state, State1, Data0};
handle_event(info, _, _State, _Data) ->
    keep_state_and_data.

%% -------------------------------------------------------------------
%% Event handling implementations
%% -------------------------------------------------------------------

-spec try_attach_impl(Node, state(), data()) -> no_reply() when
    Node :: node().
try_attach_impl(Node, State0, Data0) ->
    case State0 of
        #{state := attachment_in_progress, type := attach, node := Node} ->
            case net_kernel:connect_node(Node) of
                false ->
                    schedule_try_attach_after(50, Node),
                    keep_state_and_data;
                _ ->
                    State1 = on_node_connected(State0, Data0),
                    {next_state, State1, Data0}
            end;
        _ ->
            keep_state_and_data
    end.

-spec attach_impl(Node, AttachTimeout, From, state(), data()) -> no_reply() | reply(ok | {error, Reason}) when
    Node :: node(),
    AttachTimeout :: timeout(),
    From :: gen_statem:from(),
    Reason ::
        attachment_in_progress
        | nodedown
        | cannot_attach_to_new_node_when_multi_node_enabled
        | {bootstrap_failed, edb:bootstrap_failure()}.
attach_impl(_, _, From, #{state := attachment_in_progress}, _) ->
    {keep_state_and_data, {reply, From, {error, attachment_in_progress}}};
attach_impl(Node, AttachTimeout, From, State0, Data0) ->
    case net_kernel:connect_node(Node) of
        false when AttachTimeout =:= 0 ->
            {keep_state_and_data, {reply, From, {error, nodedown}}};
        false ->
            State1 =
                #{
                    state => attachment_in_progress,
                    type => attach,
                    node => Node,
                    caller => From
                },
            schedule_try_attach(Node),
            {next_state, State1, Data0, {state_timeout, AttachTimeout, waiting_for_node}};
        _ ->
            NodeInFocus = persistent_term:get({?MODULE, attached_node}, []),
            case State0 of
                #{state := up, nodes := #{Node := _}} ->
                    case Node =:= NodeInFocus of
                        true ->
                            % Attaching to the same node is a no-op
                            {keep_state_and_data, {reply, From, ok}};
                        false ->
                            true = persistent_term:erase({?MODULE, attached_node}),
                            ok = persistent_term:put({?MODULE, attached_node}, Node),
                            gen_statem:reply(From, ok),
                            {keep_state_and_data, {reply, From, ok}}
                    end;
                #{state := up, multi_node_enabled := true} ->
                    {keep_state_and_data, {reply, From, {error, cannot_attach_to_new_node_when_multi_node_enabled}}};
                _ ->
                    {_, _, Data1} = detach_impl_1(State0, Data0),
                    State2 =
                        #{
                            state => attachment_in_progress,
                            type => attach,
                            node => Node,
                            caller => From
                        },
                    State3 = on_node_connected(State2, Data1),
                    {next_state, State3, Data1}
            end
    end.

-spec expect_reverse_attach_impl(
    ExpectReverseAttachArgs, From, state(), data()
) ->
    reply(ok | {error, Reason})
when
    ExpectReverseAttachArgs :: expect_reverse_attach_args(),
    From :: gen_statem:from(),
    Reason :: attachment_in_progress.
expect_reverse_attach_impl(_, From, #{state := attachment_in_progress}, _) ->
    {keep_state_and_data, {reply, From, {error, attachment_in_progress}}};
expect_reverse_attach_impl(
    #{
        gatekeeper_id := GatekeeperId,
        reverse_attach_ref := ReverseAttachRef,
        timeout := ReverseAttachTimeout,
        reverse_attach_code := ReverseAttachCode,
        multi_node_enabled := MultiNodeEnabled
    },
    From,
    State0,
    Data0
) ->
    {_, _, Data1} = detach_impl_1(State0, Data0),
    State1 = #{
        state => attachment_in_progress,
        type => reverse_attach,
        gatekeeper => GatekeeperId,
        reverse_attach_ref => ReverseAttachRef,
        multi_node_reverse_attach_code => ReverseAttachCode,
        multi_node_enabled => MultiNodeEnabled
    },
    {next_state, State1, Data1, [
        {reply, From, ok},
        {state_timeout, ReverseAttachTimeout, waiting_for_reverse_attach}
    ]}.

-spec reverse_attach_notification_impl(GatekeeperId, Node, state(), data()) -> no_reply() when
    GatekeeperId :: edb_gatekeeper:id(),
    Node :: node().
reverse_attach_notification_impl(
    GatekeeperId,
    Node,
    State0 = #{
        state := attachment_in_progress,
        type := reverse_attach,
        gatekeeper := GatekeeperId
    },
    Data0 = #{event_subscribers := Subs}
) ->
    #{
        reverse_attach_ref := ReverseAttachRef,
        multi_node_reverse_attach_code := ReverseAttachCode,
        multi_node_enabled := MultiNodeEnabled
    } = State0,
    Subscribers = edb_events:subscribers(Subs),
    case bootstrap_edb(Node, Subscribers, ReverseAttachCode, pause) of
        {error, BootstrapFailure} ->
            State1 = #{state => not_attached},
            ok = edb_events:broadcast(
                {reverse_attach, ReverseAttachRef, {error, Node, {bootstrap_failed, BootstrapFailure}}}, Subs
            ),
            {next_state, State1, Data0};
        ok ->
            State1 = #{
                state => up,
                gatekeeper => GatekeeperId,
                nodes => #{Node => []},
                down_nodes => #{},
                reverse_attach_ref => ReverseAttachRef,
                multi_node_enabled => MultiNodeEnabled,
                multi_node_reverse_attach_code => ReverseAttachCode
            },
            persistent_term:put({?MODULE, attached_node}, Node),
            ok = edb_events:broadcast({reverse_attach, ReverseAttachRef, {attached, Node}}, Subs),
            {next_state, State1, Data0}
    end;
reverse_attach_notification_impl(
    GatekeeperId,
    Node,
    State0 = #{state := up, multi_node_enabled := true, gatekeeper := GatekeeperId, nodes := Nodes0},
    Data0
) ->
    #{
        reverse_attach_ref := ReverseAttachRef,
        multi_node_reverse_attach_code := ReverseAttachCode
    } = State0,
    #{event_subscribers := Subs} = Data0,
    Subscribers = edb_events:subscribers(Subs),
    case bootstrap_edb(Node, Subscribers, ReverseAttachCode, pause) of
        {error, BootstrapFailure} ->
            ok = edb_events:broadcast(
                {reverse_attach, ReverseAttachRef, {error, Node, {bootstrap_failed, BootstrapFailure}}}, Subs
            ),
            {next_state, State0, Data0};
        ok ->
            Nodes1 = Nodes0#{Node => []},
            ok = edb_events:broadcast({reverse_attach, ReverseAttachRef, {attached, Node}}, Subs),
            State1 = State0#{nodes => Nodes1},
            {next_state, State1, Data0}
    end;
reverse_attach_notification_impl(_, _, _, _) ->
    keep_state_and_data.

-spec nodes_impl(From, state(), data()) -> reply(#{node() => []}) when
    From :: gen_statem:from().
nodes_impl(From, State0, _Data0) ->
    Nodes =
        case State0 of
            #{state := up, nodes := NodesMap} -> NodesMap;
            _ -> #{}
        end,
    {keep_state_and_data, {reply, From, Nodes}}.

-spec detach_impl(From, state(), data()) -> reply(ok | not_attached) when
    From :: gen_statem:from().
detach_impl(From, State0, Data0) ->
    {Reply, State1, Data1} = detach_impl_1(State0, Data0),
    {next_state, State1, Data1, {reply, From, Reply}}.

-spec detach_impl_1(state(), data()) -> {ok | not_attached, state(), data()}.
detach_impl_1(State0, Data0) ->
    Subs = maps:get(event_subscribers, Data0),
    case State0 of
        #{state := up} ->
            {_, Data1} = lists:foldl(
                fun(Subscription, {StateK, DataK}) ->
                    {_, StateKplus1, DataKplus1} = remove_event_subscription_impl_1(Subscription, StateK, DataK),
                    {StateKplus1, DataKplus1}
                end,
                {State0, Data0},
                edb_events:subscriptions(Subs)
            ),
            State2 = #{state => not_attached},
            persistent_term:erase({?MODULE, attached_node}),
            {ok, State2, Data1};
        #{state := not_attached} ->
            {not_attached, State0, Data0}
    end.

-spec subscribe_to_events_impl(Pid, From, state(), data()) -> reply({ok, Subscription} | not_attached) when
    Pid :: pid(),
    From :: gen_statem:from(),
    Subscription :: edb_events:subscription().
subscribe_to_events_impl(Pid, From, State0, Data0) ->
    % We let edb_server create a subscription; and we will save it too, so we can reuse
    % it later for "disconnected" events created from here
    {Reply, State1, Data1} = call_edb_server({subscribe_to_events, Pid}, State0, Data0),
    Subs0 = maps:get(event_subscribers, Data1),
    MonitorRef = erlang:monitor(process, Pid),
    {Subscription, Subs1} =
        case Reply of
            not_attached ->
                {ok, {NewSubscription, NewSubscribers}} = edb_events:subscribe(Pid, MonitorRef, Subs0),
                {NewSubscription, NewSubscribers};
            {reply, {ok, ExistingSubscription}} ->
                {ok, NewSubscribers} = edb_events:subscribe(ExistingSubscription, Pid, MonitorRef, Subs0),
                {ExistingSubscription, NewSubscribers}
        end,
    Data2 = Data1#{event_subscribers := Subs1},
    {next_state, State1, Data2, {reply, From, {ok, Subscription}}}.

-spec remove_event_subscription_impl(Subscription, From, state(), data()) -> reply(ok | not_attached) when
    Subscription :: edb_events:subscription(),
    From :: gen_statem:from().
remove_event_subscription_impl(Subscription, From, State0, Data0) ->
    {Result, State1, Data1} = remove_event_subscription_impl_1(Subscription, State0, Data0),
    {next_state, State1, Data1, {reply, From, Result}}.

-spec remove_event_subscription_impl_1(Subscription, state(), data()) -> {ok | not_attached, state(), data()} when
    Subscription :: edb_events:subscription().
remove_event_subscription_impl_1(Subscription, State0, Data0) ->
    {Result, State2, Data2} =
        case call_edb_server({remove_event_subscription, Subscription}, State0, Data0) of
            {not_attached, State1, Data1} ->
                {not_attached, State1, Data1};
            {{reply, ok}, State1, Data1} ->
                {ok, State1, Data1}
        end,
    Subs0 = maps:get(event_subscribers, Data2),
    Data3 =
        case edb_events:unsubscribe(Subscription, Subs0) of
            not_subscribed ->
                Data2;
            {ok, {MonitorRef, Subs1}} ->
                true = erlang:demonitor(MonitorRef),
                Data2#{event_subscribers := Subs1}
        end,
    {Result, State2, Data3}.

-spec nodedown_impl(Node, Reason, state(), data()) -> no_reply() when
    Node :: node(),
    Reason :: term().
nodedown_impl(Node, Reason, State0, Data0) ->
    case State0 of
        #{state := up, nodes := #{Node := _}} ->
            State1 = handle_node_disconnection(Node, Reason, Data0, State0),
            {next_state, State1, Data0};
        #{state := up, down_nodes := #{Node := _} = DownNodes0} ->
            % We broadcast the nodedown event before, but only now we got the notification
            DownNodes1 = maps:remove(Node, DownNodes0),
            State1 = State0#{down_nodes := DownNodes1},
            {next_state, State1, Data0};
        _ ->
            keep_state_and_data
    end.

%% -------------------------------------------------------------------
%% Helpers
%% -------------------------------------------------------------------

-spec bootstrap_edb(Node, Subscribers, ReverseAttachCode, PauseAction) ->
    ok | {error, edb:bootstrap_failure()}
when
    Node :: node(),
    Subscribers :: #{edb_events:subscription() => pid()},
    ReverseAttachCode :: none | binary(),
    PauseAction :: pause | keep_running.
bootstrap_edb(Node, Subscribers, ReverseAttachCode, PauseAction) ->
    {Module, Binary, Filename} = code:get_object_code(edb_bootstrap),
    % elp:ignore W0014 - Debugging tool, expected.
    case erpc:call(Node, code, load_binary, [Module, Filename, Binary]) of
        {module, edb_bootstrap} ->
            % elp:ignore W0014 - Debugging tool, expected.
            erpc:call(Node, edb_bootstrap, bootstrap_debuggee, [
                node(), Subscribers, ReverseAttachCode, PauseAction
            ]);
        {error, badfile} ->
            {error, {module_injection_failed, edb_bootstrap, incompatible_beam}}
    end.

-spec schedule_try_attach(node()) -> ok.
schedule_try_attach(Node) ->
    ok = gen_statem:cast(?MODULE, {try_attach, Node}).

-spec schedule_try_attach_after(Delay :: non_neg_integer(), node()) -> ok.
schedule_try_attach_after(Delay, Node) ->
    spawn_link(fun() ->
        receive
        after Delay -> schedule_try_attach(Node)
        end
    end),
    ok.

-spec on_node_connected(state(), data()) -> state().
on_node_connected(State0 = #{state := attachment_in_progress, type := attach, node := Node, caller := Caller}, Data0) ->
    #{event_subscribers := Subs} = Data0,
    Subscribers = edb_events:subscribers(Subs),
    State2 =
        try bootstrap_edb(Node, Subscribers, none, keep_running) of
            {error, BootstrapFailure} ->
                State1 = #{state => not_attached},
                gen_statem:reply(Caller, {error, {bootstrap_failed, BootstrapFailure}}),
                State1;
            ok ->
                State1 = #{
                    state => up,
                    gatekeeper => none,
                    nodes => #{Node => []},
                    down_nodes => #{},
                    multi_node_enabled => false
                },
                persistent_term:put({?MODULE, attached_node}, Node),
                gen_statem:reply(Caller, ok),
                State1
        catch
            error:{erpc, _} ->
                % rpc may not be available yet, so we try again later
                schedule_try_attach(Node),
                State0
        end,
    State2.

-spec call_edb_server(Request :: edb_server:call_request(), state(), data()) -> Result when
    Result :: {{reply, dynamic()} | not_attached, state(), data()}.
call_edb_server(Request, State0, Data0) ->
    case State0 of
        #{state := up} ->
            Node = persistent_term:get({?MODULE, attached_node}, []),
            try
                {{reply, edb_server:call(Node, Request)}, State0, Data0}
            catch
                exit:{noproc, {gen_server, call, Args}} when is_list(Args) ->
                    % The edb_server on the debuggee crashed or was stopped
                    State1 = #{state => not_attached},
                    Data1 = #{event_subscribers => edb_events:no_subscribers()},
                    persistent_term:erase({?MODULE, attached_node}),
                    {not_attached, State1, Data1};
                exit:{{nodedown, Node}, {gen_server, call, Args}} when is_list(Args) ->
                    State1 = handle_node_disconnection(Node, unknown, Data0, State0),
                    {not_attached, State1, Data0}
            end;
        _ ->
            {not_attached, State0, Data0}
    end.

-spec handle_node_disconnection(Node, Reason, data(), State0) -> State1 when
    Node :: node(),
    Reason :: term(),
    State0 :: state(),
    State1 :: state().
handle_node_disconnection(Node, Reason, Data0, State0 = #{state := up}) ->
    #{event_subscribers := Subs} = Data0,
    ok = edb_events:broadcast({nodedown, Node, Reason}, Subs),

    #{nodes := #{Node := _} = Nodes0, down_nodes := DownNodes0} = State0,
    Nodes1 = maps:remove(Node, Nodes0),
    DownNodes1 = DownNodes0#{Node => []},

    IsNodeInFocus = Node == persistent_term:get({?MODULE, attached_node}, []),
    case IsNodeInFocus of
        true ->
            persistent_term:erase({?MODULE, attached_node}),
            case maps:size(Nodes1) of
                0 -> #{state => not_attached};
                _ -> State0#{nodes := Nodes1, down_nodes := DownNodes1}
            end;
        false ->
            State0#{nodes := Nodes1, down_nodes := DownNodes1}
    end.
