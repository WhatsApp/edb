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
-module(edb_server).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-moduledoc false.
-behaviour(gen_server).

%% External exports
-export([start/0, stop/0, find/0]).

%% Reloading module support
-export([reapply_breakpoints/1, add_module_substitute/3, remove_module_substitute/1]).

%% gen_server call wrappers that will throw on invariant violations
-export([call/2, call/3]).

%% gen_server callbacks
-export([init/1, terminate/2, handle_call/3, handle_cast/2, handle_info/2]).

%% Exceptions
-export([raise/2, raise/3, invariant_violation/1]).

-export_type([call_request/0]).

%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------

-type set(A) :: edb_server_sets:set(A).

-type line() :: edb:line().

-type start_opts() :: [].

-export_type([start_error/0]).
-type start_error() :: unsupported | failed_to_register.

-export_type([add_substitute_error/0]).
-type add_substitute_error() :: already_has_breakpoints | already_substituted | is_already_a_substitute.

-export_type([remove_substitute_error/0]).
-type remove_substitute_error() :: not_a_substitute | has_dependent_substitute.

-record(state, {
    debugger_session :: erl_debugger:session(),
    breakpoints :: edb_server_break:breakpoints(),
    suspended_procs :: set(pid()),

    % Sets used to control what to suspend and what not to
    % suspend when pausing.
    % - pids in do_suspend_pid override everything else (so a
    %   pid in this set will be suspended even if it could be
    %   part of an app to be suspended, etc.)
    do_suspend_pids :: set(pid()),
    do_not_suspend_apps :: set(atom()),
    do_not_suspend_regnames :: set(atom()),
    do_not_suspend_pids :: set(pid()),

    event_subscribers :: edb_events:subscribers()
}).

-type state() :: #state{}.

-type procs_spec() :: edb:procs_spec().

%%--------------------------------------------------------------------
%% Macros
%%--------------------------------------------------------------------
-define(is_internal_pid(Pid), (node(Pid) =:= node())).

%%--------------------------------------------------------------------
%% External exports
%%--------------------------------------------------------------------

-spec start() -> ok | {error, start_error()}.
start() ->
    case erl_debugger:supported() of
        false ->
            {error, unsupported};
        true ->
            StartResult = gen_server:start(
                {local, ?MODULE},
                ?MODULE,
                [],
                [{spawn_opt, [{priority, high}]}]
            ),
            case StartResult of
                {ok, _Pid} -> ok;
                Err = {error, Reason} when Reason =:= failed_to_register -> Err
            end
    end.

-spec stop() -> ok.
stop() ->
    ok = gen_server:stop(?MODULE).

-spec find() -> pid() | undefined.
find() ->
    case whereis(?MODULE) of
        undefined -> undefined;
        Pid when is_pid(Pid) -> Pid
    end.

%%--------------------------------------------------------------------
%% Reapply breakpoints
%%--------------------------------------------------------------------

-doc """
Reapply all existing breakpoints for the specified module to the VM.

This function will attempt to set VM breakpoints for all lines that currently
have explicit breakpoints or step breakpoints registered for the given module.

The operation is atomic - either all breakpoints are successfully reapplied, or
none are applied at all. If any individual breakpoint fails to be set, all
previously applied breakpoints from this operation are rolled back and removed.

# Returns
- `ok` - All breakpoints were successfully reapplied
- `{error, Reason}` - Operation failed, no breakpoints were applied; `Reason`
describes the error that occurred when setting the first breakpoint that failed.
""".
-spec reapply_breakpoints(Module) -> 'ok' | {error, Reason} when
    Module :: module(),
    Reason :: edb:add_breakpoint_error().
reapply_breakpoints(Module) ->
    call(node(), {reapply_breakpoints, Module}).

%%--------------------------------------------------------------------
%% Module conversions
%%--------------------------------------------------------------------

-spec to_vm_module(module(), state()) -> edb_server_break:vm_module().
to_vm_module(Module, State) ->
    #state{breakpoints = Breakpoints} = State,
    edb_server_break:to_vm_module(Module, Breakpoints).

-spec from_vm_module(edb_server_break:vm_module(), state()) -> module().
from_vm_module(VmModule, State) ->
    #state{breakpoints = Breakpoints} = State,
    edb_server_break:from_vm_module(VmModule, Breakpoints).

%%--------------------------------------------------------------------
%% Module substitutes
%%--------------------------------------------------------------------

-doc """
Add a module substitute from `Module` to `Substitute`.
When users try to set a breakpoint on `Module`, it will be set on `Substitute` instead.
This handles transitive substitutes as well, so if `Substitute` is substituted by another module,
then setting a breakpoint on `Module` will set it on that module.
If `Module` had breakpoints set, they will be transferred to `Substitute`.
`AddedFrames` is a list of frames that is expected in stack trace when functions in
`Substitute` are called. When transitivity occurs (A -> B -> C), the added frames
from each substitution are accumulated, so the final stack trace will include
frames from both A -> B and B -> C substitutions.

Returns {error, already_has_breakpoints} if `Substitute` already has breakpoints set.
Returns {error, already_substituted} if `Module` is already substituted by another module.
Returns {error, is_already_a_substitute} if `Substitute` is already a substitute of another module.
""".
-spec add_module_substitute(Module :: module(), Substitute :: module(), AddedFrames :: [mfa()]) ->
    ok | {error, add_substitute_error()}.
add_module_substitute(Module, Substitute, AddedFrames) ->
    call(node(), {add_module_substitute, Module, Substitute, AddedFrames}).

-doc """
Remove a module substitute.
All breakpoints on the substituted module will be transferred to the original module.

Returns {error, not_a_substitute} if the module has not been added as a substitute
using add_module_substitute/2.
Returns {error, has_dependent_substitute} if the module is part of a chain where
another substitute depends on it.
""".
-spec remove_module_substitute(SubstituteModule :: module()) -> ok | {error, remove_substitute_error()}.
remove_module_substitute(SubstituteModule) ->
    call(node(), {remove_module_substitute, SubstituteModule}).

%%--------------------------------------------------------------------
%% Requests
%%--------------------------------------------------------------------

-type call_request() ::
    {subscribe_to_events, pid() | #{edb_events:subscription() => pid()}}
    | {remove_event_subscription, edb:event_subscription()}
    | {send_sync_event, edb:event_subscription()}
    | {add_breakpoint, module(), line()}
    | {clear_breakpoint, module(), line()}
    | {clear_breakpoints, module()}
    | get_breakpoints
    | {get_breakpoints, module()}
    | {set_breakpoints, module(), [line()]}
    | {reapply_breakpoints, module()}
    | get_breakpoints_hit
    | {add_module_substitute, module(), module(), [mfa()]}
    | {remove_module_substitute, module()}
    | pause
    | continue
    | is_paused
    | {process_info, pid(), [edb:process_info_field()]}
    | {processes, [edb:process_info_field()]}
    | {excluded_processes, [edb:process_info_field()]}
    | {step_over, pid()}
    | {step_in, pid()}
    | {step_out, pid()}
    | {exclude_processes, [procs_spec()]}
    | {unexclude_processes, [procs_spec()]}
    | {stack_frames, pid()}
    | {stack_frame_vars, pid(), edb:frame_id(), Size :: non_neg_integer()}
    | {eval, eval_opts(Result :: term())}.

-type cast_request() ::
    term().

-type eval_opts(Result) ::
    #{
        pid := pid(),
        frame_id := edb:frame_id(),
        max_term_size := non_neg_integer(),
        timeout := timeout(),
        function := fun((Vars :: edb:stack_frame_vars()) -> Result),
        dependencies := [module()]
    }.

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

-spec init(start_opts()) -> {ok, state()} | {error, start_error()}.
init([]) ->
    case erl_debugger:register(self()) of
        {error, already_exists} ->
            {error, failed_to_register};
        {ok, DebuggerSession} ->
            % We trap exit so that terminate/1 gets called in that case too
            % and we get a chance to clean-up
            erlang:process_flag(trap_exit, true),
            {ok, #state{
                debugger_session = DebuggerSession,
                breakpoints = edb_server_break:create(),
                suspended_procs = #{},
                do_suspend_pids = #{},
                do_not_suspend_apps = #{kernel => []},
                do_not_suspend_regnames = #{},
                do_not_suspend_pids = #{},
                event_subscribers = edb_events:no_subscribers()
            }}
    end.

-spec terminate(Reason :: term(), State :: state()) -> ok.
terminate(Reason, State0) ->
    erl_debugger:unregister(self(), State0#state.debugger_session),
    BPs = get_breakpoints(State0),
    State1 = maps:fold(
        fun(VmModule, _ModuleBPS, StateN) ->
            {reply, _, StateN_plus_1} = clear_breakpoints_impl(from_vm_module(VmModule, State0), StateN),
            StateN_plus_1
        end,
        State0,
        BPs
    ),
    {ok, _ActuallyResumed, State2} = resume_processes(all, termination, State1),
    ok = edb_events:broadcast({terminated, Reason}, State2#state.event_subscribers),
    ok.

-spec handle_cast(Request, state()) -> Result when
    Request :: cast_request(),
    Result :: {noreply, state()} | {stop, shutdown, state()}.
handle_cast(_, _State) ->
    error(not_implemented).

-spec call(Node :: node(), Request :: call_request()) -> dynamic().
call(Node, Request) ->
    call(Node, Request, 5_000).

-spec call(Node :: node(), Request :: call_request(), Timeout :: pos_integer() | infinity) -> dynamic().
call(Node, Request, Timeout) ->
    case gen_server:call({?MODULE, Node}, Request, Timeout) of
        {finished, Reply} ->
            Reply;
        {raised, Class, {Reason, ST}} when Class =:= error; Class =:= throw; Class =:= exit ->
            erlang:raise(Class, Reason, ST)
    end.

-doc """
Abort the execution and raise an exception on the calling client side.

The gen_server state at the start of the request will be preserved, so
it is the caller's responsibility to ensure that things are left in a
consistent state.
""".
-spec raise(Class, Reason) -> no_return() when
    Class :: error | exit | throw,
    Reason :: term().
raise(Class, Reason) ->
    throw({raised, Class, Reason}).

-doc """
Like `raise/2`, but specifying the stacktrace to be reported.
""".
-spec raise(Class, Reason, ST) -> no_return() when
    Class :: error | exit | throw,
    Reason :: term(),
    ST :: erlang:stacktrace().
raise(Class, Reason, ST) ->
    erlang:raise(throw, {raised, Class, Reason}, ST).

-doc """
Abort due to invariant violation. Will be raised as an error on the caller side.
""".
-spec invariant_violation(Reason :: term()) -> no_return().
invariant_violation(Reason) ->
    raise(error, {invariant_violation, Reason}).

-spec handle_call(Request, From, state()) -> Result when
    Request :: call_request(),
    From :: gen_server:from(),
    Result :: {reply, Reply :: term(), NewState :: state()} | {noreply, NewState :: state()}.
handle_call(Request, From, State) ->
    try dispatch_call(Request, From, State) of
        {reply, Reply, NewState} -> {reply, {finished, Reply}, NewState}
    catch
        throw:{raised, Class, Reason}:ST ->
            {reply, {raised, Class, {Reason, ST}}, State}
    end.

-spec dispatch_call(Request, From, state()) -> Result when
    Request :: call_request(),
    From :: gen_server:from(),
    Result :: {reply, Reply :: term(), NewState :: state()} | {noreply, NewState :: state()}.
dispatch_call({subscribe_to_events, PidOrSubscribers}, _From, State0) ->
    subscribe_to_events_impl(PidOrSubscribers, State0);
dispatch_call({remove_event_subscription, Subscription}, _From, State0) ->
    remove_event_subscription_impl(Subscription, State0);
dispatch_call({send_sync_event, Subscription}, _From, State0) ->
    send_sync_event_impl(Subscription, State0);
dispatch_call({add_breakpoint, Module, Line}, _From, State0) ->
    add_breakpoint_impl(Module, Line, State0);
dispatch_call({clear_breakpoints, Module}, _From, State0) ->
    clear_breakpoints_impl(Module, State0);
dispatch_call({clear_breakpoint, Module, Line}, _From, State0) ->
    clear_breakpoint_impl(Module, Line, State0);
dispatch_call({set_breakpoints, Module, Lines}, _From, State0) ->
    set_breakpoints_impl(Module, Lines, State0);
dispatch_call(get_breakpoints, _From, State0) ->
    get_breakpoints_impl(State0);
dispatch_call({get_breakpoints, Module}, _From, State0) ->
    get_breakpoints_impl(Module, State0);
dispatch_call(get_breakpoints_hit, _From, State) ->
    get_breakpoints_hit_impl(State);
dispatch_call({reapply_breakpoints, Module}, _From, State) ->
    reapply_breakpoints_impl(Module, State);
dispatch_call({add_module_substitute, Module, Substitute, AddedFrames}, _From, State0) ->
    add_module_substitute_impl(Module, Substitute, AddedFrames, State0);
dispatch_call({remove_module_substitute, X}, _From, State0) ->
    remove_module_substitute_impl(X, State0);
dispatch_call(pause, _From, State0) ->
    pause_impl(State0);
dispatch_call(continue, _From, State0) ->
    continue_impl(State0);
dispatch_call({process_info, Pid, RequestedFields}, _From, State0) ->
    process_info_impl(Pid, RequestedFields, State0);
dispatch_call({processes, RequestedFields}, _From, State0) ->
    processes_impl(RequestedFields, State0);
dispatch_call({excluded_processes, RequestedFields}, _From, State0) ->
    excluded_processes_impl(RequestedFields, State0);
dispatch_call({exclude_processes, Specs}, _From, State0) ->
    exclude_processes_impl(Specs, State0);
dispatch_call(is_paused, _From, State0) ->
    is_paused_impl(State0);
dispatch_call({unexclude_processes, Specs}, _From, State0) ->
    unexclude_processes_impl(Specs, State0);
dispatch_call({stack_frames, Pid}, _From, State0) ->
    stack_frames_impl(Pid, State0);
dispatch_call({stack_frame_vars, Pid, FrameId, MaxTermSize}, _From, State0) ->
    stack_frame_vars_impl(Pid, FrameId, MaxTermSize, State0);
dispatch_call({step_over, Pid}, _From, State0) ->
    step_impl(fun(Breakpoints) -> edb_server_break:prepare_for_stepping(step_over, Pid, Breakpoints) end, State0);
dispatch_call({step_out, Pid}, _From, State0) ->
    step_impl(fun(Breakpoints) -> edb_server_break:prepare_for_stepping(step_out, Pid, Breakpoints) end, State0);
dispatch_call({step_in, Pid}, _From, State0) ->
    step_impl(fun(Breakpoints) -> edb_server_break:prepare_for_stepping_in(Pid, Breakpoints) end, State0);
dispatch_call({eval, Opts = #{}}, {CallerPid, _}, State0) ->
    eval_impl(Opts, CallerPid, State0).

-spec handle_info(Info, State :: state()) -> {noreply, state()} when
    Info :: erl_debugger:event_message() | {'DOWN', reference(), process, pid(), term()}.
handle_info({debugger_event, S, Event}, State0 = #state{debugger_session = S}) ->
    {ok, State1} = handle_debugger_event(Event, State0),
    {noreply, State1};
handle_info({'DOWN', MonitorRef, process, _Pid, _Info}, State0) ->
    Subs0 = State0#state.event_subscribers,
    Subs1 = edb_events:process_down(MonitorRef, Subs0),
    State1 = State0#state{event_subscribers = Subs1},
    {noreply, State1};
handle_info(_E, State0) ->
    {noreply, State0}.

%%--------------------------------------------------------------------
%% Debugger events
%%--------------------------------------------------------------------

-spec handle_debugger_event(Event, state()) -> {ok, state()} when
    Event :: erl_debugger:event().
handle_debugger_event({breakpoint, Pid, MFA, Line, Resume}, State0) ->
    breakpoint_event_impl(Pid, MFA, Line, Resume, State0).

-spec breakpoint_event_impl(Pid, MFA, Line, Resume, State0) -> {ok, State1} when
    Pid :: pid(),
    MFA :: mfa(),
    Line :: line(),
    Resume :: fun(() -> ok),
    State0 :: state(),
    State1 :: state().
breakpoint_event_impl(Pid, MFA = {Module, _, _}, Line, Resume, State0) ->
    Universe = erlang:processes(),
    UnsuspendablePids = get_excluded_processes(Universe, State0),

    State3 =
        case edb_server_sets:is_element(Pid, UnsuspendablePids) of
            true ->
                ok = Resume(),
                State0;
            false ->
                #state{breakpoints = BP0} = State0,
                VmModule = to_vm_module(Module, State0),
                case edb_server_break:register_breakpoint_event(VmModule, Line, Pid, Resume, BP0) of
                    resume ->
                        ok = Resume(),
                        State0;
                    {suspend, Reason, BP1} ->
                        State1 = State0#state{breakpoints = BP1},
                        {ok, State2} = suspend_all_processes(Universe, UnsuspendablePids, State1),
                        PausedEvent =
                            case Reason of
                                explicit ->
                                    {breakpoint, Pid, MFA, {line, Line}};
                                step ->
                                    % Pid was already suspended when processing the step breakpoint, so
                                    % resume it here to balance the suspension count. Notice the process will
                                    % remain suspended, resume_process here is cheap as it is just decreasing
                                    % a counter.
                                    edb_server_process:try_resume_process(Pid),
                                    {step, Pid}
                            end,
                        ok = edb_events:broadcast(
                            {paused, PausedEvent},
                            State2#state.event_subscribers
                        ),
                        State2
                end
        end,

    {ok, State3}.

%%--------------------------------------------------------------------
%% handle_call implementations
%%--------------------------------------------------------------------

-spec subscribe_to_events_impl(PidOrSubscribers, State0) -> {reply, ok | {ok, Subscription}, State1} when
    PidOrSubscribers :: pid() | #{edb_events:subscription() => pid()},
    State0 :: state(),
    Subscription :: edb_events:subscription(),
    State1 :: state().
subscribe_to_events_impl(Pid, State0 = #state{event_subscribers = Subs0}) when is_pid(Pid) ->
    MonitorRef = erlang:monitor(process, Pid),
    {ok, {Subscription, Subs1}} = edb_events:subscribe(Pid, MonitorRef, Subs0),
    State1 = State0#state{event_subscribers = Subs1},
    {reply, {ok, Subscription}, State1};
subscribe_to_events_impl(Subscribers, State0 = #state{event_subscribers = Subs0}) when is_map(Subscribers) ->
    SubscribersWithRefs = [{Sub, Pid, erlang:monitor(process, Pid)} || Sub := Pid <- Subscribers],
    {ok, Subs1} = lists:foldl(
        fun({Sub, Pid, Ref}, {ok, SubsN}) ->
            edb_events:subscribe(Sub, Pid, Ref, SubsN)
        end,
        {ok, Subs0},
        SubscribersWithRefs
    ),
    State1 = State0#state{event_subscribers = Subs1},
    {reply, ok, State1}.

-spec remove_event_subscription_impl(Subscription, State0) -> {reply, ok, State1} when
    Subscription :: edb_events:subscription(),
    State0 :: state(),
    State1 :: state().
remove_event_subscription_impl(Subscription, State0 = #state{event_subscribers = Subs0}) ->
    State1 =
        case edb_events:send_to(Subscription, unsubscribed, Subs0) of
            undefined ->
                State0;
            ok ->
                case edb_events:unsubscribe(Subscription, Subs0) of
                    not_subscribed ->
                        State0;
                    {ok, {MonitorRef, Subs1}} ->
                        erlang:demonitor(MonitorRef, [flush]),
                        State0#state{event_subscribers = Subs1}
                end
        end,
    {reply, ok, State1}.

-spec send_sync_event_impl(Subscription, State0) -> {reply, Reply, State1} when
    Subscription :: edb_events:subscription(),
    State0 :: state(),
    Reply :: {ok, reference()} | {error, unknown_subscription},
    State1 :: state().
send_sync_event_impl(Subscription, State) ->
    SyncRef = erlang:make_ref(),
    Reply =
        case edb_events:send_to(Subscription, {sync, SyncRef}, State#state.event_subscribers) of
            undefined ->
                {error, unknown_subscription};
            ok ->
                {ok, SyncRef}
        end,
    {reply, Reply, State}.

-spec add_breakpoint_impl(Module, Line, State0) -> {reply, ok | {error, Reason}, State1} when
    Module :: module(),
    Line :: line(),
    Reason :: edb:add_breakpoint_error(),
    State0 :: state(),
    State1 :: state().
add_breakpoint_impl(Module, Line, State0) ->
    #state{breakpoints = Breakpoints0} = State0,
    VmModule = to_vm_module(Module, State0),
    case edb_server_break:add_explicit(VmModule, Line, Breakpoints0) of
        {ok, Breakpoints1} ->
            State1 = State0#state{breakpoints = Breakpoints1},
            {reply, ok, State1};
        {error, Reason} ->
            {reply, {error, Reason}, State0}
    end.

-spec clear_breakpoints_impl(Module, State0) -> {reply, ok, State1} when
    Module :: module(),
    State0 :: state(),
    State1 :: state().
clear_breakpoints_impl(Module, State0) ->
    #state{breakpoints = Breakpoints0} = State0,
    VmModule = to_vm_module(Module, State0),
    {ok, Breakpoints1} = edb_server_break:clear_explicits(VmModule, Breakpoints0),
    State1 = State0#state{breakpoints = Breakpoints1},
    {reply, ok, State1}.

-spec clear_breakpoint_impl(Module, Line, State0) -> {reply, ok | {error, not_found}, State1} when
    Module :: module(),
    Line :: line(),
    State0 :: state(),
    State1 :: state().
clear_breakpoint_impl(Module, Line, State0) ->
    #state{breakpoints = Breakpoints0} = State0,
    VmModule = to_vm_module(Module, State0),
    case edb_server_break:clear_explicit(VmModule, Line, Breakpoints0) of
        {ok, _, Breakpoints1} ->
            %% We don't do anything particular yet if the breakpoint vanished from the VM
            State1 = State0#state{breakpoints = Breakpoints1},
            {reply, ok, State1};
        {error, Reason} ->
            {reply, {error, Reason}, State0}
    end.

-spec set_breakpoints_impl(Module, Lines, State0) -> {reply, Result, State1} when
    Module :: module(),
    Lines :: [line()],
    State0 :: state(),
    State1 :: state(),
    Result :: edb:set_breakpoints_result().
set_breakpoints_impl(Module, Lines, State0) ->
    #state{breakpoints = Breakpoints0} = State0,
    VmModule = to_vm_module(Module, State0),
    {ok, Breakpoints1} = edb_server_break:clear_explicits(VmModule, Breakpoints0),
    {LineResults, Breakpoints2} = edb_server_break:add_explicits(VmModule, Lines, Breakpoints1),
    State2 = State0#state{breakpoints = Breakpoints2},
    {reply, LineResults, State2}.

-spec get_breakpoints_impl(state()) -> {reply, #{module() => [edb:breakpoint_info()]}, state()}.
get_breakpoints_impl(State0) ->
    BPSet = get_breakpoints(State0),
    Result =
        #{
            Module => [#{module => Module, line => Line} || Line := [] <- Lines]
         || VmModule := Lines <- BPSet,
            Module <- [from_vm_module(VmModule, State0)]
        },
    {reply, Result, State0}.

-spec get_breakpoints_impl(module(), state()) -> {reply, [edb:breakpoint_info()], state()}.
get_breakpoints_impl(Module, State0) ->
    BPSet = get_breakpoints(State0),
    Lines = maps:get(to_vm_module(Module, State0), BPSet, #{}),
    BPInfoList = [#{module => Module, line => Line} || Line := [] <- Lines],
    {reply, BPInfoList, State0}.

-spec get_breakpoints_hit_impl(State0 :: state()) -> {reply, BreakpointsHit, State1 :: state()} when
    BreakpointsHit :: #{pid() => #{module := module(), line := line()}}.
get_breakpoints_hit_impl(State0) ->
    #state{breakpoints = Breakpoints0} = State0,
    VmBreakpointsHit = edb_server_break:get_explicits_hit(Breakpoints0),
    BreakpointsHit = maps:map(
        fun(_Pid, #{line := Line, module := VmModule}) ->
            #{line => Line, module => from_vm_module(VmModule, State0)}
        end,
        VmBreakpointsHit
    ),
    {reply, BreakpointsHit, State0}.

-spec reapply_breakpoints_impl(module(), State0 :: state()) ->
    {reply, ok | {error, Reason}, State1 :: state()}
when
    Reason :: edb:add_breakpoint_error().
reapply_breakpoints_impl(Module, State0) ->
    #state{breakpoints = Breakpoints0} = State0,
    VmModule = to_vm_module(Module, State0),
    Result = edb_server_break:reapply_breakpoints(VmModule, Breakpoints0),
    {reply, Result, State0}.

-spec add_module_substitute_impl(Module :: module(), Substitute :: module(), AddedFrames :: [mfa()], State0 :: state()) ->
    {reply, ok | {error, add_substitute_error()}, State1 :: state()}.
add_module_substitute_impl(Module, Substitute, AddedFrames, State0) ->
    #state{breakpoints = Breakpoints0} = State0,
    case edb_server_break:add_module_substitute(Module, Substitute, AddedFrames, Breakpoints0) of
        {ok, Breakpoints1} ->
            State1 = State0#state{breakpoints = Breakpoints1},
            {reply, ok, State1};
        Error ->
            {reply, Error, State0}
    end.

-spec remove_module_substitute_impl(SubstituteModule :: module(), State0 :: state()) ->
    {reply, ok | {error, remove_substitute_error()}, State1 :: state()}.
remove_module_substitute_impl(SubstituteModule, State0) ->
    #state{breakpoints = Breakpoints0} = State0,
    case edb_server_break:remove_module_substitute(SubstituteModule, Breakpoints0) of
        {ok, Breakpoints1} ->
            State1 = State0#state{breakpoints = Breakpoints1},
            {reply, ok, State1};
        Error ->
            {reply, Error, State0}
    end.

-spec pause_impl(State0 :: state()) -> {reply, ok, State1 :: state()}.
pause_impl(State0) ->
    State2 =
        case is_paused(State0) of
            true ->
                State0;
            false ->
                Universe = erlang:processes(),
                UnsuspendablePids = get_excluded_processes(Universe, State0),
                {ok, State1} = suspend_all_processes(Universe, UnsuspendablePids, State0),
                ok = edb_events:broadcast({paused, pause}, State0#state.event_subscribers),
                State1
        end,
    {reply, ok, State2}.

-spec continue_impl(State0 :: state()) -> {reply, Result, State1 :: state()} when
    Result :: {ok, resumed | not_paused}.
continue_impl(State0) ->
    {ok, ActuallyResumed, State1} = resume_processes(all, continue, State0),
    Result =
        case maps:size(ActuallyResumed) > 0 of
            true -> resumed;
            false -> not_paused
        end,
    {reply, {ok, Result}, State1}.

-spec step_impl(PrepareStepBreakpoints, State0) -> {reply, ok | {error, Reason}, State1} when
    PrepareStepBreakpoints :: fun((Breakpoints0) -> {ok, Breakpoints1} | {error, Reason}),
    Breakpoints0 :: edb_server_break:breakpoints(),
    Breakpoints1 :: edb_server_break:breakpoints(),
    State0 :: state(),
    State1 :: state().
step_impl(PrepareStepBreakpoints, State0) ->
    #state{breakpoints = Breakpoints0} = State0,
    case PrepareStepBreakpoints(Breakpoints0) of
        {ok, Breakpoints1} ->
            State1 = State0#state{breakpoints = Breakpoints1},
            {ok, _, State2} = resume_processes(all, continue, State1),
            {reply, ok, State2};
        {error, _} = Error ->
            {reply, Error, State0}
    end.

-spec process_info_impl(Pid, RequestedFields, State0) -> {reply, Result, State1} when
    Pid :: pid(),
    RequestedFields :: [edb:process_info_field()],
    State0 :: state(),
    State1 :: state(),
    Result :: {ok, edb:process_info()} | undefined.
process_info_impl(Pid, RequestedFields, State0) ->
    Status = process_status(Pid, State0),
    Result =
        case edb_server_process:processes_info(#{Pid => Status}, RequestedFields) of
            #{Pid := Info} -> {ok, Info};
            _ -> undefined
        end,
    {reply, Result, State0}.

-spec processes_impl(RequestedFields, State0) -> {reply, Result, State1} when
    RequestedFields :: [edb:process_info_field()],
    State0 :: state(),
    State1 :: state(),
    Result :: #{pid() => edb:process_info()}.
processes_impl(RequestedFields, State0) ->
    Universe = erlang:processes(),
    Excluded = get_excluded_processes(Universe, State0),

    Procs =
        #{
            Pid => process_status(Pid, State0)
         || Pid <- Universe, not maps:is_key(Pid, Excluded)
        },
    Result = edb_server_process:processes_info(Procs, RequestedFields),
    {reply, Result, State0}.

-spec is_paused_impl(State0) -> {reply, Result, State1} when
    State0 :: state(),
    State1 :: state(),
    Result :: boolean().
is_paused_impl(State0) ->
    {reply, is_paused(State0), State0}.

-spec excluded_processes_impl(RequestedFields, State0) -> {reply, #{pid() => edb:process_info()}, State1} when
    RequestedFields :: [edb:process_info_field()],
    State0 :: state(),
    State1 :: state().
excluded_processes_impl(RequestedFields, State0) ->
    Universe = erlang:processes(),
    Excluded = get_excluded_processes(Universe, State0),
    Result = edb_server_process:excluded_processes_info(Excluded, RequestedFields),
    {reply, Result, State0}.

-spec excluded_sys_processes(Universe :: [pid()], state()) -> set(pid()).
excluded_sys_processes(Universe, State0) ->
    #state{do_suspend_pids = DoSuspendPids} = State0,
    SysProcNames = [
        application_controller,
        erl_prim_loader,
        erts_code_purger,
        init,
        logger
    ],
    NamedSysProcs =
        #{
            Pid => []
         || N <- SysProcNames,
            Pid <- [erlang:whereis(N)],
            Pid /= undefined,
            is_pid(Pid),
            not edb_server_sets:is_element(Pid, DoSuspendPids)
        },
    InternalSysProcs = #{Pid => [] || Pid <- Universe, erts_internal:is_system_process(Pid)},
    edb_server_sets:union(NamedSysProcs, InternalSysProcs).

-spec excluded_debugger_processes(state()) -> set(pid()).
excluded_debugger_processes(State) ->
    #state{
        do_suspend_pids = DoSuspendPids,
        event_subscribers = Subscribers
    } = State,
    SubscribedPids =
        #{
            Pid => []
         || Pid <- edb_events:subscriber_pids(Subscribers),
            not edb_server_sets:is_element(Pid, DoSuspendPids)
        },
    AllDebuggerPids = SubscribedPids#{self() => []},
    AllDebuggerPids.

-spec excluded_processes_by_regname(state()) -> set(pid()).
excluded_processes_by_regname(State) ->
    #state{do_not_suspend_regnames = DoNotSuspendRegNames} = State,
    excluded_processes_by_regname(DoNotSuspendRegNames, State).

-spec excluded_processes_by_regname(RegNameSet, state()) -> set(pid()) when
    RegNameSet :: set(atom()).
excluded_processes_by_regname(RegNameSet, State) ->
    #state{do_suspend_pids = DoSuspendPids} = State,
    #{
        Pid => []
     || Name := [] <- RegNameSet,
        Pid <- [erlang:whereis(Name)],
        not edb_server_sets:is_element(Pid, DoSuspendPids),
        is_pid(Pid),
        Pid /= undefined
    }.

-spec excluded_processes_by_app(Universe :: [pid()], state()) -> set(pid()).
excluded_processes_by_app(Universe, State) ->
    #state{do_not_suspend_apps = DoNotSuspendApps} = State,
    excluded_processes_by_app(DoNotSuspendApps, Universe, State).

-spec excluded_processes_by_app(AppSet, Universe, state()) -> set(pid()) when
    AppSet :: set(atom()),
    Universe :: [pid()].
excluded_processes_by_app(AppSet, Universe, State) ->
    #state{do_suspend_pids = DoSuspendPids} = State,
    case map_size(AppSet) == 0 of
        true ->
            #{};
        false ->
            ApplicationMasterPids =
                #{
                    GlPid => []
                 || App := _ <- AppSet,
                    {_App, GlPid} <- ets:lookup(ac_tab, {application_master, App})
                },
            #{
                P => []
             || P <- Universe,
                not edb_server_sets:is_element(P, DoSuspendPids),
                {group_leader, GL} <- group_leader(P),
                edb_server_sets:is_element(GL, ApplicationMasterPids)
            }
    end.

-spec group_leader(pid()) -> [{group_leader, pid()}].
group_leader(Pid) ->
    case erlang:process_info(Pid, [group_leader]) of
        undefined ->
            [];
        [{group_leader, GL}] ->
            [{group_leader, GL}]
    end.

-spec exclude_processes_impl(Specs, State0) -> {reply, ok, State1} when
    State0 :: state(),
    State1 :: state(),
    Specs :: [procs_spec()].
exclude_processes_impl(Specs, State0) ->
    ExcludedByPid = #{P => [] || {proc, P} <- Specs, is_pid(P), is_relevant_pid(P)},
    ExcludedRegNames = #{Name => [] || {proc, Name} <- Specs, is_atom(Name)},
    ExcludedApps = #{App => [] || {application, App} <- Specs},
    ExceptedFromExclude = #{P => [] || {except, P} <- Specs, is_relevant_pid(P)},

    #state{
        do_not_suspend_apps = DoNotSuspendApps0,
        do_not_suspend_pids = DoNotSuspendPids0,
        do_not_suspend_regnames = DoNotSuspendRegNames0,
        do_suspend_pids = DoSuspend0
    } = State0,
    State1 = State0#state{
        do_not_suspend_apps = edb_server_sets:union(DoNotSuspendApps0, ExcludedApps),
        do_not_suspend_pids = edb_server_sets:union(DoNotSuspendPids0, ExcludedByPid),
        do_not_suspend_regnames = edb_server_sets:union(DoNotSuspendRegNames0, ExcludedRegNames),
        do_suspend_pids = edb_server_sets:union(DoSuspend0, ExceptedFromExclude)
    },

    Universe = erlang:processes(),

    State4 =
        case State1#state.suspended_procs of
            SuspendedProcs when map_size(SuspendedProcs) =:= 0 ->
                State1;
            _ ->
                PidsExcludedByRegName = excluded_processes_by_regname(ExcludedRegNames, State1),
                PidsExcludedByApp = excluded_processes_by_app(ExcludedApps, Universe, State1),
                NewlyExcludedProcs = edb_server_sets:union([
                    ExcludedByPid, PidsExcludedByRegName, PidsExcludedByApp
                ]),

                {ok, _ActuallyResumed, State2} = resume_processes(NewlyExcludedProcs, excluded, State1),
                UnsuspendablePids = get_excluded_processes(Universe, State2),
                {ok, State3} = suspend_all_processes(Universe, UnsuspendablePids, State2),
                State3
        end,

    {reply, ok, State4}.

-spec unexclude_processes_impl(Specs, State0) -> {reply, ok, State1} when
    State0 :: state(),
    State1 :: state(),
    Specs :: [procs_spec()].
unexclude_processes_impl(Specs, State0) ->
    UnexcludedByPid = #{P => [] || {proc, P} <- Specs, is_pid(P), is_relevant_pid(P)},
    UnexcludedRegNames = #{Name => [] || {proc, Name} <- Specs, is_atom(Name)},
    UnexcludedApps = #{App => [] || {application, App} <- Specs},
    UnexceptedFromExclude = #{P => [] || {except, P} <- Specs, is_relevant_pid(P)},

    #state{
        do_not_suspend_apps = DoNotSuspendApps0,
        do_not_suspend_pids = DoNotSuspend0,
        do_not_suspend_regnames = DoNotSuspendRegNames0,
        do_suspend_pids = DoSuspend0
    } = State0,

    State1 = State0#state{
        do_not_suspend_apps = edb_server_sets:subtract(DoNotSuspendApps0, UnexcludedApps),
        do_not_suspend_pids = edb_server_sets:subtract(DoNotSuspend0, UnexcludedByPid),
        do_not_suspend_regnames = edb_server_sets:subtract(DoNotSuspendRegNames0, UnexcludedRegNames),
        do_suspend_pids = edb_server_sets:subtract(DoSuspend0, UnexceptedFromExclude)
    },

    Universe = erlang:processes(),

    State4 =
        case State1#state.suspended_procs of
            SuspendedProcs when map_size(SuspendedProcs) =:= 0 ->
                State1;
            _ ->
                UnsuspendablePids = get_excluded_processes(Universe, State1),
                NewlyExcludedProcs = edb_server_sets:intersection(UnexceptedFromExclude, UnsuspendablePids),
                {ok, _ActuallyResumed, State2} = resume_processes(NewlyExcludedProcs, excluded, State1),
                {ok, State3} = suspend_all_processes(Universe, UnsuspendablePids, State2),
                State3
        end,

    {reply, ok, State4}.

-spec stack_frames_impl(Pid, State0) -> {reply, Response, State1} when
    Pid :: pid(),
    State0 :: state(),
    State1 :: state(),
    Response :: not_paused | {ok, [edb:stack_frame()]}.
stack_frames_impl(Pid, State0) ->
    case edb_server_stack_frames:raw_user_stack_frames(Pid) of
        not_paused ->
            {reply, not_paused, State0};
        RawFrames ->
            #state{breakpoints = Breakpoints0} = State0,
            RelevantFrames = edb_server_stack_frames:without_bottom_terminator_frame(RawFrames),
            Result = [format_frame(RawFrame, Breakpoints0) || RawFrame <- RelevantFrames],
            {reply, {ok, Result}, State0}
    end.

-spec format_frame(RawFrame :: erl_debugger:stack_frame(), edb_server_break:breakpoints()) -> edb:stack_frame().
format_frame({FrameNo, 'unknown function', _}, _) ->
    #{
        id => FrameNo,
        mfa => unknown,
        source => undefined,
        line => undefined
    };
format_frame({FrameNo, #{function := {M, F, A}, line := Line}, _}, Breakpoints) ->
    VmModule = {vm_module, M},
    OriginalModule = edb_server_break:from_vm_module(VmModule, Breakpoints),
    #{
        id => FrameNo,
        mfa => {OriginalModule, F, A},
        % TODO(T204197553) take md5 sum into account once it is available in the raw frame
        source => edb_server_break:get_vm_module_source(VmModule, Breakpoints),
        line => Line
    }.

-spec stack_frame_vars_impl(Pid, FrameId, MaxTermSize, State0) -> {reply, Response, State1} when
    Pid :: pid(),
    FrameId :: edb:frame_id(),
    MaxTermSize :: non_neg_integer(),
    Result :: edb:stack_frame_vars(),
    Response :: not_paused | undefined | {ok, Result},
    State0 :: state(),
    State1 :: state().
stack_frame_vars_impl(Pid, FrameId, MaxTermSize, State0) ->
    Result = get_stack_frame_vars(Pid, FrameId, MaxTermSize, State0),
    {reply, Result, State0}.

-spec get_stack_frame_vars(Pid, FrameId, MaxTermSize, State) -> not_paused | undefined | {ok, Result} when
    Pid :: pid(),
    FrameId :: edb:frame_id(),
    MaxTermSize :: non_neg_integer(),
    Result :: edb:stack_frame_vars(),
    State :: state().
get_stack_frame_vars(Pid, FrameId, MaxTermSize, State) ->
    case edb_server_stack_frames:raw_stack_frames(Pid) of
        not_paused ->
            not_paused;
        RawFrames ->
            ResolveLocalVars =
                case edb_server_stack_frames:user_frames_only(RawFrames) of
                    [{TopFrameId, _, _} | _] when FrameId =:= TopFrameId ->
                        edb_server_break:is_process_trapped(Pid, State#state.breakpoints);
                    _ ->
                        false
                end,
            edb_server_stack_frames:stack_frame_vars(Pid, FrameId, MaxTermSize, RawFrames, #{
                resolve_local_vars => ResolveLocalVars
            })
    end.

-spec eval_impl(Opts, CallerPid, State0) -> {reply, Response, State1} when
    Opts :: eval_opts(Result),
    CallerPid :: pid(),
    Response :: not_paused | undefined | {ok, Result} | {eval_error, edb:eval_error()},
    State0 :: state(),
    State1 :: state().
eval_impl(Opts, CallerPid, State0) ->
    #{pid := Pid, frame_id := FrameId, max_term_size := MaxTermSize, dependencies := Deps} = Opts,
    Result =
        case get_stack_frame_vars(Pid, FrameId, MaxTermSize, State0) of
            {ok, StackFrameVars} ->
                #{function := F, timeout := Timeout} = Opts,
                case edb_server_eval:eval(F, StackFrameVars, node(CallerPid), Timeout, Deps) of
                    {failed_to_load_module, _, _} = LoadFailure ->
                        ?MODULE:raise(error, LoadFailure);
                    EvalResult ->
                        EvalResult
                end;
            NotOk ->
                NotOk
        end,
    {reply, Result, State0}.

%%--------------------------------------------------------------------
%% State helpers
%%--------------------------------------------------------------------

-spec is_paused(State) -> boolean() when State :: state().
is_paused(State) ->
    #state{suspended_procs = Procs} = State,
    HasAPausedProcess = maps:size(Procs) =/= 0,
    HasAPausedProcess.

-spec get_breakpoints(State0) -> #{edb_server_break:vm_module() => #{line() => []}} when State0 :: state().
get_breakpoints(State0) ->
    #state{breakpoints = Breakpoints} = State0,
    edb_server_break:get_explicits(Breakpoints).

-spec resume_processes(Targets, Reason, State0) -> {ok, ActuallyResumed, State1} when
    Targets :: set(pid()) | all,
    Reason :: continue | excluded | termination,
    ActuallyResumed :: set(pid()),
    State0 :: state(),
    State1 :: state().
resume_processes(Targets, Reason, State0) ->
    #state{
        suspended_procs = Suspended0,
        breakpoints = BP0
    } = State0,

    {ToResume, Suspended1, BP1} =
        case Targets of
            all ->
                {Suspended0, #{}, edb_server_break:resume_processes(all, BP0)};
            Requested when is_map(Requested) ->
                NeedToBeResumed = edb_server_sets:intersection(Requested, Suspended0),
                RemainingSuspended = edb_server_sets:subtract(Suspended0, NeedToBeResumed),
                RemainingBP = edb_server_break:resume_processes(NeedToBeResumed, BP0),
                {NeedToBeResumed, RemainingSuspended, RemainingBP}
        end,

    ActuallyResumed = #{Pid => [] || Pid := [] <- ToResume, edb_server_process:try_resume_process(Pid)},

    State1 = State0#state{
        suspended_procs = Suspended1,
        breakpoints = BP1
    },

    Subs = State1#state.event_subscribers,
    case Targets of
        _ when map_size(ActuallyResumed) =:= 0 ->
            ok;
        all when Reason =:= continue; Reason =:= termination ->
            ok = edb_events:broadcast({resumed, {Reason, all}}, Subs);
        _ when Reason =:= excluded ->
            ok = edb_events:broadcast({resumed, {Reason, ActuallyResumed}}, Subs)
    end,

    {ok, ActuallyResumed, State1}.

-spec suspend_all_processes(Universe, Unsuspendable, State0) -> {ok, State1} when
    Universe :: [pid()],
    Unsuspendable :: set(pid()),
    State0 :: state(),
    State1 :: state().
suspend_all_processes(Universe, Unsuspendable, State0) ->
    #state{suspended_procs = AlreadySuspended} = State0,
    MustIgnore = fun(Pid) ->
        edb_server_sets:is_element(Pid, AlreadySuspended) orelse edb_server_sets:is_element(Pid, Unsuspendable)
    end,

    JustSuspended =
        #{
            Pid => []
         || Pid <- Universe,
            not MustIgnore(Pid),
            edb_server_process:try_suspend_process(Pid)
        },
    AllSuspended = maps:merge(AlreadySuspended, JustSuspended),
    State1 = State0#state{suspended_procs = AllSuspended},
    {ok, State1}.

-spec get_excluded_processes(Universe, State) -> #{pid() => [edb:exclusion_reason()]} when
    Universe :: [pid()],
    State :: state().
get_excluded_processes(Universe, State) ->
    #state{do_not_suspend_pids = DoNotSuspendPids} = State,

    ExcludedSysProcs = edb_server_sets:to_map(excluded_sys_processes(Universe, State), [system_component]),
    ExcludedByDebugger = edb_server_sets:to_map(excluded_debugger_processes(State), [debugger_component]),
    ExcludedByPid = edb_server_sets:to_map(DoNotSuspendPids, [excluded_pid]),
    ExcludedByName = edb_server_sets:to_map(excluded_processes_by_regname(State), [excluded_regname]),
    ExcludedByApps = edb_server_sets:to_map(excluded_processes_by_app(Universe, State), [excluded_application]),

    ExcludedCombined = lists:foldl(
        fun(MapL, MapR) ->
            maps:merge_with(fun(_, L, R) -> lists:merge(L, R) end, MapL, MapR)
        end,
        #{},
        [ExcludedSysProcs, ExcludedByDebugger, ExcludedByPid, ExcludedByName, ExcludedByApps]
    ),
    ExcludedCombined.

-spec process_status(Pid, State) -> running | paused | {breakpoint, edb:breakpoint_info()} when
    Pid :: pid(),
    State :: state().
process_status(Pid, State) ->
    #state{suspended_procs = SuspendedProcs} = State,

    case is_map_key(Pid, SuspendedProcs) of
        false ->
            running;
        true ->
            #state{breakpoints = BP} = State,
            case edb_server_break:get_explicit_hit(Pid, BP) of
                no_breakpoint_hit ->
                    paused;
                {ok, #{module := VmModule, line := Line}} ->
                    {breakpoint, #{module => from_vm_module(VmModule, State), line => Line}}
            end
    end.

%%--------------------------------------------------------------------
%% Process helpers
%%--------------------------------------------------------------------

-spec is_relevant_pid(Pid :: pid()) -> boolean().
is_relevant_pid(Pid) ->
    ?is_internal_pid(Pid) andalso is_process_alive(Pid).
