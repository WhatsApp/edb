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

-module(edb_server_break).

% Creation
-export([create/0]).

% User-brekapoints manipulation
-export([add_user_breakpoint/2, add_user_breakpoints/2]).
-export([get_user_breakpoints/1, get_user_breakpoints/2]).
-export([clear_user_breakpoint/2, clear_user_breakpoints/2]).
-export([get_user_breakpoints_hit/1, get_user_breakpoint_hit/2]).
-export([reapply_breakpoints/2]).

% Stepping
-export([prepare_for_stepping/3]).
-export([prepare_for_stepping_in/2]).

% Execution control
-export([is_process_trapped/2]).
-export([register_breakpoint_event/5]).
-export([resume_processes/2]).

% Module substitutes
-export([add_module_substitute/4, remove_module_substitute/2]).
-export([to_vm_module/2, from_vm_module/2]).
-export([get_vm_module_source/2]).

-compile(warn_missing_spec_all).

%% --------------------------------------------------------------------
%% Types
%% --------------------------------------------------------------------

-type line() :: edb:line().
-type vm_module() :: {vm_module, module()}.
-type substitute_info() :: #{
    substitute => vm_module(),
    added_frames => [mfa()],
    original_sources => file:filename() | undefined
}.
-type further_substitute_info() :: #{
    substitute => vm_module(),
    added_frames => [mfa()]
}.

-export_type([breakpoints/0, vm_module/0]).
-record(breakpoints, {
    %% TODO(T198738599): we should somehow keep track of the identity
    %% of the module instance on which the breakpoint
    %% was set? The general problem is that right now when
    %% a module is reloaded, breakpoints remain on the old
    %% version of the code (until purged) and will not exist
    %% on the new version (lines could have changed, so seems
    %% right). We need some way to be aware/handle this.

    %% Internal breakpoints set by the server to step through, grouped by pid.
    %% For each such breakpoint, there are only certain call-stacks under which
    %% we want to suspend the process.
    steps :: #{pid() => #{vm_module() => #{line() => #{call_stack_pattern() => []}}}},

    %% User-breakpoints that have been hit
    user_bps_hit :: #{pid() => #{type := line, module := vm_module(), line := line()}},

    %% Callbacks to resume processes that hit a VM breakpoint
    resume_actions :: #{pid() => fun(() -> ok)},

    %% Sets of reasons why VM breakpoints were set on each locations
    vm_breakpoints :: #{vm_module() => #{line() => #{vm_breakpoint_reason() => []}}},

    substituted_modules :: #{module() => substitute_info()},

    further_substituted_modules :: #{vm_module() => further_substitute_info()},

    % The inverse of `substituted_modules` and `further_substituted_modules`
    substituted_modules_reverse :: #{vm_module() => module() | vm_module()}
}).

-type vm_breakpoint_reason() ::
    user_breakpoint
    | {step, pid()}.

-opaque breakpoints() :: #breakpoints{}.

%% --------------------------------------------------------------------
%% Creation
%% --------------------------------------------------------------------

-spec create() -> breakpoints().
create() ->
    #breakpoints{
        steps = #{},
        user_bps_hit = #{},
        resume_actions = #{},
        vm_breakpoints = #{},
        substituted_modules = #{},
        further_substituted_modules = #{},
        substituted_modules_reverse = #{}
    }.

%% --------------------------------------------------------------------
%% User breakpoints manipulation
%% --------------------------------------------------------------------
-spec add_user_breakpoint(BreakpointDescription, breakpoints()) ->
    {ok, breakpoints()} | {error, edb:add_breakpoint_error()}
when
    BreakpointDescription :: {vm_module(), line()}.
add_user_breakpoint({{vm_module, Module} = VmModule, Line}, Breakpoints0) ->
    case try_ensure_module_loaded(Module) of
        ok ->
            add_vm_breakpoint(VmModule, Line, user_breakpoint, Breakpoints0);
        {error, timeout} ->
            {error, timeout_loading_module};
        {error, _} ->
            {error, {badkey, Module}}
    end.

-spec add_user_breakpoints(BreakpointDescriptions, breakpoints()) -> {BreakpointResults, breakpoints()} when
    BreakpointDescriptions :: [BreakpointDescription],
    BreakpointDescription :: {vm_module(), line()},
    BreakpointResults :: [{BreakpointDescription, Result}],
    Result :: ok | {error, edb:add_breakpoint_error()}.
add_user_breakpoints(BreakpointDescriptions, Breakpoints0) ->
    lists:mapfoldl(
        fun(BreakpointDescription, AccBreakpointsIn) ->
            case add_user_breakpoint(BreakpointDescription, AccBreakpointsIn) of
                {ok, AccBreakpointsOut} -> {{BreakpointDescription, ok}, AccBreakpointsOut};
                {error, Error} -> {{BreakpointDescription, {error, Error}}, AccBreakpointsIn}
            end
        end,
        Breakpoints0,
        BreakpointDescriptions
    ).

-spec get_user_breakpoints(breakpoints()) -> #{vm_module() => #{line() => []}}.
get_user_breakpoints(Breakpoints) ->
    VmBreakpoints = Breakpoints#breakpoints.vm_breakpoints,
    #{VmMod => #{K => [] || K := #{user_breakpoint := []} <- Info} || VmMod := Info <- VmBreakpoints}.

-spec get_user_breakpoints(vm_module(), breakpoints()) -> #{line() => []}.
get_user_breakpoints(Module, Breakpoints) ->
    Info = maps:get(Module, Breakpoints#breakpoints.vm_breakpoints, #{}),
    #{K => [] || K := #{user_breakpoint := []} <- Info}.

-spec clear_user_breakpoint(LineBreakpoint, breakpoints()) ->
    {ok, removed | vanished, breakpoints()} | {error, not_found}
when
    LineBreakpoint :: {vm_module(), line()}.
clear_user_breakpoint({Module, Line}, Breakpoints0) ->
    case remove_vm_breakpoint(Module, Line, user_breakpoint, Breakpoints0) of
        {ok, DeletionResult, Breakpoints1} ->
            {ok, DeletionResult, Breakpoints1};
        {error, unknown_vm_breakpoint} ->
            {error, not_found}
    end.

-spec clear_user_breakpoints(vm_module(), breakpoints()) -> {ok, breakpoints()}.
clear_user_breakpoints(Module, Breakpoints0) ->
    Lines = maps:keys(get_user_breakpoints(Module, Breakpoints0)),
    Breakpoints1 = lists:foldl(
        fun(Line, AccBreakpointsIn) ->
            case clear_user_breakpoint({Module, Line}, AccBreakpointsIn) of
                {ok, _RemovedOrVanished, AccBreakpointsOut} -> AccBreakpointsOut;
                % A breakpoint line taken from the list cannot be not_found
                {error, not_found} -> edb_server:invariant_violation(unexpected_bp_not_found)
            end
        end,
        Breakpoints0,
        Lines
    ),
    {ok, Breakpoints1}.

-spec get_user_breakpoints_hit(breakpoints()) -> #{pid() => #{type := line, module := vm_module(), line := line()}}.
get_user_breakpoints_hit(#breakpoints{user_bps_hit = UserBpsHit}) ->
    UserBpsHit.

-spec get_user_breakpoint_hit(pid(), breakpoints()) ->
    {ok, #{type := line, module := vm_module(), line := line()}} | no_breakpoint_hit.
get_user_breakpoint_hit(Pid, #breakpoints{user_bps_hit = UserBpsHit}) ->
    case UserBpsHit of
        #{Pid := BpHit} ->
            {ok, BpHit};
        #{} ->
            no_breakpoint_hit
    end.

%% --------------------------------------------------------------------
%% Stepping
%% --------------------------------------------------------------------

-spec prepare_for_stepping(StepType, Pid, breakpoints()) -> {ok, breakpoints()} | {error, Error} when
    StepType :: step_over | step_out,
    Pid :: pid(),
    Error :: edb:step_error().
prepare_for_stepping(StepType, Pid, Breakpoints0) ->
    case edb_server_stack_frames:raw_user_stack_frames(Pid) of
        not_paused ->
            {error, not_paused};
        StackFrames when is_list(StackFrames) ->
            case StepType of
                step_over ->
                    RelevantFrames = StackFrames,
                    Types = [on_any_required, on_any | [on_exc_handler || _ <- tl(tl(RelevantFrames))]],
                    Addrs = call_stack_addrs(RelevantFrames),
                    add_steps_on_stack_frames(Pid, RelevantFrames, Addrs, Types, Breakpoints0);
                step_out ->
                    RelevantFrames = tl(StackFrames),
                    Types = [on_any_required | [on_exc_handler || _ <- tl(RelevantFrames)]],
                    Addrs = call_stack_addrs(RelevantFrames),
                    add_steps_on_stack_frames(Pid, RelevantFrames, Addrs, Types, Breakpoints0)
            end
    end.

-spec prepare_for_stepping_in(Pid, breakpoints()) -> {ok, breakpoints()} | {error, Error} when
    Pid :: pid(),
    Error :: edb:step_in_error().
prepare_for_stepping_in(Pid, Breakpoints0) ->
    case edb_server_stack_frames:raw_user_stack_frames(Pid) of
        not_paused ->
            {error, not_paused};
        [TopFrame | _] = StackFrames ->
            case get_targets_for_step_in(TopFrame) of
                {error, _} = Error ->
                    Error;
                {ok, TargetMFAs} ->
                    {_, #{function := CurrentMFA}, _} = TopFrame,
                    Addrs = call_stack_addrs(StackFrames),

                    AddStepsOnStepInTargetsResult = lists:foldl(
                        fun
                            (_TargetMFA, {{error, _}, _} = Error) ->
                                Error;
                            (TargetMFA, {ok, BreakpointsN}) ->
                                case add_steps_on_step_in_target(Pid, CurrentMFA, TargetMFA, Addrs, BreakpointsN) of
                                    Error = {error, _} -> {Error, BreakpointsN};
                                    OkResult -> OkResult
                                end
                        end,
                        {ok, Breakpoints0},
                        TargetMFAs
                    ),
                    case AddStepsOnStepInTargetsResult of
                        {Error = {error, _}, Breakpoints1} ->
                            _Breakpoints2 = clear_steps(Pid, Breakpoints1),
                            Error;
                        {ok, Breakpoints1} ->
                            RelevantFrames = StackFrames,
                            Types = [on_exc_handler || _ <- RelevantFrames],
                            add_steps_on_stack_frames(Pid, RelevantFrames, Addrs, Types, Breakpoints1)
                    end
            end
    end.

-spec add_steps_on_step_in_target(Pid, CurrentMFA, TargetMFA, Addrs, breakpoints()) ->
    {ok, breakpoints()} | {error, edb:step_in_error()}
when
    Pid :: pid(),
    CurrentMFA :: mfa(),
    TargetMFA :: mfa(),
    Addrs :: call_stack_addrs().
add_steps_on_step_in_target(Pid, CurrentMFA, TargetMFA, Addrs, Breakpoints0) ->
    {Mod, Fun, Arity} = TargetMFA,
    case try_ensure_module_loaded(Mod) of
        {error, timeout} ->
            {error, {call_target, {timeout_loading_module, Mod}}};
        {error, _} ->
            {error, {call_target, {module_not_found, Mod}}};
        ok ->
            case erl_debugger:breakpoints(Mod, Fun, Arity) of
                {error, {badkey, Mod}} ->
                    % Mod deleted concurrently?
                    {error, {cannot_breakpoint, Mod}};
                {error, {badkey, {Fun, Arity}}} ->
                    {error, {call_target, {function_not_found, TargetMFA}}};
                {ok, _} ->
                    ExtraFrames = maybe_substituted_module_extra_frames(Mod, Breakpoints0),
                    BasePatterns = [
                        % Base pattern for non-tail-calls
                        ExtraFrames ++ [CurrentMFA | tl(Addrs)],

                        % Base pattern for tail-calls
                        ExtraFrames ++ tl(Addrs)
                    ],
                    case add_steps_on_function(Pid, TargetMFA, BasePatterns, Breakpoints0) of
                        no_breakpoint_set ->
                            {error, {cannot_breakpoint, Mod}};
                        Result ->
                            Result
                    end
            end
    end.

-spec maybe_substituted_module_extra_frames(module(), breakpoints()) -> [mfa()].
maybe_substituted_module_extra_frames(Mod, Breakpoints) ->
    #breakpoints{substituted_modules = SubstitutedModules} = Breakpoints,
    case SubstitutedModules of
        #{Mod := #{added_frames := Frames, substitute := SubstituteMod}} ->
            get_further_frames_to_add(SubstituteMod, Breakpoints, [Frames]);
        #{} ->
            get_further_frames_to_add({vm_module, Mod}, Breakpoints, [])
    end.

-spec get_further_frames_to_add(vm_module(), breakpoints(), [[mfa()]]) -> [mfa()].
get_further_frames_to_add(SubstituteMod, Breakpoints, Acc) ->
    #breakpoints{further_substituted_modules = FurtherSubstitutes} = Breakpoints,
    case FurtherSubstitutes of
        #{SubstituteMod := #{added_frames := Frames, substitute := FurtherSubstituteMod}} ->
            get_further_frames_to_add(FurtherSubstituteMod, Breakpoints, [Frames | Acc]);
        #{} ->
            lists:flatten(Acc)
    end.

-spec add_steps_on_stack_frames(Pid, Frames, FrameAddrs, Types, breakpoints()) ->
    {ok, breakpoints()} | {error, Error}
when
    Pid :: pid(),
    FrameAddrs :: call_stack_addrs(),
    Frames :: [erl_debugger:stack_frame()],
    Types :: [on_any_required | on_any | on_exc_handler],
    Error :: {cannot_breakpoint, module()}.
add_steps_on_stack_frames(
    Pid, [TopFrame | MoreFrames], FrameAddrs = [_ | MoreFrameAddrs], [Type | MoreTypes], Breakpoints0
) ->
    case add_steps_on_stack_frame(Pid, TopFrame, FrameAddrs, Type, Breakpoints0) of
        {ok, Breakpoints1} ->
            add_steps_on_stack_frames(Pid, MoreFrames, MoreFrameAddrs, MoreTypes, Breakpoints1);
        no_breakpoint_set when Type =:= on_any_required ->
            %% We cannot claim success if no breakpoints were added
            {_, #{function := {Module, _, _}}, _} = TopFrame,
            {error, {cannot_breakpoint, Module}};
        skipped when Type =:= on_any_required ->
            edb_server:invariant_violation(stepping_from_unbreakable_frame);
        Failure when Failure =:= skipped; Failure =:= no_breakpoint_set ->
            add_steps_on_stack_frames(Pid, MoreFrames, MoreFrameAddrs, MoreTypes, Breakpoints0)
    end;
add_steps_on_stack_frames(_Pid, [], [], [], Breakpoints) ->
    {ok, Breakpoints}.

-spec add_steps_on_stack_frame(Pid, TopFrame, FrameAddrs, Type, breakpoints()) ->
    {ok, breakpoints()} | no_breakpoint_set | skipped
when
    Pid :: pid(),
    TopFrame :: erl_debugger:stack_frame(),
    FrameAddrs :: call_stack_addrs(),
    Type :: on_any_required | on_any | on_exc_handler.
add_steps_on_stack_frame(Pid, Frame = {_, #{function := MFA, line := Line}, _}, FrameAddrs, Type, Breakpoints) when
    is_tuple(MFA), is_integer(Line)
->
    ShouldSkip = Type =:= on_exc_handler andalso not edb_server_stack_frames:has_exception_handler(Frame),
    case ShouldSkip of
        true ->
            skipped;
        false ->
            BasePatterns = [tl(FrameAddrs)],
            add_steps_on_function(Pid, MFA, BasePatterns, Breakpoints)
    end;
add_steps_on_stack_frame(_Pid, _Addrs, _TopFrame, _Type, _Breakpoints) ->
    % no line-number information or not a user function
    skipped.

-spec add_steps_on_function(Pid, MFA, BasePatterns, breakpoints()) ->
    {ok, breakpoints()} | no_breakpoint_set
when
    Pid :: pid(),
    MFA :: mfa(),
    BasePatterns :: [call_stack_pattern()].
add_steps_on_function(Pid, MFA, BasePatterns, Breakpoints0) ->
    {Module, Fun, Arity} = MFA,
    {vm_module, VmModule} = to_vm_module(Module, Breakpoints0),
    case erl_debugger:breakpoints(VmModule, Fun, Arity) of
        {error, {badkey, _}} ->
            no_breakpoint_set;
        {ok, BreakableLines} ->
            Patterns = [[{VmModule, Fun, Arity} | BasePattern] || BasePattern <- BasePatterns],

            {Breakpoints1, SomeBreakpointSet} = maps:fold(
                fun(Line1, _, Acc0 = {AccBreakpoints0, _}) ->
                    case add_step(Pid, Patterns, {vm_module, VmModule}, Line1, AccBreakpoints0) of
                        no_breakpoint_set ->
                            Acc0;
                        {ok, AccBreakpoints1} ->
                            {AccBreakpoints1, true}
                    end
                end,
                {Breakpoints0, false},
                BreakableLines
            ),

            case SomeBreakpointSet of
                true -> {ok, Breakpoints1};
                false -> no_breakpoint_set
            end
    end.

-spec add_step(Pid, Patterns, Module, Line, breakpoints()) -> {ok, breakpoints()} | no_breakpoint_set when
    Pid :: pid(),
    Patterns :: [call_stack_pattern()],
    Module :: vm_module(),
    Line :: line().
add_step(Pid, Patterns, Module, Line, Breakpoints0) ->
    %% TODO(T233850146): Corner case - Sometimes we want to add a stepping breakpoint to the old (non-substitute)
    %% version of a module. In this case, the semantics of Erlang will call fun() in the old version of
    %% the module, and the breakpoint should be set in the old version, so we need to add a way to
    %% do this in the VM.
    case add_vm_breakpoint(Module, Line, {step, Pid}, Breakpoints0) of
        {ok, Breakpoints1} ->
            #breakpoints{steps = Steps1} = Breakpoints1,
            Steps2 = lists:foldl(
                fun(Pattern, StepsN) ->
                    edb_server_maps:add(Pid, Module, Line, Pattern, [], StepsN)
                end,
                Steps1,
                Patterns
            ),
            Breakpoints2 = Breakpoints1#breakpoints{steps = Steps2},
            {ok, Breakpoints2};
        {error, _} ->
            % This is not a line where we can set a breakpoint.
            no_breakpoint_set
    end.

-spec get_targets_for_step_in(TopFrame) -> {ok, nonempty_list(mfa())} | {error, edb:step_in_error()} when
    TopFrame :: erl_debugger:stack_frame().
get_targets_for_step_in({_, #{function := {M, _, _}, line := Line}, _}) when is_integer(Line) ->
    case edb_server_code:fetch_abstract_forms(M) of
        {error, _} = Error ->
            Error;
        {ok, Forms} ->
            case edb_server_code:get_call_targets(Line, Forms) of
                {ok, CallTargets} ->
                    MFAs = [MFA || {MFA, _Args} <- CallTargets],
                    {ok, MFAs};
                {error, CallTargetError} ->
                    {error, {call_target, CallTargetError}}
            end
    end;
get_targets_for_step_in(_TopFrame) ->
    edb_server:invariant_violation(stepping_from_unbreakable_frame).

%% --------------------------------------------------------------------
%% Execution control
%% --------------------------------------------------------------------

-doc """
Returns true if the given process is either on a user-breakpoint or a step-breakpoint.
Equivalently, returns true if the given process is on a VM breakpoint.
""".
-spec is_process_trapped(Pid, Breakpoints) -> boolean() when
    Pid :: pid(),
    Breakpoints :: breakpoints().
is_process_trapped(Pid, Breakpoints) ->
    #breakpoints{resume_actions = ResumeActions} = Breakpoints,
    maps:is_key(Pid, ResumeActions).

-spec register_breakpoint_event(Module, Line, Pid, Resume, Breakpoints) ->
    {suspend, Reason, breakpoints()} | resume
when
    Breakpoints :: breakpoints(),
    Module :: vm_module(),
    Line :: integer(),
    Pid :: pid(),
    Resume :: fun(() -> ok),
    Reason :: user_breakpoint | step.
register_breakpoint_event(Module, Line, Pid, Resume, Breakpoints0) ->
    case should_be_suspended(Module, Line, Pid, Breakpoints0) of
        {true, Reason} ->
            %% Relevant breakpoint hit. Register it, clear steps in both cases and suspend.
            Breakpoints1 = register_resume_action(Pid, Resume, Breakpoints0),
            Breakpoints2 =
                case Reason of
                    step ->
                        Breakpoints1;
                    user_breakpoint ->
                        register_user_breakpoint_hit(Module, Line, Pid, Breakpoints1)
                end,
            {ok, Breakpoints3} = clear_steps(Pid, Breakpoints2),
            {suspend, Reason, Breakpoints3};
        false ->
            resume
    end.

-spec should_be_suspended(vm_module(), line(), pid(), breakpoints()) -> {true, Reason} | false when
    Reason :: user_breakpoint | step.
should_be_suspended(Module, Line, Pid, Breakpoints) ->
    case Breakpoints#breakpoints.vm_breakpoints of
        #{Module := #{Line := #{user_breakpoint := []}}} ->
            {true, user_breakpoint};
        #{Module := #{Line := #{{step, Pid} := []}}} ->
            case Breakpoints#breakpoints.steps of
                #{Pid := #{Module := #{Line := Patterns}}} ->
                    % We need stack-frames, and these require the process to be suspended
                    case edb_server_process:try_suspend_process(Pid) of
                        true ->
                            case edb_server_stack_frames:raw_user_stack_frames(Pid) of
                                not_paused ->
                                    edb_server:invariant_violation(not_paused_right_after_suspending);
                                StackFrames when is_list(StackFrames) ->
                                    ShouldSuspend = lists:any(
                                        fun(Pattern) -> call_stack_matches(Pattern, StackFrames) end,
                                        maps:keys(Patterns)
                                    ),
                                    case ShouldSuspend of
                                        true ->
                                            %% This is a step breakpoint for the current process.
                                            %% Caller expects this process to be suspended, in this case
                                            {true, step};
                                        _ ->
                                            edb_server_process:try_resume_process(Pid),
                                            false
                                    end
                            end;
                        false ->
                            % Process was concurrently killed, etc
                            false
                    end
            end;
        _ ->
            false
    end.

-spec register_resume_action(Pid, Resume, Breakpoints) -> Breakpoints when
    Breakpoints :: breakpoints(),
    Pid :: pid(),
    Resume :: fun(() -> ok).
register_resume_action(Pid, Resume, Breakpoints) ->
    #breakpoints{resume_actions = ResumeActions} = Breakpoints,
    ResumeActions1 = ResumeActions#{Pid => Resume},
    Breakpoints#breakpoints{resume_actions = ResumeActions1}.

-spec register_user_breakpoint_hit(Module, Line, Pid, Breakpoints) -> breakpoints() when
    Breakpoints :: breakpoints(),
    Module :: vm_module(),
    Line :: integer(),
    Pid :: pid().
register_user_breakpoint_hit(Module, Line, Pid, Breakpoints) ->
    #breakpoints{user_bps_hit = UserBpsHit} = Breakpoints,
    NewBPHit = #{type => line, module => Module, line => Line},
    UserBpsHit1 = UserBpsHit#{Pid => NewBPHit},
    Breakpoints#breakpoints{user_bps_hit = UserBpsHit1}.

-spec clear_steps(pid(), breakpoints()) -> {ok, breakpoints()}.
clear_steps(Pid, Breakpoints) ->
    #breakpoints{steps = Steps} = Breakpoints,
    %% Implementation note. At the time of first writing this, maps:take introduces spurious
    %% dynamic() types that are worked around by the sequence of maps:get and maps:remove.
    PidSteps = maps:get(Pid, Steps, #{}),
    ModuleLines = [{Module, Line} || Module := LinePatterns <- PidSteps, Line := _ <- LinePatterns],
    Steps1 = maps:remove(Pid, Steps),
    Breakpoints1 = Breakpoints#breakpoints{steps = Steps1},

    Breakpoints2 = lists:foldl(
        fun({Module, Line}, Accu) ->
            try_clear_step_in_vm(Pid, Module, Line, Accu)
        end,
        Breakpoints1,
        ModuleLines
    ),

    {ok, Breakpoints2}.

%% Try to clear one step breakpoint in the VM. If error happens, do nothing.
-spec try_clear_step_in_vm(pid(), vm_module(), line(), breakpoints()) -> breakpoints().
try_clear_step_in_vm(Pid, Module, Line, Breakpoints0) ->
    case remove_vm_breakpoint(Module, Line, {step, Pid}, Breakpoints0) of
        {ok, _, Breakpoints1} -> Breakpoints1;
        {error, unknown_vm_breakpoint} -> Breakpoints0
    end.

-spec resume_processes(all | edb_server_sets:set(pid()), breakpoints()) -> breakpoints().
resume_processes(ToResume, Breakpoints) ->
    #breakpoints{user_bps_hit = UserBpsHit, resume_actions = ResumeActions} = Breakpoints,

    {UserBpsHit1, ResumeActions1} =
        case ToResume of
            all ->
                [
                    ResumeProcThatHitBP()
                 || _ := ResumeProcThatHitBP <- ResumeActions
                ],

                {#{}, #{}};
            _ ->
                [
                    ResumeProcThatHitBP()
                 || ProcThatHitBP := ResumeProcThatHitBP <- ResumeActions,
                    edb_server_sets:is_element(ProcThatHitBP, ToResume)
                ],

                {
                    edb_server_sets:map_subtract_keys(UserBpsHit, ToResume),
                    edb_server_sets:map_subtract_keys(ResumeActions, ToResume)
                }
        end,

    Breakpoints#breakpoints{user_bps_hit = UserBpsHit1, resume_actions = ResumeActions1}.

%% --------------------------------------------------------------------
%% Helpers -- VM breakpoints
%% --------------------------------------------------------------------

% erlfmt:ignore-begin
-define(unbreakpointable_modules,
    % When stepping on processes that have these modules on their call-stack,
    % the overhead of having breakpoints on these is too high as too many processes
    % use them. Once we add native VM support for conditional breakpoints and the overhead
    % becomes low, we can remove these (T220510085)
    #{
        artillery_tracer => true, % fb-only
        gen_factory => true,  % fb-only
        wa_request_context => true, % fb-only

        gen_server => true,
        gen_statem => true
    }
).
% erlfmt:ignore-end

-spec add_vm_breakpoint(Module, Line, Reason, Breakpoints0) ->
    {ok, Breakpoints1} | {error, edb:add_breakpoint_error()}
when
    Module :: vm_module(),
    Line :: line(),
    Reason :: vm_breakpoint_reason(),
    Breakpoints0 :: breakpoints(),
    Breakpoints1 :: breakpoints().
add_vm_breakpoint({vm_module, Module}, _, _, _) when map_get(Module, ?unbreakpointable_modules) ->
    {error, {unsupported, Module}};
add_vm_breakpoint(Module, Line, Reason, Breakpoints0) ->
    %% Register the new breakpoint reason at this location
    #breakpoints{vm_breakpoints = VmBreakpoints0} = Breakpoints0,
    VmBreakpoints1 = edb_server_maps:add(Module, Line, Reason, [], VmBreakpoints0),
    Breakpoints1 = Breakpoints0#breakpoints{vm_breakpoints = VmBreakpoints1},

    %% Set the VM breakpoint.
    %% We do this regardless of whether it was already set at this location
    %% because the module could have been reloaded in the meantime.
    case vm_set_breakpoint(Module, Line) of
        ok ->
            {ok, Breakpoints1};
        {error, Error} ->
            {error, Error}
    end.

-spec remove_vm_breakpoint(Module, Line, Reason, Breakpoints0) ->
    {ok, removed | vanished, Breakpoints1} | {error, unknown_vm_breakpoint}
when
    Module :: vm_module(),
    Line :: line(),
    Reason :: vm_breakpoint_reason(),
    Breakpoints0 :: breakpoints(),
    Breakpoints1 :: breakpoints().
remove_vm_breakpoint(Module, Line, Reason, Breakpoints0) ->
    #breakpoints{vm_breakpoints = VmBreakpoints0} = Breakpoints0,

    case VmBreakpoints0 of
        #{Module := #{Line := #{Reason := []} = Reasons0}} when map_size(Reasons0) =:= 1 ->
            %% We have exactly one breakpoint reason on this line (and it's the one we're trying to remove)
            %% Unset the breakpoint and remove this location from the state
            VmBreakpoints1 = edb_server_maps:remove(Module, Line, VmBreakpoints0),
            Breakpoints1 = Breakpoints0#breakpoints{vm_breakpoints = VmBreakpoints1},

            DeletionResult = vm_unset_breakpoint(Module, Line),
            {ok, DeletionResult, Breakpoints1};
        #{Module := #{Line := #{Reason := []} = Reasons0}} when map_size(Reasons0) > 1 ->
            %% We have more than one VM breakpoint on this line (and one of them is the one we're trying to remove)
            %% Remove the reason and leave the VM breakpoint in place
            Reasons1 = maps:remove(Reason, Reasons0),
            VmBreakpoints1 = edb_server_maps:add(Module, Line, Reasons1, VmBreakpoints0),
            Breakpoints1 = Breakpoints0#breakpoints{vm_breakpoints = VmBreakpoints1},
            {ok, removed, Breakpoints1};
        _ ->
            %% We don't have the VM breakpoint we're trying to remove on this line, this is a user bug.
            %% Since the user must be another function of this module, this is likely to be an error in the caller code.
            %% If the caller expected this to be a valid breakpoint (it was registered in the internal state),
            %% then this is invariant violation.
            {error, unknown_vm_breakpoint}
    end.

%% Low-level VM breakpoint functions. Do not use directly (but through add/remove).

-spec vm_set_breakpoint(Module, Line) -> ok | {error, edb:add_breakpoint_error()} when
    Module :: vm_module(),
    Line :: line().
vm_set_breakpoint({vm_module, Module}, Line) ->
    case erl_debugger:instrumentations() of
        #{line_breakpoint := true} ->
            case erl_debugger:breakpoint(Module, Line, true) of
                ok ->
                    ok;
                {error, Reason} ->
                    {error, Reason}
            end;
        _ ->
            {error, unsupported}
    end.

-spec vm_unset_breakpoint(Module, Line) -> removed | vanished when
    Module :: vm_module(),
    Line :: line().
vm_unset_breakpoint({vm_module, Module}, Line) ->
    case erl_debugger:breakpoint(Module, Line, false) of
        ok ->
            %% Breakpoint has been successfully removed from the VM
            removed;
        {error, _} ->
            % Module with the breakpoint was unloaded or something? We don't
            % have enough info atm to understand what happened, so just acknowled
            % that it isn't set anymore
            vanished
    end.

-spec reapply_breakpoints(vm_module(), breakpoints()) -> ok | {error, edb:add_breakpoint_error()}.
reapply_breakpoints(Module, Breakpoints0) ->
    #breakpoints{vm_breakpoints = VmBreakpoints} = Breakpoints0,
    AllLines = maps:keys(maps:get(Module, VmBreakpoints, #{})),
    reapply_breakpoints_with_rollback(Module, AllLines, []).

-spec reapply_breakpoints(SourceModule, TargetModule, breakpoints()) ->
    {ok, breakpoints()} | {error, edb:add_breakpoint_error()}
when
    SourceModule :: vm_module(),
    TargetModule :: vm_module().
reapply_breakpoints(SourceModule, TargetModule, Breakpoints0) ->
    #breakpoints{vm_breakpoints = VmBreakpoints} = Breakpoints0,
    AllLines = maps:keys(maps:get(SourceModule, VmBreakpoints, #{})),
    case reapply_breakpoints_with_rollback(TargetModule, AllLines, []) of
        ok ->
            Breakpoints1 = transfer_module_references(SourceModule, TargetModule, Breakpoints0),
            {ok, Breakpoints1};
        Error ->
            Error
    end.

-spec has_breakpoints(vm_module(), breakpoints()) -> boolean().
has_breakpoints(Module, Breakpoints0) ->
    #breakpoints{vm_breakpoints = VmBreakpoints} = Breakpoints0,
    maps:is_key(Module, VmBreakpoints).

-spec reapply_breakpoints_with_rollback(vm_module(), [line()], [line()]) ->
    ok | {error, edb:add_breakpoint_error()}.
reapply_breakpoints_with_rollback(_Module, [], _Applied) ->
    ok;
reapply_breakpoints_with_rollback(Module, [Line | Rest], Applied) ->
    case vm_set_breakpoint(Module, Line) of
        ok ->
            reapply_breakpoints_with_rollback(Module, Rest, [Line | Applied]);
        {error, _} = Error ->
            % Unset all previously applied breakpoints
            lists:foreach(
                fun(AppliedLine) ->
                    vm_unset_breakpoint(Module, AppliedLine)
                end,
                Applied
            ),
            Error
    end.

-spec transfer_module_references(SourceModule, TargetModule, Breakpoints0) -> Breakpoints1 when
    SourceModule :: vm_module(),
    TargetModule :: vm_module(),
    Breakpoints0 :: breakpoints(),
    Breakpoints1 :: breakpoints().
transfer_module_references(SourceModule, TargetModule, Breakpoints0) ->
    #breakpoints{
        steps = Steps0,
        vm_breakpoints = VmBreakpoints0
    } = Breakpoints0,

    Steps1 =
        #{
            Pid =>
                case PidSteps of
                    #{SourceModule := LinePatterns} ->
                        PidSteps#{TargetModule => LinePatterns};
                    #{} ->
                        PidSteps
                end
         || Pid := PidSteps <- Steps0
        },

    VmBreakpoints1 =
        case VmBreakpoints0 of
            #{SourceModule := LineReasons} ->
                VmBreakpoints0#{TargetModule => LineReasons};
            #{} ->
                VmBreakpoints0
        end,

    Breakpoints0#breakpoints{
        steps = Steps1,
        vm_breakpoints = VmBreakpoints1
    }.

%%--------------------------------------------------------------------
%% Module substitutes
%%--------------------------------------------------------------------

-spec to_vm_module(Module, Breakpoints) -> vm_module() when
    Module :: module(),
    Breakpoints :: breakpoints().
to_vm_module(Module, Breakpoints) ->
    resolve_module_substitute(Module, Breakpoints).

-spec from_vm_module(VmModule, Breakpoints) -> module() when
    VmModule :: vm_module(),
    Breakpoints :: breakpoints().
from_vm_module(VmModule, Breakpoints) ->
    resolve_module_substitute_reverse(VmModule, Breakpoints).

-spec add_module_substitute(Module, Substitute, AddedFrames, Breakpoints0) ->
    {ok, Breakpoints1} | {error, edb_server:add_substitute_error()}
when
    Module :: module(),
    Substitute :: module(),
    AddedFrames :: [mfa()],
    Breakpoints0 :: breakpoints(),
    Breakpoints1 :: breakpoints().
add_module_substitute(Module, Substitute, AddedFrames, Breakpoints0) ->
    #breakpoints{
        substituted_modules = SubstitutedModules0,
        further_substituted_modules = FurtherSubstitutes0,
        substituted_modules_reverse = SubstitutedModulesReverse0
    } = Breakpoints0,
    case has_breakpoints(to_vm_module(Substitute, Breakpoints0), Breakpoints0) of
        true ->
            {error, already_has_breakpoints};
        false ->
            case maps:is_key(Module, SubstitutedModules0) of
                true ->
                    {error, already_substituted};
                false ->
                    VmSubstitute = {vm_module, Substitute},
                    case maps:is_key(VmSubstitute, SubstitutedModulesReverse0) of
                        true ->
                            {error, is_already_a_substitute};
                        false ->
                            VmModule = {vm_module, Module},
                            case FurtherSubstitutes0 of
                                #{VmModule := _} ->
                                    {error, already_substituted};
                                #{} ->
                                    Breakpoints1 =
                                        case reapply_breakpoints(VmModule, VmSubstitute, Breakpoints0) of
                                            {ok, BreakpointsAfterReapplying} -> BreakpointsAfterReapplying;
                                            {error, _} -> Breakpoints0
                                        end,

                                    case SubstitutedModulesReverse0 of
                                        #{VmModule := _} ->
                                            FurtherSubstitutes1 = FurtherSubstitutes0#{
                                                VmModule => #{
                                                    substitute => VmSubstitute,
                                                    added_frames => AddedFrames
                                                }
                                            },
                                            SubstitutedModulesReverse1 = SubstitutedModulesReverse0#{
                                                VmSubstitute => VmModule
                                            },
                                            Breakpoints2 = Breakpoints1#breakpoints{
                                                further_substituted_modules = FurtherSubstitutes1,
                                                substituted_modules_reverse = SubstitutedModulesReverse1
                                            },
                                            {ok, Breakpoints2};
                                        #{} ->
                                            SubstitutedModules1 = SubstitutedModules0#{
                                                Module => #{
                                                    substitute => VmSubstitute,
                                                    added_frames => AddedFrames,
                                                    original_sources => edb_server_code:module_source(Module)
                                                }
                                            },
                                            SubstitutedModulesReverse1 = SubstitutedModulesReverse0#{
                                                VmSubstitute => Module
                                            },
                                            Breakpoints2 = Breakpoints1#breakpoints{
                                                substituted_modules = SubstitutedModules1,
                                                substituted_modules_reverse = SubstitutedModulesReverse1
                                            },
                                            {ok, Breakpoints2}
                                    end
                            end
                    end
            end
    end.

-spec resolve_module_substitute(Module, Breakpoints) -> vm_module() when
    Module :: module() | vm_module(),
    Breakpoints :: breakpoints().
resolve_module_substitute(Module, #breakpoints{substituted_modules = SubstitutedModules} = Breakpoints) when
    is_atom(Module)
->
    case SubstitutedModules of
        #{Module := #{substitute := Substitute}} ->
            resolve_module_substitute(Substitute, Breakpoints);
        _ ->
            {vm_module, Module}
    end;
resolve_module_substitute(
    Subst = {vm_module, _}, #breakpoints{further_substituted_modules = FurtherSubstitutedModules} = Breakpoints
) ->
    case FurtherSubstitutedModules of
        #{Subst := #{substitute := FurtherSubstitute}} ->
            resolve_module_substitute(FurtherSubstitute, Breakpoints);
        _ ->
            Subst
    end.

-spec resolve_module_substitute_reverse(Substitute, Breakpoints) -> module() when
    Substitute :: vm_module(),
    Breakpoints :: breakpoints().
resolve_module_substitute_reverse({vm_module, SubMod} = Substitute, Breakpoints) ->
    #breakpoints{substituted_modules_reverse = SubstitutedModulesReverse} = Breakpoints,
    case SubstitutedModulesReverse of
        #{Substitute := {vm_module, _} = PrevSubstitute} ->
            resolve_module_substitute_reverse(PrevSubstitute, Breakpoints);
        #{Substitute := OrigModule} when is_atom(OrigModule) ->
            OrigModule;
        #{} ->
            SubMod
    end.

-spec remove_module_substitute(SubstituteModule, Breakpoints0) ->
    {ok, Breakpoints1} | {error, edb_server:remove_substitute_error()}
when
    SubstituteModule :: module(),
    Breakpoints0 :: breakpoints(),
    Breakpoints1 :: breakpoints().
remove_module_substitute(SubstituteModule, Breakpoints0) ->
    #breakpoints{
        substituted_modules = SubstitutedModules0,
        further_substituted_modules = FurtherSubstitutes0,
        substituted_modules_reverse = SubstituteModulesReverse0
    } = Breakpoints0,
    VmSubstitute = {vm_module, SubstituteModule},
    case SubstituteModulesReverse0 of
        #{VmSubstitute := OriginalModule} ->
            {SubstitutedModules1, FurtherSubstitutes1, SubstitutedModulesReverse1} = remove_substitute(
                OriginalModule, VmSubstitute, SubstitutedModules0, FurtherSubstitutes0, SubstituteModulesReverse0
            ),
            case FurtherSubstitutes0 of
                #{VmSubstitute := _SubstituteModuleNext} ->
                    {error, has_dependent_substitute};
                #{} ->
                    Breakpoints1 = Breakpoints0#breakpoints{
                        substituted_modules = SubstitutedModules1,
                        further_substituted_modules = FurtherSubstitutes1,
                        substituted_modules_reverse = SubstitutedModulesReverse1
                    },
                    OriginalModuleAtom =
                        case OriginalModule of
                            {vm_module, Mod} -> Mod;
                            Mod -> Mod
                        end,
                    {module, OriginalModuleAtom} = code:ensure_loaded(OriginalModuleAtom),
                    VmOriginalModule = {vm_module, OriginalModuleAtom},
                    case reapply_breakpoints(VmSubstitute, VmOriginalModule, Breakpoints1) of
                        {ok, Breakpoints2} -> {ok, Breakpoints2};
                        {error, _} -> {ok, Breakpoints1}
                    end
            end;
        #{} ->
            {error, not_a_substitute}
    end.

-spec remove_substitute(
    OriginalModule :: module() | vm_module(),
    SubstituteModule :: vm_module(),
    SubstitutedModules :: #{module() => substitute_info()},
    FurtherSubstitutes :: #{vm_module() => further_substitute_info()},
    SubstitutedModulesReverse :: #{vm_module() => module() | vm_module()}
) ->
    {#{module() => substitute_info()}, #{vm_module() => further_substitute_info()}, #{
        vm_module() => module() | vm_module()
    }}.
remove_substitute(
    {vm_module, _} = OriginalModule,
    SubstituteModule,
    SubstitutedModules,
    FurtherSubstitutes,
    SubstitutedModulesReverse
) ->
    {
        SubstitutedModules,
        maps:remove(OriginalModule, FurtherSubstitutes),
        maps:remove(SubstituteModule, SubstitutedModulesReverse)
    };
remove_substitute(
    OriginalModule, SubstituteModule, SubstitutedModules, FurtherSubstitutes, SubstitutedModulesReverse
) ->
    {
        maps:remove(OriginalModule, SubstitutedModules),
        FurtherSubstitutes,
        maps:remove(SubstituteModule, SubstitutedModulesReverse)
    }.

%% --------------------------------------------------------------------
%% Module info
%% --------------------------------------------------------------------

-spec try_ensure_module_loaded(Module) -> ok | {error, embedded | badfile | nofile | timeout} when
    Module :: module().
try_ensure_module_loaded(Module) ->
    ResponseRef = erlang:make_ref(),
    Me = self(),
    {Pid, MonRef} = erlang:spawn_monitor(fun() -> Me ! {ResponseRef, code:ensure_loaded(Module)} end),
    receive
        {ResponseRef, {module, Module}} -> ok;
        {ResponseRef, Err = {error, _}} -> Err;
        {'DOWN', MonRef, process, Pid, Reason} -> error({crashed_ensuring_loaded, Reason})
    after 5_000 ->
        erlang:exit(Pid, kill),
        receive
            {'DOWN', MonRef, process, Pid, _Reason} -> ok
        end,
        receive
            {ResponseRef, {module, Module}} -> ok;
            {ResponseRef, Err = {error, _}} -> Err
        after 0 ->
            {error, timeout}
        end
    end.

-spec get_vm_module_source(VmModule, Breakpoints) -> file:filename() | undefined when
    VmModule :: vm_module(),
    Breakpoints :: breakpoints().
get_vm_module_source(VmModule, Breakpoints) ->
    #breakpoints{substituted_modules = SubstitutedModules} = Breakpoints,
    OriginalModule = from_vm_module(VmModule, Breakpoints),
    case SubstitutedModules of
        #{OriginalModule := #{original_sources := Source}} ->
            Source;
        #{} ->
            edb_server_code:module_source(OriginalModule)
    end.

%% --------------------------------------------------------------------
%% Helpers -- call-stacks and call-stack patterns
%% --------------------------------------------------------------------

-type call_stack_addrs() :: [CodeAddr :: pos_integer()].
-type call_stack_pattern() :: [mfa() | CodeAddr :: pos_integer()].

-spec call_stack_addrs(RawFrames) -> call_stack_addrs() when
    RawFrames :: [erl_debugger:stack_frame()].
call_stack_addrs(RawFrames) ->
    [CodeAddr || {_, _, #{code := CodeAddr}} <- RawFrames].

-spec call_stack_matches(Pattern, RawFrames) -> boolean() when
    Pattern :: call_stack_pattern(),
    RawFrames :: [erl_debugger:stack_frame()].
call_stack_matches([], []) ->
    true;
call_stack_matches([MFA | MorePattern], [{_, #{function := MFA}, _} | MoreFrames]) when is_tuple(MFA) ->
    call_stack_matches(MorePattern, MoreFrames);
call_stack_matches([CodeAddr | MorePattern], [{_, _, #{code := CodeAddr}} | MoreFrames]) when is_integer(CodeAddr) ->
    call_stack_matches(MorePattern, MoreFrames);
call_stack_matches(_, _) ->
    false.
