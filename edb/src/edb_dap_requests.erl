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
%%%-------------------------------------------------------------------
%% @doc DAP Request Handlers
%%      The actual implementation for the DAP requests.
%%      This function should be invoked by the DAP server.
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(edb_dap_requests).

%% erlfmt:ignore
% @fb-only: 
-compile(warn_missing_spec_all).
-include("edb_dap.hrl").
-include_lib("kernel/include/logger.hrl").

-export([initialize/2, launch/2, disconnect/2]).
-export([set_breakpoints/2, pause/2, continue/2, next/2, step_out/2]).
-export([threads/2, stack_trace/2, scopes/2, variables/2]).

-type reaction(T) :: #{
    response := T | edb_dap:error_response(),
    actions => [edb_dap_server:action()],
    state => edb_dap_state:t()
}.
-export_type([reaction/1]).

-define(MAX_TERM_SIZE, 1_000_000).
-define(DEFAULT_ATTACH_TIMEOUT_IN_SECS, 60).
-define(ERL_FLAGS, <<"+D">>).

-spec initialize(edb_dap_state:t(), edb_dap:initialize_request_arguments()) ->
    reaction(edb_dap:initialize_response()).
initialize(State, _Args) ->
    case edb_dap_state:is_initialized(State) of
        false ->
            Capabilities = capabilities(),
            #{
                response => #{success => true, body => Capabilities},
                state => edb_dap_state:set_status(State, initialized)
            };
        true ->
            #{
                response => edb_dap:build_error_response(?JSON_RPC_ERROR_INVALID_REQUEST, <<"Already initialized">>)
            }
    end.

-spec launch(edb_dap_state:t(), edb_dap:launch_request_arguments()) ->
    reaction(edb_dap:launch_response()).
launch(State, Args) ->
    #{launchCommand := LaunchCommand, targetNode := TargetNode} = Args,
    #{cwd := Cwd, command := Command} = LaunchCommand,
    AttachTimeoutInSecs = maps:get(timeout, Args, ?DEFAULT_ATTACH_TIMEOUT_IN_SECS),
    StripSourcePrefix = maps:get(stripSourcePrefix, Args, <<>>),
    Arguments = maps:get(arguments, LaunchCommand, []),
    Env = maps:get(env, LaunchCommand, #{}),
    RunInTerminalRequest = #{
        kind => <<"integrated">>,
        title => <<"EDB">>,
        cwd => Cwd,
        args => [Command | Arguments],
        env => Env#{'ERL_FLAGS' => ?ERL_FLAGS}
    },
    #{
        response => #{success => true},
        actions => [{reverse_request, <<"runInTerminal">>, RunInTerminalRequest}],
        state => edb_dap_state:set_context(State, context(TargetNode, AttachTimeoutInSecs, Cwd, StripSourcePrefix))
    }.

-spec disconnect(edb_dap_state:t(), edb_dap:disconnect_request_arguments()) ->
    reaction(edb_dap:disconnect_response()).
disconnect(_State, _Args) ->
    % TODO(T206222651) make the behaviour compliant
    ok = edb:terminate(),
    #{
        response => #{success => true},
        actions => [terminate]
    }.

-spec set_breakpoints(edb_dap_state:t(), edb_dap:set_breakpoints_request_arguments()) ->
    reaction(edb_dap:set_breakpoints_response()).
set_breakpoints(State, #{source := #{path := Path}} = Args) ->
    Module = binary_to_atom(filename:basename(Path, ".erl")),

    % TODO(T202772655): Remove once edb:set_breakpoint/2 takes care of auto-loading modules
    #{target_node := #{name := Node}} = edb_dap_state:get_context(State),
    % elp:ignore W0014 (cross_node_eval)
    erpc:call(Node, code, ensure_loaded, [Module]),

    edb:clear_breakpoints(Module),
    SourceBreakpoints = maps:get(breakpoints, Args, []),
    Breakpoints = lists:map(
        fun(#{line := Line}) ->
            case edb:add_breakpoint(Module, Line) of
                ok ->
                    #{line => Line, verified => true};
                {error, Reason} ->
                    ?LOG_WARNING("Failed to set breakpoint: ~p, ~p, ~p", [Module, Line, Reason]),
                    Message = edb:format("~p", [Reason]),
                    #{line => Line, verified => false, message => Message, reason => <<"failed">>}
            end
        end,
        SourceBreakpoints
    ),
    Body = #{breakpoints => Breakpoints},
    #{response => #{success => true, body => Body}}.

-spec threads(edb_dap_state:t(), edb_dap:threads_request_arguments()) ->
    reaction(edb_dap:threads_response()).
threads(_State, _Args) ->
    Threads = maps:fold(fun thread/3, [], edb:processes()),
    #{
        response => #{success => true, body => #{threads => Threads}}
    }.

-spec scopes(edb_dap_state:t(), edb_dap:scopes_request_arguments()) ->
    reaction(edb_dap:scopes_response()).
scopes(State, #{frameId := FrameId}) ->
    {ok, #{pid := Pid, frame_no := FrameNo}} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId),
    VariablesScopes =
        case edb:stack_frame_vars(Pid, FrameNo, _MaxTermSize = 1) of
            {ok, #{vars := _}} ->
                [
                    #{
                        name => <<"Locals">>,
                        presentationHint => <<"locals">>,
                        variablesReference => edb_dap_id_mappings:frame_scope_to_var_reference(#{
                            frame => FrameId, scope => locals
                        }),
                        expensive => false
                    }
                ];
            {ok, Frames} when is_map(Frames) ->
                [
                    #{
                        name => <<"Registers">>,
                        presentationHint => <<"registers">>,
                        variablesReference => edb_dap_id_mappings:frame_scope_to_var_reference(#{
                            frame => FrameId, scope => registers
                        }),
                        expensive => false
                    }
                ];
            _ ->
                []
        end,
    #{target_node := #{name := Node}} = edb_dap_state:get_context(State),
    MessagesScopes =
        % elp:ignore W0014 (cross_node_eval)
        case erpc:call(Node, erlang, process_info, [Pid, message_queue_len]) of
            {message_queue_len, N} when N > 0 ->
                [
                    #{
                        name => <<"Messages">>,
                        variablesReference => edb_dap_id_mappings:frame_scope_to_var_reference(#{
                            frame => FrameId, scope => messages
                        }),
                        expensive => false
                    }
                ];
            _ ->
                []
        end,
    #{
        response => #{
            success => true,
            body => #{
                scopes => MessagesScopes ++ VariablesScopes
            }
        }
    }.

-spec variables(edb_dap_state:t(), edb_dap:variables_request_arguments()) ->
    reaction(edb_dap:variables_response()).
variables(State, #{variablesReference := VariablesReference}) ->
    case edb_dap_id_mappings:var_reference_to_frame_scope(VariablesReference) of
        {ok, #{frame := FrameId, scope := Scope}} ->
            case edb_dap_id_mappings:frame_id_to_pid_frame(FrameId) of
                {ok, #{pid := Pid, frame_no := FrameNo}} ->
                    case Scope of
                        messages ->
                            #{target_node := #{name := Node}} = edb_dap_state:get_context(State),
                            % elp:ignore W0014 (cross_node_eval)
                            case erpc:call(Node, erlang, process_info, [Pid, messages]) of
                                {messages, Messages0} when is_list(Messages0) ->
                                    % Ideally we'd have a `erl_debugger:peek_message/1` function
                                    % which would allow us to peek at the message queue and return
                                    % a too_large entry if the message is too large.
                                    Messages = [cap_by_size(M, ?MAX_TERM_SIZE) || M <- Messages0],
                                    #{
                                        response => #{
                                            success => true,
                                            body => #{
                                                variables => unnamed_variables(<<"">>, Messages)
                                            }
                                        }
                                    };
                                _ ->
                                    ?LOG_WARNING("Cannot resolve messages for pid ~p and frame_no ~p", [Pid, FrameNo]),
                                    #{
                                        response => edb_dap:build_error_response(
                                            ?JSON_RPC_ERROR_INTERNAL_ERROR, <<"Cannot resolve messages">>
                                        )
                                    }
                            end;
                        _ ->
                            case edb:stack_frame_vars(Pid, FrameNo, ?MAX_TERM_SIZE) of
                                not_paused ->
                                    ?LOG_WARNING("Cannot resolve variables (not_paused) for pid ~p and frame_no ~p", [
                                        Pid, FrameNo
                                    ]),
                                    #{
                                        response => edb_dap:build_error_response(
                                            ?JSON_RPC_ERROR_INTERNAL_ERROR, <<"Cannot resolve variables (not_paused)">>
                                        )
                                    };
                                undefined ->
                                    ?LOG_WARNING("Cannot resolve variables (undefined) for pid ~p and frame_no ~p", [
                                        Pid, FrameNo
                                    ]),
                                    #{
                                        response => edb_dap:build_error_response(
                                            ?JSON_RPC_ERROR_INTERNAL_ERROR, <<"Cannot resolve variables (undefined)">>
                                        )
                                    };
                                {ok, Result} ->
                                    Variables =
                                        case Scope of
                                            locals ->
                                                [variable(Name, Value) || Name := Value <- maps:get(vars, Result, #{})];
                                            registers ->
                                                XRegs = unnamed_variables(<<"X">>, maps:get(xregs, Result, [])),
                                                YRegs = unnamed_variables(<<"Y">>, maps:get(yregs, Result, [])),
                                                XRegs ++ YRegs
                                        end,
                                    #{
                                        response => #{
                                            success => true,
                                            body => #{
                                                variables => Variables
                                            }
                                        }
                                    }
                            end
                    end;
                {error, not_found} ->
                    ?LOG_WARNING("Cannot find pid_frame for frame ~p", [FrameId]),
                    #{
                        response => edb_dap:build_error_response(
                            ?JSON_RPC_ERROR_INTERNAL_ERROR, <<"Cannot resolve variables (variable_ref_not_found)">>
                        )
                    }
            end;
        {error, not_found} ->
            ?LOG_WARNING("Cannot find frame for variables reference ~p", [VariablesReference]),
            #{
                response => edb_dap:build_error_response(
                    ?JSON_RPC_ERROR_INVALID_PARAMS, <<"Cannot resolve variables (frame_id_not_found)">>
                )
            }
    end.

-spec cap_by_size(term(), non_neg_integer()) -> edb:value().
cap_by_size(Term, MaxSize) ->
    Size = erts_debug:flat_size(Term),
    case Size > MaxSize of
        true ->
            {too_large, Size, MaxSize};
        false ->
            {value, Term}
    end.

-spec variable(binary(), edb:value()) -> edb_dap:variable().
variable(Name, Value) ->
    #{
        name => Name,
        value => variable_value(Value),
        variablesReference => 0
    }.

-spec unnamed_variables(binary(), [edb:value()]) -> [edb_dap:variable()].
unnamed_variables(Prefix, Values) ->
    Fun = fun(Value, {Acc, Count}) ->
        Name = edb:format("~s~p", [Prefix, Count]),
        {[variable(Name, Value) | Acc], Count + 1}
    end,
    {Registers, _Count} = lists:foldl(Fun, {[], 0}, Values),
    lists:reverse(Registers).

-spec variable_value(edb:value()) -> binary().
variable_value({too_large, Size, Max}) ->
    edb_dap:to_binary(io_lib:format("Too Large (~p vs ~p)", [Size, Max]));
variable_value({value, Value}) ->
    edb:format("~p", [Value]).

-spec thread(pid(), edb:process_info(), [edb_dap:thread()]) ->
    [edb_dap:thread()].
thread(Pid, Info, Acc) ->
    Id = edb_dap_id_mappings:pid_to_thread_id(Pid),
    [
        #{
            id => Id,
            name => edb_dap:thread_name(Pid, Info)
        }
        | Acc
    ].

-spec capabilities() -> edb_dap:capabilities().
capabilities() ->
    #{
        supportsConfigurationDoneRequest => false,
        supportsFunctionBreakpoints => false,
        supportsConditionalBreakpoints => false,
        supportsHitConditionalBreakpoints => false,
        supportsEvaluateForHovers => false,
        exceptionBreakpointFilters => [],
        supportsStepBack => false,
        supportsSetVariable => false,
        supportsRestartFrame => false,
        supportsGotoTargetsRequest => false,
        supportsStepInTargetsRequest => false,
        supportsCompletionsRequest => false,
        completionTriggerCharacters => [],
        supportsModulesRequest => false,
        additionalModuleColumns => [],
        supportedChecksumAlgorithms => [],
        supportsRestartRequest => false,
        supportsExceptionOptions => false,
        supportsValueFormattingOptions => false,
        supportsExceptionInfoRequest => false,
        supportTerminateDebuggee => false,
        supportSuspendDebuggee => false,
        supportsDelayedStackTraceLoading => false,
        supportsLoadedSourcesRequest => false,
        supportsLogPoints => false,
        supportsTerminateThreadsRequest => false,
        supportsSetExpression => false,
        supportsTerminateRequest => false,
        supportsDataBreakpoints => false,
        supportsReadMemoryRequest => false,
        supportsWriteMemoryRequest => false,
        supportsDisassembleRequest => false,
        supportsCancelRequest => false,
        supportsBreakpointLocationsRequest => false,
        supportsClipboardContext => false,
        supportsSteppingGranularity => false,
        supportsInstructionBreakpoints => false,
        supportsExceptionFilterOptions => false,
        supportsSingleThreadExecutionRequests => false,
        supportsDataBreakpointBytes => false,
        breakpointModes => []
    }.

-spec stack_trace(edb_dap_state:t(), edb_dap:stack_trace_request_arguments()) ->
    reaction(edb_dap:stack_trace_response()).
stack_trace(State, #{threadId := ThreadId}) ->
    StackFrames = #{stackFrames => stack_frames(State, ThreadId)},
    #{response => #{success => true, body => StackFrames}}.

-spec stack_frames(edb_dap_state:t(), edb_dap:thread_id()) -> [edb_dap:stack_frame()].
stack_frames(State, ThreadId) ->
    Context = edb_dap_state:get_context(State),
    case edb_dap_id_mappings:thread_id_to_pid(ThreadId) of
        {ok, Pid} ->
            case edb:stack_frames(Pid) of
                not_paused ->
                    ?LOG_WARNING("Client requesting stack frames for not_paused thread ~p", [ThreadId]),
                    [];
                {ok, Frames} ->
                    [edb_dap:stack_frame(Context, Pid, Frame) || Frame <- Frames]
            end;
        {error, not_found} ->
            ?LOG_WARNING("Cannot find pid for thread id ~p", [ThreadId]),
            []
    end.

-spec pause(edb_dap_state:t(), edb_dap:pause_request_arguments()) ->
    reaction(edb_dap:pause_response()).
pause(_State, _Args) ->
    ok = edb:pause(),
    #{response => #{success => true, body => #{}}}.

-spec continue(edb_dap_state:t(), edb_dap:continue_request_arguments()) ->
    reaction(edb_dap:continue_response()).
continue(_State, _Args) ->
    edb_dap_id_mappings:reset(),
    {ok, _} = edb:continue(),
    #{response => #{success => true, body => #{allThreadsContinued => true}}}.

-spec next(edb_dap_state:t(), edb_dap:next_request_arguments()) -> reaction(edb_dap:next_response()).
next(_State, #{threadId := ThreadId}) ->
    stepper(ThreadId, 'step-over').

-spec step_out(edb_dap_state:t(), edb_dap:step_out_request_arguments()) -> reaction(edb_dap:step_out_response()).
step_out(_State, #{threadId := ThreadId}) ->
    stepper(ThreadId, 'step-out').

-type stepper_response() :: #{
    success := boolean(),
    message => binary(),
    body := #{}
}.

-spec stepper(ThreadId, StepType) -> reaction(stepper_response()) when
    ThreadId :: edb_dap:thread_id(),
    StepType :: 'step-over' | 'step-out'.
stepper(ThreadId, StepType) ->
    StepFun =
        case StepType of
            'step-over' -> fun edb:step_over/1;
            'step-out' -> fun edb:step_out/1
        end,
    case edb_dap_id_mappings:thread_id_to_pid(ThreadId) of
        {ok, Pid} ->
            case StepFun(Pid) of
                ok ->
                    edb_dap_id_mappings:reset(),
                    #{response => #{success => true, body => #{}}};
                {error, not_paused} ->
                    #{
                        response => edb_dap:build_error_response(
                            ?JSON_RPC_ERROR_INVALID_PARAMS,
                            ~"Process is not stopped"
                        )
                    };
                {error, no_abstract_code} ->
                    #{
                        response => edb_dap:build_error_response(
                            ?ERROR_NOT_SUPPORTED,
                            ~"Module not compiled with debug_info"
                        )
                    };
                {error, {beam_analysis, Err}} ->
                    ?LOG_ERROR("beam analysis error: ~p", [Err]),
                    #{
                        response => edb_dap:build_error_response(
                            ?JSON_RPC_ERROR_INTERNAL_ERROR,
                            erlang:iolist_to_binary(io_lib:format("beam analysis failure: ~w", [Err]))
                        )
                    }
            end;
        {error, not_found} ->
            ?LOG_WARNING("Cannot find pid for thread id ~p", [ThreadId]),
            #{response => edb_dap:build_error_response(?JSON_RPC_ERROR_INTERNAL_ERROR, ~"Unknown threadId")}
    end.

-spec context(TargetNode, AttachTimeout, Cwd, StripSourcePrefix) -> edb_dap_state:context() when
    TargetNode :: edb_dap:target_node(),
    AttachTimeout :: non_neg_integer(),
    Cwd :: binary(),
    StripSourcePrefix :: binary().
context(TargetNode, AttachTimeout, Cwd, StripSourcePrefix) ->
    #{
        target_node => edb_dap_state:make_target_node(TargetNode),
        attach_timeout => AttachTimeout,
        cwd => Cwd,
        strip_source_prefix => StripSourcePrefix,
        cwd_no_source_prefix => edb_dap_utils:strip_suffix(Cwd, StripSourcePrefix)
    }.
