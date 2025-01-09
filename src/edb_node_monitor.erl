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

-behavior(gen_server).

%% Public API
-export([start/0]).
-export([attach/2, detach/0, attached_node/0]).
-export([subscribe/0, unsubscribe/1]).

%% gen_server callbacks
-export([init/1, terminate/2, handle_call/3, handle_cast/2, handle_info/2]).

%% -------------------------------------------------------------------
%% Types
%% -------------------------------------------------------------------

-type start_opts() :: [].

-type state() :: #{
    % Cached in a persistent-term while `up`
    attached_node :=
        not_attached
        | {attaching, node(), Caller :: gen_server:from(), TimerRef :: undefined | reference()}
        | {up, node()}
        | {down, node()},
    event_subscribers := edb_events:subscribers()
}.

%% -------------------------------------------------------------------
%% Public API
%% -------------------------------------------------------------------

-spec start() -> gen_server:start_ret().
start() ->
    gen_server:start(
        {local, ?MODULE},
        ?MODULE,
        [],
        []
    ).

-spec attach(node(), timeout()) -> ok | {error, Reason} when
    Reason ::
        nodedown
        | edb:start_error()
        | term().
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

-spec subscribe() -> {ok, edb:event_subscription()}.
subscribe() ->
    call({subscribe_to_events, self()}).

-spec unsubscribe(Subscription) -> ok when
    Subscription :: edb:event_subscription().
unsubscribe(Subscription) ->
    call({remove_event_subscription, Subscription}).

%% -------------------------------------------------------------------
%% Requests
%% -------------------------------------------------------------------

-type call_request() ::
    {attach, node(), timeout()}
    | detach
    | {subscribe_to_events, pid()}
    | {remove_event_subscription, edb:event_subscription()}.

-spec call(call_request()) -> dynamic().
call(Request) ->
    ensure_started(),
    case gen_server:call(?MODULE, Request, infinity) of
        badarg -> error(badarg);
        not_attached -> error(not_attached);
        Result -> Result
    end.

-type cast_request() ::
    {try_attach, node()}.

%% -------------------------------------------------------------------
%% gen_server callbacks
%% -------------------------------------------------------------------

-spec init(start_opts()) -> {ok, state()}.
init([]) ->
    State = #{
        attached_node => not_attached,
        event_subscribers => edb_events:no_subscribers()
    },
    ok = net_kernel:monitor_nodes(true, #{node_type => all, nodedown_reason => true}),
    {ok, State}.

-spec terminate(Reason :: term(), State :: state()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec handle_cast(Request, state()) -> Result when
    Request :: cast_request(),
    Result :: {noreply, state()}.
handle_cast({try_attach, Node}, State0) ->
    case State0 of
        #{attached_node := {attaching, Node, _, _}} ->
            case net_kernel:connect_node(Node) of
                false ->
                    schedule_try_attach_after(50, Node),
                    {noreply, State0};
                _ ->
                    State1 = on_node_connected(State0),
                    {noreply, State1}
            end;
        _ ->
            {noreply, State0}
    end.

-spec handle_call(Request, From, state()) -> Result when
    Request :: call_request(),
    From :: gen_server:from(),
    Result :: {reply, Reply :: term(), NewState :: state()} | {noreply, NewState :: state()}.
handle_call({attach, Node, AttachTimeout}, From, State) ->
    attach_impl(Node, AttachTimeout, From, State);
handle_call(detach, _From, State) ->
    detach_impl(State);
handle_call({subscribe_to_events, Pid}, _From, State0) ->
    subscribe_to_events_impl(Pid, State0);
handle_call({remove_event_subscription, Subscription}, _From, State0) ->
    remove_event_subscription_impl(Subscription, State0);
handle_call(UnknownRequest, _From, State) ->
    {reply, {error, {undef, UnknownRequest}}, State}.

-spec handle_info(Info, State :: state()) -> {noreply, state()} when
    Info ::
        {nodedown, node(), #{node_type := hidden | visible, nodedown_reason := term()}}
        | {nodeup, node(), #{node_type := hidden | visible}}
        | {timeout, TimeRef :: reference(), attaching}
        | {'DOWN', MonitorRef :: reference(), process, pid(), Info :: term()}.
handle_info({nodedown, Node, #{node_type := _, nodedown_reason := Reason}}, State) ->
    nodedown_impl(Node, Reason, State);
handle_info({nodeup, Node, _}, State0 = #{attached_node := {attaching, Node, _, _}}) ->
    State1 = on_node_connected(State0),
    {noreply, State1};
handle_info({timeout, TimerRef, attaching}, State0 = #{attached_node := {attaching, _Node, Caller, TimerRef}}) ->
    gen_server:reply(Caller, {error, nodedown}),
    State1 = State0#{attached_node := not_attached},
    {noreply, State1};
handle_info({'DOWN', MonitorRef, process, _Pid, _Info}, State0 = #{event_subscribers := Subs0}) ->
    Subs1 = edb_events:process_down(MonitorRef, Subs0),
    State1 = State0#{event_subscribers := Subs1},
    {noreply, State1};
handle_info(_Info, State) ->
    {noreply, State}.

%% -------------------------------------------------------------------
%% handle_call and handle_info implementations
%% -------------------------------------------------------------------
-spec attach_impl(Node, AttachTimeout, From, State) -> {reply, Reply, State} | {noreply, State} when
    Node :: node(),
    AttachTimeout :: timeout(),
    From :: gen_server:from(),
    Reply :: ok | {error, Reason},
    Reason ::
        attachment_in_progress
        | nodedown
        | edb:start_error()
        | term(),
    State :: state().
attach_impl(_, _, _, State = #{attached_node := {attaching, _, _, _}}) ->
    {reply, {error, attachment_in_progress}, State};
attach_impl(Node, AttachTimeout, From, State0) ->
    case net_kernel:connect_node(Node) of
        false when AttachTimeout =:= 0 ->
            {reply, {error, nodedown}, State0};
        false ->
            Timer =
                case AttachTimeout of
                    infinity -> undefined;
                    TimeoutInMs -> erlang:start_timer(TimeoutInMs, self(), attaching)
                end,
            State1 = State0#{attached_node := {attaching, Node, From, Timer}},
            schedule_try_attach(Node),
            {noreply, State1};
        _ ->
            case State0 of
                #{attached_node := {up, Node}} ->
                    % Attaching to the same node is a no-op
                    {reply, ok, State0};
                _ ->
                    {reply, _, State1} = detach_impl(State0),
                    State2 = State1#{attached_node := {attaching, Node, From, undefined}},
                    State3 = on_node_connected(State2),
                    {noreply, State3}
            end
    end.

-spec detach_impl(State) -> {reply, ok | not_attached, State} when
    State :: state().
detach_impl(State0) ->
    case State0 of
        #{attached_node := {up, _Node}, event_subscribers := Subs} ->
            State1 = lists:foldl(
                fun(Subscription, StateK) ->
                    {reply, _, StateKplus1} = remove_event_subscription_impl(Subscription, StateK),
                    StateKplus1
                end,
                State0,
                edb_events:subscriptions(Subs)
            ),
            State2 = State1#{attached_node := not_attached},
            persistent_term:erase({?MODULE, attached_node}),
            {reply, ok, State2};
        #{attached_node := {down, Node}, event_subscribers := Subs} ->
            % Previous node may have gone down, if we have any subscribers is because
            % we failed to detect it in time, so let's notify now
            ok = edb_events:broadcast({nodedown, Node, unknown}, Subs),
            State1 = #{attached_node => not_attached, event_subscribers => edb_events:no_subscribers()},
            {reply, not_attached, State1};
        #{attached_node := not_attached} ->
            {reply, not_attached, State0}
    end.

-spec subscribe_to_events_impl(Pid, State0) -> {reply, {ok, Subscription} | not_attached, State1} when
    Pid :: pid(),
    State0 :: state(),
    Subscription :: edb_events:subscription(),
    State1 :: state().
subscribe_to_events_impl(Pid, State0) ->
    % We let edb_server create a subscription; and we will save it too, so we can reuse
    % it later for "disconnected" events created from here
    case call_edb_server({subscribe_to_events, Pid}, State0) of
        {not_attached, State1} ->
            {reply, not_attached, State1};
        {reply, {ok, Subscription}, State1} ->
            #{event_subscribers := Subs0} = State1,
            MonitorRef = erlang:monitor(process, Pid),
            {ok, Subs1} = edb_events:subscribe(Subscription, Pid, MonitorRef, Subs0),
            State2 = State1#{event_subscribers := Subs1},
            {reply, {ok, Subscription}, State2}
    end.

-spec remove_event_subscription_impl(Subscription, State0) -> {reply, ok | not_attached, State1} when
    Subscription :: edb_events:subscription(),
    State0 :: state(),
    State1 :: state().
remove_event_subscription_impl(Subscription, State0) ->
    {Result, State2} =
        case call_edb_server({remove_event_subscription, Subscription}, State0) of
            {not_attached, State1} ->
                {not_attached, State1};
            {reply, ok, State1} ->
                {ok, State1}
        end,
    #{event_subscribers := Subs0} = State2,
    State3 =
        case edb_events:unsubscribe(Subscription, Subs0) of
            not_subscribed ->
                State2;
            {ok, {MonitorRef, Subs1}} ->
                true = erlang:demonitor(MonitorRef),
                State2#{event_subscribers := Subs1}
        end,
    {reply, Result, State3}.

-spec nodedown_impl(Node, Reason, State) -> {noreply, State} when
    Node :: node(),
    Reason :: term(),
    State :: state().
nodedown_impl(Node, Reason, State0) ->
    case State0 of
        #{attached_node := {Attachment, Node}} when Attachment =:= up; Attachment =:= down ->
            #{event_subscribers := Subs} = State0,
            ok = edb_events:broadcast({nodedown, Node, Reason}, Subs),
            State1 = State0#{attached_node := not_attached},
            persistent_term:erase({?MODULE, attached_node}),
            {noreply, State1};
        _ ->
            {noreply, State0}
    end.

%% -------------------------------------------------------------------
%% Helpers
%% -------------------------------------------------------------------

-spec schedule_try_attach(node()) -> ok.
schedule_try_attach(Node) ->
    ok = gen_server:cast(?MODULE, {try_attach, Node}).

-spec schedule_try_attach_after(Delay :: non_neg_integer(), node()) -> ok.
schedule_try_attach_after(Delay, Node) ->
    spawn_link(fun() ->
        receive
        after Delay -> schedule_try_attach(Node)
        end
    end),
    ok.

-spec on_node_connected(state()) -> state().
on_node_connected(State0 = #{attached_node := {attaching, Node, Caller, Timer}}) ->
    {TimerAction, State2} =
        % elp:ignore W0014 (cross_node_eval) - Debugging tool, expected.
        try erpc:call(Node, edb_server, ensure_started, []) of
            Error = {error, _} ->
                State1 = State0#{attached_node := not_attached},
                gen_server:reply(Caller, Error),
                {cancel_timer, State1};
            ok ->
                State1 = State0#{attached_node := {up, Node}},
                persistent_term:put({?MODULE, attached_node}, Node),
                gen_server:reply(Caller, ok),
                {cancel_timer, State1}
        catch
            error:{erpc, _} ->
                % rpc may not be available yet, so we try again later
                schedule_try_attach(Node),
                {leave_timer, State0};
            error:{exception, undef, [{edb_server, ensure_started, [], []}]} ->
                % edb_server module not yet available, so we try again later
                schedule_try_attach(Node),
                {leave_timer, State0}
        end,
    case {TimerAction, Timer} of
        {leave_timer, _} -> ok;
        {cancel_timer, undefined} -> ok;
        {cancel_timer, TimerRef} -> erlang:cancel_timer(TimerRef)
    end,
    State2.

-spec ensure_started() -> ok.
ensure_started() ->
    case erlang:whereis(?MODULE) of
        undefined ->
            case start() of
                {ok, _Pid} -> ok;
                {error, {already_started, _Pid}} -> ok
            end;
        Pid when is_pid(Pid) ->
            ok
    end.

-spec call_edb_server(Request :: edb_server:call_request(), State) -> Result when
    State :: state(),
    Result :: {reply, dynamic(), State} | {not_attached, State}.
call_edb_server(Request, State0) ->
    case State0 of
        #{attached_node := {up, Node}} ->
            try
                {reply, gen_server:call({edb_server, Node}, Request), State0}
            catch
                exit:{noproc, {gen_server, call, Args}} when is_list(Args) ->
                    % The edb_server on the debuggee crashed or was stopped
                    State1 = State0#{attached_node := not_attached, event_subscribers := edb_events:no_subscribers()},
                    persistent_term:erase({?MODULE, attached_node}),
                    {not_attached, State1};
                exit:{{nodedown, Node}, {gen_server, call, Args}} when is_list(Args) ->
                    State1 = State0#{attached_node := {down, Node}},
                    persistent_term:erase({?MODULE, attached_node}),
                    {not_attached, State1}
            end;
        _ ->
            {not_attached, State0}
    end.
