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

% Explicit brekapoints manipulation
-export([add_explicit/3, add_explicits/3]).
-export([get_explicits/1, get_explicits/2]).
-export([clear_explicit/3, clear_explicits/2]).
-export([get_explicits_hit/1, get_explicit_hit/2]).

% Stepping
-export([prepare_for_stepping/3]).
-export([prepare_for_stepping_in/2]).

% Execution control
-export([is_process_trapped/2]).
-export([register_breakpoint_event/5]).
-export([resume_processes/2]).

-compile(warn_missing_spec_all).

%% erlfmt:ignore
% @fb-only

%% --------------------------------------------------------------------
%% Types
%% --------------------------------------------------------------------

-type line() :: edb:line().

-export_type([breakpoints/0]).
-record(breakpoints, {
    %% TODO(T198738599): we should somehow keep track of the identity
    %% of the module instance on which the breakpoint
    %% was set? The general problem is that right now when
    %% a module is reloaded, breakpoints remain on the old
    %% version of the code (until purged) and will not exist
    %% on the new version (lines could have changed, so seems
    %% right). We need some way to be aware/handle this.

    %% Explicit breakpoints requested by the client, grouped by module
    explicits :: #{module() => #{line() => []}},

    %% Internal breakpoints set by the server to step through, grouped by pid.
    %% For each such breakpoint, there are only certain call-stacks under which
    %% we want to suspend the process.
    steps :: #{pid() => #{{module(), line()} => #{call_stack_pattern() => []}}},

    %% Explicit breakpoints that have been hit
    explicits_hit :: #{pid() => {module(), line()}},

    %% Callbacks to resume processes that hit a VM breakpoint
    resume_actions :: #{pid() => fun(() -> ok)},

    %% Sets of reasons why VM breakpoints were set on each locations
    vm_breakpoints :: #{{module(), line()} => #{vm_breakpoint_reason() => []}}
}).

-type vm_breakpoint_reason() ::
    explicit
    | {step, pid()}.

-opaque breakpoints() :: #breakpoints{}.

%% --------------------------------------------------------------------
%% Creation
%% --------------------------------------------------------------------

-spec create() -> breakpoints().
create() ->
    #breakpoints{
        explicits = #{},
        steps = #{},
        explicits_hit = #{},
        resume_actions = #{},
        vm_breakpoints = #{}
    }.

%% --------------------------------------------------------------------
%% Explicit breakpoints manipulation
%% --------------------------------------------------------------------
-spec add_explicit(module(), line(), breakpoints()) -> {ok, breakpoints()} | {error, edb:add_breakpoint_error()}.
add_explicit(Module, Line, Breakpoints0) ->
    case add_vm_breakpoint(Module, Line, explicit, Breakpoints0) of
        {ok, Breakpoints1} ->
            #breakpoints{explicits = Explicits1} = Breakpoints1,
            Explicits2 = edb_server_maps:add(Module, Line, [], Explicits1),
            Breakpoints2 = Breakpoints1#breakpoints{explicits = Explicits2},
            {ok, Breakpoints2};
        {error, Reason} ->
            {error, Reason}
    end.

-spec add_explicits(module(), [line()], breakpoints()) -> {LineResults, breakpoints()} when
    LineResults :: [{line(), Result}],
    Result :: ok | {error, edb:add_breakpoint_error()}.
add_explicits(Module, Lines, Breakpoints0) ->
    lists:mapfoldl(
        fun(Line, AccBreakpointsIn) ->
            case add_explicit(Module, Line, AccBreakpointsIn) of
                {ok, AccBreakpointsOut} -> {{Line, ok}, AccBreakpointsOut};
                {error, Error} -> {{Line, {error, Error}}, AccBreakpointsIn}
            end
        end,
        Breakpoints0,
        Lines
    ).

-spec get_explicits(breakpoints()) -> #{module() => #{line() => []}}.
get_explicits(#breakpoints{explicits = Explicits}) ->
    Explicits.

-spec get_explicits(module(), breakpoints()) -> #{line() => []}.
get_explicits(Module, #breakpoints{explicits = Explicits}) ->
    maps:get(Module, Explicits, #{}).

-spec clear_explicit(module(), line(), breakpoints()) ->
    {ok, removed | vanished, breakpoints()} | {error, not_found}.
clear_explicit(Module, Line, Breakpoints0) ->
    case unregister_explicit(Module, Line, Breakpoints0) of
        {found, Breakpoints1} ->
            %% We knew about this breakpoint. Now remove it from the VM.
            case remove_vm_breakpoint(Module, Line, explicit, Breakpoints1) of
                {ok, DeletionResult, Breakpoints2} ->
                    {ok, DeletionResult, Breakpoints2};
                {error, unknown_vm_breakpoint} ->
                    % Breakpoint was registered as explicit but not as a reason?
                    % This should never happen, if it does we have a bug.
                    edb_server:invariant_violation(inconsistent_explicit_breakpoint)
            end;
        not_found ->
            %% We didn't know about this breakpoint, trying to clear it is a user error.
            {error, not_found}
    end.

-spec clear_explicits(module(), breakpoints()) -> {ok, breakpoints()}.
clear_explicits(Module, Breakpoints0) ->
    Lines = maps:keys(get_explicits(Module, Breakpoints0)),
    Breakpoints1 = lists:foldl(
        fun(Line, AccBreakpointsIn) ->
            case clear_explicit(Module, Line, AccBreakpointsIn) of
                {ok, _RemovedOrVanished, AccBreakpointsOut} -> AccBreakpointsOut;
                % A breakpoint line taken from the list cannot be not_found
                {error, not_found} -> edb_server:invariant_violation(unexpected_bp_not_found)
            end
        end,
        Breakpoints0,
        Lines
    ),
    {ok, Breakpoints1}.

-spec unregister_explicit(module(), line(), breakpoints()) -> {found, breakpoints()} | not_found.
unregister_explicit(Module, Line, Breakpoints0) ->
    #breakpoints{explicits = Explicits0} = Breakpoints0,
    BreakpointInfos0 = maps:get(Module, Explicits0, #{}),
    case edb_server_sets:take_element(Line, BreakpointInfos0) of
        not_found ->
            not_found;
        {found, BreakpointInfos1} ->
            Explicits1 =
                case edb_server_sets:is_empty(BreakpointInfos1) of
                    true -> maps:remove(Module, Explicits0);
                    false -> Explicits0#{Module := BreakpointInfos1}
                end,
            Breakpoints1 = Breakpoints0#breakpoints{explicits = Explicits1},
            {found, Breakpoints1}
    end.

-spec get_explicits_hit(breakpoints()) -> #{pid() => #{module := module(), line := line()}}.
get_explicits_hit(#breakpoints{explicits_hit = ExplicitsHit}) ->
    maps:map(
        fun(_Pid, {Module, Line}) -> #{module => Module, line => Line} end,
        ExplicitsHit
    ).

-spec get_explicit_hit(pid(), breakpoints()) ->
    {ok, #{module := module(), line := line()}} | no_breakpoint_hit.
get_explicit_hit(Pid, #breakpoints{explicits_hit = ExplicitsHit}) ->
    case ExplicitsHit of
        #{Pid := {Module, Line}} ->
            {ok, #{module => Module, line => Line}};
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
            case get_target_for_step_in(TopFrame) of
                {error, _} = Error ->
                    Error;
                {ok, MFA = {Mod, Fun, Arity}} ->
                    case edb_server_code:fetch_abstract_forms(Mod) of
                        {error, _} = Error ->
                            Error;
                        {ok, ModForms} ->
                            case edb_server_code:find_fun(Fun, Arity, ModForms) of
                                not_found ->
                                    {error, {call_target, not_found}};
                                {ok, FunForm} ->
                                    {_, #{function := CurrentMFA}, _} = TopFrame,
                                    Addrs = call_stack_addrs(StackFrames),
                                    BasePatterns = [
                                        % Base pattern for non-tail-calls
                                        [CurrentMFA | tl(Addrs)],

                                        % Base pattern for tail-calls
                                        tl(Addrs)
                                    ],
                                    case add_steps_on_function(Pid, MFA, FunForm, BasePatterns, Breakpoints0) of
                                        no_breakpoint_set ->
                                            {error, {cannot_breakpoint, Mod}};
                                        {ok, Breakpoints1} ->
                                            RelevantFrames = StackFrames,
                                            Types = [on_exc_handler || _ <- RelevantFrames],
                                            add_steps_on_stack_frames(
                                                Pid, RelevantFrames, Addrs, Types, Breakpoints1
                                            )
                                    end
                            end
                    end
            end
    end.

-spec add_steps_on_stack_frames(Pid, Frames, FrameAddrs, Types, breakpoints()) ->
    {ok, breakpoints()} | {error, Error}
when
    Pid :: pid(),
    FrameAddrs :: call_stack_addrs(),
    Frames :: [erl_debugger:stack_frame()],
    Types :: [on_any_required | on_any | on_exc_handler],
    Error :: no_abstract_code | {cannot_breakpoint, module()} | {beam_analysis, term()}.
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
            add_steps_on_stack_frames(Pid, MoreFrames, MoreFrameAddrs, MoreTypes, Breakpoints0);
        {error, {beam_analysis, dynamically_compiled}} when Type /= on_any_required ->
            % Dynamically compiled code on the stack (no beam file available), let's not fail
            add_steps_on_stack_frames(Pid, MoreFrames, MoreFrameAddrs, MoreTypes, Breakpoints0);
        {error, Error} ->
            {error, Error}
    end;
add_steps_on_stack_frames(_Pid, [], [], [], Breakpoints) ->
    {ok, Breakpoints}.

-spec add_steps_on_stack_frame(Pid, TopFrame, FrameAddrs, Type, breakpoints()) ->
    {ok, breakpoints()} | no_breakpoint_set | skipped | {error, Error}
when
    Pid :: pid(),
    TopFrame :: erl_debugger:stack_frame(),
    FrameAddrs :: call_stack_addrs(),
    Type :: on_any_required | on_any | on_exc_handler,
    Error :: no_abstract_code | {beam_analysis, term()}.
add_steps_on_stack_frame(Pid, Frame = {_, #{function := MFA, line := Line}, _}, FrameAddrs, Type, Breakpoints) when
    is_tuple(MFA), is_integer(Line)
->
    ShouldSkip = Type =:= on_exc_handler andalso not edb_server_stack_frames:has_exception_handler(Frame),
    case ShouldSkip of
        true ->
            skipped;
        false ->
            {Module, _, _} = MFA,
            case edb_server_code:fetch_abstract_forms(Module) of
                {error, _} = Error ->
                    Error;
                {ok, Forms} ->
                    case edb_server_code:find_fun_containing_line(Line, Forms) of
                        {ok, Form} ->
                            BasePatterns = [tl(FrameAddrs)],
                            add_steps_on_function(Pid, MFA, Form, BasePatterns, Breakpoints);
                        not_found ->
                            {error, {beam_analysis, {invalid_line, Line}}}
                    end
            end
    end;
add_steps_on_stack_frame(_Pid, _Addrs, _TopFrame, _Type, _Breakpoints) ->
    % no line-number information or not a user function
    skipped.

-spec add_steps_on_function(Pid, MFA, FunForm, BasePatterns, breakpoints()) ->
    {ok, breakpoints()} | no_breakpoint_set
when
    Pid :: pid(),
    MFA :: mfa(),
    FunForm :: edb_server_code:form(),
    BasePatterns :: [call_stack_pattern()].
add_steps_on_function(Pid, MFA, FunForm, BasePatterns, Breakpoints0) ->
    {From, To} = edb_server_code:get_line_span(FunForm),
    Lines = lists:seq(From, To),

    {Module, _, _} = MFA,
    Patterns = [[MFA | BasePattern] || BasePattern <- BasePatterns],

    {Breakpoints1, SomeBreakpointSet} = lists:foldl(
        fun(Line1, Acc0 = {AccBreakpoints0, _}) ->
            case add_step(Pid, Patterns, Module, Line1, AccBreakpoints0) of
                no_breakpoint_set ->
                    Acc0;
                {ok, AccBreakpoints1} ->
                    {AccBreakpoints1, true}
            end
        end,
        {Breakpoints0, false},
        Lines
    ),

    case SomeBreakpointSet of
        true -> {ok, Breakpoints1};
        false -> no_breakpoint_set
    end.

-spec add_step(Pid, Patterns, Module, Line, breakpoints()) -> {ok, breakpoints()} | no_breakpoint_set when
    Pid :: pid(),
    Patterns :: [call_stack_pattern()],
    Module :: module(),
    Line :: line().
add_step(Pid, Patterns, Module, Line, Breakpoints0) ->
    case add_vm_breakpoint(Module, Line, {step, Pid}, Breakpoints0) of
        {ok, Breakpoints1} ->
            #breakpoints{steps = Steps1} = Breakpoints1,
            Steps2 = lists:foldl(
                fun(Pattern, StepsN) -> edb_server_maps:add(Pid, {Module, Line}, Pattern, [], StepsN) end,
                Steps1,
                Patterns
            ),
            Breakpoints2 = Breakpoints1#breakpoints{steps = Steps2},
            {ok, Breakpoints2};
        {error, _} ->
            % This is not a line where we can set a breakpoint.
            no_breakpoint_set
    end.

-spec get_target_for_step_in(TopFrame) -> {ok, mfa()} | {error, edb:step_in_error()} when
    TopFrame :: erl_debugger:stack_frame().
get_target_for_step_in({_, #{function := {M, _, _}, line := Line}, _}) when is_integer(Line) ->
    case edb_server_code:fetch_abstract_forms(M) of
        {error, _} = Error ->
            Error;
        {ok, Forms} ->
            case edb_server_code:get_call_target(Line, Forms) of
                {ok, {MFA, _Args}} ->
                    {ok, MFA};
                {error, CallTargetError} ->
                    {error, {call_target, CallTargetError}}
            end
    end;
get_target_for_step_in(_TopFrame) ->
    edb_server:invariant_violation(stepping_from_unbreakable_frame).

%% --------------------------------------------------------------------
%% Execution control
%% --------------------------------------------------------------------

%% @doc Returns true if the given process is either on an explicit breakpoint or a step breakpoint.
%% Equivalently, returns true if the given process is on a VM breakpoint.
-spec is_process_trapped(Pid, Breakpoints) -> boolean() when
    Pid :: pid(),
    Breakpoints :: breakpoints().
is_process_trapped(Pid, Breakpoints) ->
    #breakpoints{resume_actions = ResumeActions} = Breakpoints,
    maps:is_key(Pid, ResumeActions).

-spec register_breakpoint_event(Module, Line, Pid, Resume, Breakpoints) ->
    {suspend, explicit | step, breakpoints()} | resume
when
    Breakpoints :: breakpoints(),
    Module :: module(),
    Line :: integer(),
    Pid :: pid(),
    Resume :: fun(() -> ok).
register_breakpoint_event(Module, Line, Pid, Resume, Breakpoints0) ->
    case should_be_suspended(Module, Line, Pid, Breakpoints0) of
        {true, Reason} ->
            %% Relevant breakpoint hit. Register it, clear steps in both cases and suspend.
            Breakpoints1 = register_resume_action(Pid, Resume, Breakpoints0),
            Breakpoints2 =
                case Reason of
                    step ->
                        Breakpoints1;
                    explicit ->
                        register_explicit_hit(Module, Line, Pid, Breakpoints1)
                end,
            {ok, Breakpoints3} = clear_steps(Pid, Breakpoints2),
            {suspend, Reason, Breakpoints3};
        false ->
            resume
    end.

-spec should_be_suspended(module(), line(), pid(), breakpoints()) -> {true, explicit | step} | false.
should_be_suspended(Module, Line, Pid, Breakpoints) ->
    #breakpoints{explicits = Explicits, steps = Steps} = Breakpoints,
    case Explicits of
        #{Module := #{Line := []}} ->
            %% This is an explicit breakpoint
            {true, explicit};
        _ ->
            case Steps of
                #{Pid := #{{Module, Line} := Patterns}} ->
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
                    end;
                _ ->
                    false
            end
    end.

-spec register_resume_action(Pid, Resume, Breakpoints) -> Breakpoints when
    Breakpoints :: breakpoints(),
    Pid :: pid(),
    Resume :: fun(() -> ok).
register_resume_action(Pid, Resume, Breakpoints) ->
    #breakpoints{resume_actions = ResumeActions} = Breakpoints,
    ResumeActions1 = ResumeActions#{Pid => Resume},
    Breakpoints#breakpoints{resume_actions = ResumeActions1}.

-spec register_explicit_hit(Module, Line, Pid, Breakpoints) -> breakpoints() when
    Breakpoints :: breakpoints(),
    Module :: module(),
    Line :: integer(),
    Pid :: pid().
register_explicit_hit(Module, Line, Pid, Breakpoints) ->
    #breakpoints{explicits_hit = ExplicitsHit} = Breakpoints,
    NewBPHit = {Module, Line},
    ExplicitsHit1 = ExplicitsHit#{Pid => NewBPHit},
    Breakpoints#breakpoints{explicits_hit = ExplicitsHit1}.

-spec clear_steps(pid(), breakpoints()) -> {ok, breakpoints()}.
clear_steps(Pid, Breakpoints) ->
    #breakpoints{steps = Steps} = Breakpoints,
    %% Implementation note. At the time of first writing this, maps:take introduces spurious
    %% dynamic() types that are worked around by the sequence of maps:get and maps:remove.
    PidSteps = maps:get(Pid, Steps, #{}),
    Steps1 = maps:remove(Pid, Steps),
    Breakpoints1 = Breakpoints#breakpoints{steps = Steps1},

    Breakpoints2 = maps:fold(
        fun({Module, Line}, _Patterns, Accu) ->
            try_clear_step_in_vm(Pid, Module, Line, Accu)
        end,
        Breakpoints1,
        PidSteps
    ),

    {ok, Breakpoints2}.

%% Try to clear one step breakpoint in the VM. If error happens, do nothing.
-spec try_clear_step_in_vm(pid(), module(), line(), breakpoints()) -> breakpoints().
try_clear_step_in_vm(Pid, Module, Line, Breakpoints0) ->
    case remove_vm_breakpoint(Module, Line, {step, Pid}, Breakpoints0) of
        {ok, _, Breakpoints1} -> Breakpoints1;
        {error, unknown_vm_breakpoint} -> Breakpoints0
    end.

-spec resume_processes(all | edb_server_sets:set(pid()), breakpoints()) -> breakpoints().
resume_processes(ToResume, Breakpoints) ->
    #breakpoints{explicits_hit = ExplicitsHit, resume_actions = ResumeActions} = Breakpoints,

    {ExplicitsHit1, ResumeActions1} =
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
                    edb_server_sets:map_subtract_keys(ExplicitsHit, ToResume),
                    edb_server_sets:map_subtract_keys(ResumeActions, ToResume)
                }
        end,

    Breakpoints#breakpoints{explicits_hit = ExplicitsHit1, resume_actions = ResumeActions1}.

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
    Module :: module(),
    Line :: line(),
    Reason :: vm_breakpoint_reason(),
    Breakpoints0 :: breakpoints(),
    Breakpoints1 :: breakpoints().
add_vm_breakpoint(Module, _, _, _) when map_get(Module, ?unbreakpointable_modules) ->
    {error, {unsupported, Module}};
add_vm_breakpoint(Module, Line, Reason, Breakpoints0) ->
    %% Register the new breakpoint reason at this location
    #breakpoints{vm_breakpoints = VmBreakpoints0} = Breakpoints0,
    VmBreakpoints1 = edb_server_maps:add({Module, Line}, Reason, [], VmBreakpoints0),
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
    Module :: module(),
    Line :: line(),
    Reason :: vm_breakpoint_reason(),
    Breakpoints0 :: breakpoints(),
    Breakpoints1 :: breakpoints().
remove_vm_breakpoint(Module, Line, Reason, Breakpoints0) ->
    #breakpoints{vm_breakpoints = VmBreakpoints0} = Breakpoints0,

    case VmBreakpoints0 of
        #{{Module, Line} := #{Reason := []} = Reasons0} when map_size(Reasons0) =:= 1 ->
            %% We have exactly one breakpoint reason on this line (and it's the one we're trying to remove)
            %% Unset the breakpoint and remove this location from the state
            VmBreakpoints1 = maps:remove({Module, Line}, VmBreakpoints0),
            Breakpoints1 = Breakpoints0#breakpoints{vm_breakpoints = VmBreakpoints1},

            DeletionResult = vm_unset_breakpoint(Module, Line),
            {ok, DeletionResult, Breakpoints1};
        #{{Module, Line} := #{Reason := []} = Reasons0} when map_size(Reasons0) > 1 ->
            %% We have more than one VM breakpoint on this line (and one of them is the one we're trying to remove)
            %% Remove the reason and leave the VM breakpoint in place
            Reasons1 = maps:remove(Reason, Reasons0),
            VmBreakpoints1 = VmBreakpoints0#{{Module, Line} => Reasons1},
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
    Module :: module(),
    Line :: line().
vm_set_breakpoint(Module, Line) ->
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
    Module :: module(),
    Line :: line().
vm_unset_breakpoint(Module, Line) ->
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
