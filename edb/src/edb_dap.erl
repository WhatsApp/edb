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
%%%---------------------------------------------------------------------------------
%% @doc Support for the DAP Protocol
%%
%%      The Debug Adapter Protocol (DAP) defines the abstract protocol
%%      used between a development tool (e.g. IDE or editor) and a
%%      debugger, using JSON-RPC as the underlying transport protocol.
%%
%%      This module implements the types and functions required to
%%      encode and decode messages to and from the DAP protocol.
%%
%%      For the full specification, please refer to:
%%
%%      https://microsoft.github.io/debug-adapter-protocol/specification
%% @end
%%%---------------------------------------------------------------------------------
%%% % @format

-module(edb_dap).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-include_lib("kernel/include/logger.hrl").

-export([encode_frame/1, decode_frames/1, frame/1, unframe/1]).
-export([build_error_response/2]).
-export([thread_name/2, stack_frame/3]).
-export([to_binary/1]).

-export_type([
    arguments/0,
    body/0,
    cancel_request_arguments/0,
    cancel_response/0,
    capabilities/0,
    command/0,
    continue_request_arguments/0,
    continue_response/0,
    disconnect_request_arguments/0,
    disconnect_response/0,
    error_response/0,
    event/0,
    event_type/0,
    exited_event_body/0,
    initialize_request_arguments/0,
    initialize_response/0,
    initialized_event_body/0,
    launch_request_arguments/0,
    launch_response/0,
    message/0,
    next_request_arguments/0,
    next_response/0,
    pause_request_arguments/0,
    pause_response/0,
    protocol_message_type/0,
    protocol_message/0,
    request/0,
    response/0,
    run_in_terminal_request_arguments/0,
    run_in_terminal_response/0,
    set_breakpoints_request_arguments/0,
    set_breakpoints_response/0,
    seq/0,
    stack_frame/0,
    stack_trace_request_arguments/0,
    stack_trace_response/0,
    stepping_granularity/0,
    step_out_request_arguments/0,
    step_out_response/0,
    stopped_event_body/0,
    target_node/0,
    terminated_event_body/0,
    thread/0,
    threads_request_arguments/0,
    thread_id/0,
    threads_response/0,
    scope/0,
    scopes_request_arguments/0,
    scopes_response/0,
    variable/0,
    variables_request_arguments/0,
    variables_response/0
]).

-export_type([frame/0]).

%%%---------------------------------------------------------------------------------
%%% Encode / Decode
%%%---------------------------------------------------------------------------------

-define(CONTENT_LENGTH, <<"Content-Length: ">>).
% 7 digits will allow max byte size ~10Mb
-define(MAX_CONTENT_LENGTH_LEN, byte_size(?CONTENT_LENGTH) + 7).

-opaque frame() :: {ContentLength :: pos_integer(), Payload :: binary()}.

-spec frame(request() | response() | event()) -> frame().
frame(Message) ->
    Body = iolist_to_binary(json:encode(Message)),
    Length = byte_size(Body),
    {Length, Body}.

-spec unframe(frame()) -> request() | response().
unframe({_Length, Body}) ->
    %% Convert binary keys to atoms
    %% Also convert binary values to atom if the key is the special <<"type">>
    Push = fun
        (<<"type">>, Value, Acc) ->
            [{type, binary_to_atom(Value)} | Acc];
        (Key, Value, Acc) ->
            [{binary_to_atom(Key), Value} | Acc]
    end,
    {Result, noacc, <<>>} = json:decode(Body, noacc, #{object_push => Push}),
    Result.

-spec encode_frame(frame()) -> binary().
encode_frame({Length, Body}) ->
    BinLength = integer_to_binary(Length),
    <<?CONTENT_LENGTH/binary, BinLength/binary, "\r\n\r\n", Body/binary>>.

-spec decode_frames(binary()) -> {[frame()], binary()}.
decode_frames(Data) ->
    decode_frames(Data, []).

-spec decode_frames(binary(), [frame()]) -> {[frame()], binary()}.
decode_frames(Data, Messages) ->
    case binary:split(Data, <<"\r\n\r\n">>) of
        [<<"Content-Length: ", BinLength/binary>>, Rest] when is_binary(Rest) ->
            Length = binary_to_integer(BinLength),
            case byte_size(Rest) < Length of
                true ->
                    {lists:reverse(Messages), Data};
                false ->
                    <<Body:Length/binary, NewData/binary>> = Rest,
                    decode_frames(NewData, [{Length, Body} | Messages])
            end;
        [Data] when byte_size(Data) =< ?MAX_CONTENT_LENGTH_LEN ->
            {lists:reverse(Messages), Data};
        _ ->
            error({invalid_data, Data})
    end.

%%%---------------------------------------------------------------------------------
%%% Base Protocol
%%%---------------------------------------------------------------------------------

-type protocol_message_type() :: request | response | event.
-type seq() :: pos_integer().
-type protocol_message() :: #{seq := seq(), type := protocol_message_type()}.
-type command() :: binary().
-type body() :: map().
-type arguments() :: map().
-type request() :: #{seq := seq(), type := request, command := command(), arguments => arguments()}.
-type event_type() :: binary().
-type event() :: #{seq := seq(), type := event, event := event_type(), body => body()}.
-type response() :: #{
    seq := seq(),
    type := response,
    request_seq := seq(),
    success := boolean(),
    command := command(),
    message => binary(),
    body => body()
}.
-type error_response() :: #{
    success := false,
    body => #{error => message()}
}.
-type message() :: #{
    id := number(),
    format := binary(),
    variables => #{
        binary() => binary()
    },
    sendTelemetry => boolean(),
    showUser => boolean(),
    url => binary(),
    urlLabel => binary()
}.
-type cancel_request_arguments() :: #{requestId => seq(), progressId => binary()}.
-type cancel_response() :: response().

-spec build_error_response(number(), binary()) -> error_response().
build_error_response(Id, Format) ->
    #{
        success => false,
        body => #{error => #{id => Id, format => Format}}
    }.

%%%---------------------------------------------------------------------------------
%%% Requests
%%%---------------------------------------------------------------------------------

%%% Initialize

-type initialize_request_arguments() :: #{
    clientID => binary(),
    clientName => binary(),
    adapterID := binary(),
    locale => binary(),
    linesStartAt1 => boolean(),
    columnsStartAt1 => boolean(),
    pathFormat => path | uri,
    supportsVariableType => boolean(),
    supportsVariablePaging => boolean(),
    supportsRunInTerminalRequest => boolean(),
    supportsMemoryReferences => boolean(),
    supportsProgressReporting => boolean(),
    supportsInvalidatedEvent => boolean(),
    supportsMemoryEvent => boolean(),
    supportsArgsCanBeInterpretedByShell => boolean(),
    supportsStartDebuggingRequest => boolean()
}.
-type initialize_response() :: #{
    success := boolean(),
    message => binary(),
    body => capabilities()
}.

%%% Launch
%%% Notice that, since launching is debugger/runtime specific, the arguments for this request are not part of the DAP specification itself.
-type target_node() :: #{
    name := binary(),
    cookie => binary(),
    type => binary()
}.
-type launch_request_arguments() :: #{
    launchCommand := #{
        cwd := binary(),
        command := binary(),
        arguments => [binary()],
        env => #{binary() => binary()}
    },
    targetNode := target_node(),
    stripSourcePath => binary()
}.
-type launch_response() :: #{
    success := boolean()
}.

%%% Disconnect
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Disconnect
-type disconnect_request_arguments() :: #{
    %  A value of true indicates that this `disconnect` request is part of a
    % restart sequence
    restart => boolean(),

    % Indicates whether the debuggee should be terminated when the debugger is
    % disconnected.
    % If unspecified, the debug adapter is free to do whatever it thinks is best.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportTerminateDebuggee` is true.
    terminateDebuggee => boolean(),

    % Indicates whether the debuggee should stay suspended when the debugger is
    % disconnected.
    % If unspecified, the debuggee should resume execution.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportSuspendDebuggee` is true.
    supportSuspendDebuggee => boolean()
}.
-type disconnect_response() :: #{
    success := boolean()
}.

%%% Set Breakpoints

-type set_breakpoints_request_arguments() :: #{
    source := source(),
    breakpoints => [sourceBreakpoint()],
    % Deprecated
    lines => [number()],
    sourceModified => boolean()
}.
-type set_breakpoints_response() :: #{
    success := boolean(),
    message => binary(),
    body => breakpoints()
}.

%%% Threads

-type threads_request_arguments() :: #{}.
-type threads_response() :: #{
    success := boolean(),
    body => threads()
}.

%%% Stack Trace
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_StackTrace
-type thread_id() :: number().
-type stack_trace_request_arguments() :: #{
    % Retrieve the stacktrace for this thread.
    threadId := thread_id(),
    % The index of the first frame to return; if omitted frames start at 0.
    startFrame => number(),
    % The maximum number of frames to return. If levels is not specified or 0,
    % all frames are returned.
    levels => number(),
    % Specifies details on how to format the stack frames.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportsValueFormattingOptions` is true.
    format => stack_frame_format()
}.
-type stack_frame_format() :: #{
    % Display the value in hex.
    hex => boolean(),
    % Displays parameters for the stack frame.
    parameters => boolean(),
    % Displays the types of parameters for the stack frame.
    parameterTypes => boolean(),
    % Displays the names of parameters for the stack frame.
    parameterNames => boolean(),
    % Displays the values of parameters for the stack frame.
    parameterValues => boolean(),
    % Displays the line number of the stack frame.
    line => boolean(),
    % Displays the module of the stack frame.
    module => boolean(),
    % Includes all stack frames, including those the debug adapter might otherwise hide.
    includeAll => boolean()
}.
-type stack_trace_response() :: #{
    success := boolean(),
    message => binary(),
    body := #{
        % The frames of the stack frame. If the array has length zero, there are no
        % stack frames available.
        % This means that there is no location information available.
        stackFrames := [stack_frame()],
        % The total number of frames available in the stack. If omitted or if
        % `totalFrames` is larger than the available frames, a client is expected
        % to request frames until a request returns less frames than requested
        % (which indicates the end of the stack). Returning monotonically
        % increasing `totalFrames` values for subsequent requests can be used to
        % enforce paging in the client.
        totalFrames => number()
    }
}.
-type stack_frame() :: #{
    % An identifier for the stack frame. It must be unique across all threads.
    % This id can be used to retrieve the scopes of the frame with the `scopes`
    % request or to restart the execution of a stack frame.
    id := number(),
    % The name of the stack frame, typically a method name.
    name := binary(),
    % The source of the frame.
    source => source(),
    % The line within the source of the frame. If the source attribute is missing
    % or doesn't exist, `line` is 0 and should be ignored by the client.
    line := number(),
    % Start position of the range covered by the stack frame. It is measured in
    % UTF-16 code units and the client capability `columnsStartAt1` determines
    % whether it is 0- or 1-based. If attribute `source` is missing or doesn't
    % exist, `column` is 0 and should be ignored by the client.
    column := number(),
    % The end line of the range covered by the stack frame.
    endLine => number(),
    % End position of the range covered by the stack frame. It is measured in
    % UTF-16 code units and the client capability `columnsStartAt1` determines
    % whether it is 0- or 1-based.
    endColumn => number(),
    % Indicates whether this frame can be restarted with the `restartFrame`
    % request. Clients should only use this if the debug adapter supports the
    % `restart` request and the corresponding capability `supportsRestartFrame`
    % is true. If a debug adapter has this capability, then `canRestart` defaults
    % to `true` if the property is absent.
    canRestart => boolean(),
    % A memory reference for the current instruction pointer in this frame.
    instructionPointerReference => binary(),
    % The module associated with this frame, if any.
    moduleId => number() | binary(),
    % A hint for how to present this frame in the UI.
    % A value of `label` can be used to indicate that the frame is an artificial
    % frame that is used as a visual label or separator. A value of `subtle` can
    % be used to change the appearance of a frame in a 'subtle' way.
    % Values: normal | label | subtle
    presentationHint => binary()
}.

%%% Pause
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Pause
-type pause_request_arguments() :: #{
    % Pause execution for this thread.
    threadId := thread_id()
}.
-type pause_response() :: #{
    success := boolean(),
    message => binary(),
    body := #{}
}.

%%% Continue
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Continue
-type continue_request_arguments() :: #{
    % Specifies the active thread. If the debug adapter supports single thread
    % execution (see `supportsSingleThreadExecutionRequests`) and the argument
    % `singleThread` is true, only the thread with this ID is resumed.
    threadId := thread_id(),
    % If this flag is true, execution is resumed only for the thread with given
    % `threadId`.
    singleThread => boolean()
}.
-type continue_response() :: #{
    success := boolean(),
    message => binary(),
    body := #{
        % The value true (or a missing property) signals to the client that all
        % threads have been resumed. The value false indicates that not all threads
        % were resumed.
        allThreadsContinued => boolean()
    }
}.

%%% Next
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Next
-type next_request_arguments() :: #{
    %  Specifies the thread for which to resume execution for one step (of the
    %  given granularity).
    threadId := number(),

    %  If this flag is true, all other suspended threads are not resumed.
    singleThread => boolean(),

    %  Stepping granularity. If no granularity is specified, a granularity of
    %  `statement` is assumed.
    granularity => stepping_granularity()
}.
-type next_response() ::
    #{
        success := boolean(),
        message => binary(),
        body := #{}
    }.

%%% Step-out
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_StepOut
-type step_out_request_arguments() :: #{
    %  Specifies the thread for which to resume execution for one step-out (of the
    %  given granularity).
    threadId := number(),

    %  If this flag is true, all other suspended threads are not resumed.
    singleThread => boolean(),

    %  Stepping granularity. If no granularity is specified, a granularity of
    %  `statement` is assumed.
    granularity => stepping_granularity()
}.
-type step_out_response() ::
    #{
        success := boolean(),
        message => binary(),
        body := #{}
    }.

%%% Scopes
-type scopes_request_arguments() :: #{
    % Retrieve the scopes for the stack frame identified by `frameId`. The
    % `frameId` must have been obtained in the current suspended state.
    frameId := number()
}.
-type scopes_response() :: #{
    success := boolean(),
    message => binary(),
    body := #{
        % The scopes of the stack frame. If the array has length zero, there are no
        % scopes available.
        scopes := [scope()]
    }
}.
-type scope() :: #{
    % Name of the scope such as 'Arguments', 'Locals', or 'Registers'. This
    % string is shown in the UI as is and can be translated.
    name := binary(),
    % A hint for how to present this scope in the UI. If this attribute is
    % missing, the scope is shown with a generic UI.
    % Values:
    %   'arguments': Scope contains method arguments.
    %   'locals': Scope contains local variables.
    %   'registers': Scope contains registers. Only a single `registers` scope
    %                should be returned from a `scopes` request.
    %   'returnValue': Scope contains one or more return values.
    presentationHint => binary(),
    % The variables of this scope can be retrieved by passing the value of
    % `variablesReference` to the `variables` request as long as execution
    % remains suspended.
    variablesReference := number(),
    % The number of named variables in this scope.
    % The client can use this information to present the variables in a paged UI
    % and fetch them in chunks.
    namedVariables => number(),
    % The number of indexed variables in this scope.
    % The client can use this information to present the variables in a paged UI
    % and fetch them in chunks.
    indexedVariables => number(),
    % If true, the number of variables in this scope is large or expensive to
    % retrieve.
    expensive := boolean(),
    % The source for this scope.
    source => source(),
    % The start line of the range covered by this scope.
    line => number(),
    % Start position of the range covered by the scope.
    % It is measured in UTF-16
    % code units and the client capability `columnsStartAt1` determines whether
    % it is 0- or 1-based.
    column => number(),
    % The end line of the range covered by this scope.
    endLine => number(),
    % End position of the range covered by the scope.
    % It is measured in UTF-16
    % code units and the client capability `columnsStartAt1` determines whether
    % it is 0- or 1-based.
    endColumn => number()
}.

%%% Variables
-type variables_request_arguments() :: #{
    % The variable for which to retrieve its children. The `variablesReference`
    % must have been obtained in the current suspended state.
    variablesReference := number(),
    % Filter to limit the child variables to either named or indexed. If omitted,
    % both types are fetched.
    % Possible values: 'indexed', 'named'
    filter => binary(),
    % The index of the first variable to return; if omitted children start at 0.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportsVariablePaging` is true.
    start => number(),
    % The number of variables to return. If count is missing or 0, all variables
    % are returned.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportsVariablePaging` is true.
    count => number(),
    % Specifies details on how to format the Variable values.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportsValueFormattingOptions` is true.
    format => value_format()
}.
-type value_format() :: #{
    % Display the value in hex
    hex => boolean()
}.
-type variables_response() :: #{
    success := boolean(),
    message => binary(),
    body := #{
        variables => [variable()]
    }
}.
-type variable() :: #{
    % The variable's name.
    name := binary(),
    % The variable's value.
    % This can be a multi-line text, e.g. for a function the body of a function.
    % For structured variables (which do not have a simple value), it is
    % recommended to provide a one-line representation of the structured object.
    % This helps to identify the structured object in the collapsed state when
    % its children are not yet visible.
    % An empty string can be used if no value should be shown in the UI.
    value := binary(),
    % The type of the variable's value. Typically shown in the UI when hovering
    % over the value.
    % This attribute should only be returned by a debug adapter if the
    % corresponding capability `supportsVariableType` is true.
    type => binary(),
    % Properties of a variable that can be used to determine how to render the
    % variable in the UI.
    presentationHint => variable_presentation_hint(),
    % The evaluatable name of this variable which can be passed to the `evaluate`
    % request to fetch the variable's value.
    evaluateName => binary(),
    % If `variablesReference` is > 0, the variable is structured and its children
    % can be retrieved by passing `variablesReference` to the `variables` request
    % as long as execution remains suspended.
    variablesReference := number(),
    % The number of named child variables.
    % The client can use this information to present the children in a paged UI
    % and fetch them in chunks.
    namedVariables => number(),
    % The number of indexed child variables.
    % The client can use this information to present the children in a paged UI
    % and fetch them in chunks.
    indexedVariables => number(),
    % A memory reference associated with this variable.
    % For pointer type variables, this is generally a reference to the memory
    % address contained in the pointer.
    % For executable data, this reference may later be used in a `disassemble`
    % request.
    % This attribute may be returned by a debug adapter if corresponding
    % capability `supportsMemoryReferences` is true.
    memoryReference => binary(),
    % A reference that allows the client to request the location where the
    % variable is declared. This should be present only if the adapter is likely
    % to be able to resolve the location.
    % This reference shares the same lifetime as the `variablesReference`.
    declarationLocationReference => number(),
    % A reference that allows the client to request the location where the
    % variable's value is declared. For example, if the variable contains a
    % function pointer, the adapter may be able to look up the function's
    % location. This should be present only if the adapter is likely to be able
    % to resolve the location.
    % This reference shares the same lifetime as the `variablesReference`.
    valueLocationReference => number()
}.
-type variable_presentation_hint() :: #{
    % The kind of variable. Before introducing additional values, try to use the
    % listed values.
    % Values:
    % 'property': Indicates that the object is a property.
    % 'method': Indicates that the object is a method.
    % 'class': Indicates that the object is a class.
    % 'data': Indicates that the object is data.
    % 'event': Indicates that the object is an event.
    % 'baseClass': Indicates that the object is a base class.
    % 'innerClass': Indicates that the object is an inner class.
    % 'interface': Indicates that the object is an interface.
    % 'mostDerivedClass': Indicates that the object is the most derived class.
    % 'virtual': Indicates that the object is virtual, that means it is a
    % synthetic object introduced by the adapter for rendering purposes, e.g. an
    % index range for large arrays.
    % 'dataBreakpoint': Deprecated: Indicates that a data breakpoint is
    % registered for the object. The `hasDataBreakpoint` attribute should
    % generally be used instead.
    % etc.
    kind => binary(),
    % Set of attributes represented as an array of strings. Before introducing
    % additional values, try to use the listed values.
    % Values:
    % 'static': Indicates that the object is static.
    % 'constant': Indicates that the object is a constant.
    % 'readOnly': Indicates that the object is read only.
    % 'rawString': Indicates that the object is a raw string.
    % 'hasObjectId': Indicates that the object can have an Object ID created for
    % it. This is a vestigial attribute that is used by some clients; 'Object
    % ID's are not specified in the protocol.
    % 'canHaveObjectId': Indicates that the object has an Object ID associated
    % with it. This is a vestigial attribute that is used by some clients;
    % 'Object ID's are not specified in the protocol.
    % 'hasSideEffects': Indicates that the evaluation had side effects.
    % 'hasDataBreakpoint': Indicates that the object has its value tracked by a
    % data breakpoint.
    % etc.
    attributes => [binary()],
    % Visibility of variable. Before introducing additional values, try to use
    % the listed values.
    % Values: 'public', 'private', 'protected', 'internal', 'final', etc.
    visibility => binary(),
    % If true, clients can present the variable with a UI that supports a
    % specific gesture to trigger its evaluation.
    % This mechanism can be used for properties that require executing code when
    % retrieving their value and where the code execution can be expensive and/or
    % produce side-effects. A typical example are properties based on a getter
    % function.
    % Please note that in addition to the `lazy` flag, the variable's
    % `variablesReference` is expected to refer to a variable that will provide
    % the value through another `variable` request.
    lazy => boolean()
}.

%%%---------------------------------------------------------------------------------
%%% Reverse Requests
%%%---------------------------------------------------------------------------------

%%% Run In Terminal

-type run_in_terminal_request_arguments() :: #{
    % integrated | external
    kind => binary(),
    title => binary(),
    cwd => binary(),
    % The first argument is the command to run
    args := [binary()],
    env => #{binary() => binary()},
    argsCanBeInterpretedByShell => boolean()
}.
-type run_in_terminal_response() :: #{
    success := boolean(),
    message => binary(),
    body := #{
        % Currently not sent by VS Code. See https://github.com/microsoft/vscode/issues/61640#issuecomment-432696354
        processId => number(),
        shellProcessId => number()
    }
}.

%%%---------------------------------------------------------------------------------
%%% Events
%%%---------------------------------------------------------------------------------

%%% Initialized
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Events_Initialized
-type initialized_event_body() :: #{}.

%%% Exited
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Events_Exited
-type exited_event_body() :: #{
    % The exit code returned from the debuggee.
    exitCode := number()
}.

%%% Stopped
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Events_Stopped
-type stopped_event_body() :: #{
    % The reason for the event. For backward compatibility this string is shown in the UI if the
    % `description` attribute is missing (but it must not be translated).
    % Values: 'step' | 'breakpoint' | 'exception' | 'pause' | 'entry' | 'goto' | 'function breakpoint' |
    % 'data breakpoint' | 'instruction breakpoint'
    reason := binary(),
    % The full reason for the event, e.g. 'Paused on exception'. This string is shown in the UI as is and can be translated.
    description => binary(),
    % The thread which was stopped
    threadId => thread_id(),
    % A value of `true` hints to the client that this event should not change the focus
    preserveFocusHint => boolean(),
    % Additional information. E.g. if `reason` is `exception`, text contains the exception name. This string is shown in the UI.
    text => binary(),
    % If `allThreadsStopped` is `true`, a debug adapter can announce that all threads have stopped.
    % - The client should use this information to enable that all threads can be expanded to access their stacktraces.
    % - If the attribute is missing or `false`, only the thread with the given `threadId` can be expanded.
    allThreadsStopped => boolean(),
    % Ids of the breakpoints that triggered the event. In most cases there is only a single breakpoint but here are some examples for multiple
    % breakpoints:
    % - Different types of breakpoints map to the same location.
    % - Multiple source breakpoints get collapsed to the same instruction by the compiler/runtime.
    % - Multiple function breakpoints with different function names map to the same location.
    hitBreakpointIds => [number()]
}.

%%% Terminated
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Events_Terminated
-type terminated_event_body() :: #{
    % A debug adapter may set `restart` to true (or to an arbitrary object) to
    % request that the client restarts the session.
    % The value is not interpreted by the client and passed unmodified as an
    % attribute `__restart` to the `launch` and `attach` requests.
    restart => true | map()
}.

%%%---------------------------------------------------------------------------------
%%% Basic Types (used by requests and responses)
%%%---------------------------------------------------------------------------------

-type capabilities() :: #{
    supportsConfigurationDoneRequest => boolean(),
    supportsFunctionBreakpoints => boolean(),
    supportsConditionalBreakpoints => boolean(),
    supportsHitConditionalBreakpoints => boolean(),
    supportsEvaluateForHovers => boolean(),
    exceptionBreakpointFilters => [exceptionBreakpointsFilter()],
    supportsStepBack => boolean(),
    supportsSetVariable => boolean(),
    supportsRestartFrame => boolean(),
    supportsGotoTargetsRequest => boolean(),
    supportsStepInTargetsRequest => boolean(),
    supportsCompletionsRequest => boolean(),
    completionTriggerCharacters => [binary()],
    supportsModulesRequest => boolean(),
    additionalModuleColumns => [columnDescriptor()],
    supportedChecksumAlgorithms => [checksumAlgorithm()],
    supportsRestartRequest => boolean(),
    supportsExceptionOptions => boolean(),
    supportsValueFormattingOptions => boolean(),
    supportsExceptionInfoRequest => boolean(),
    supportTerminateDebuggee => boolean(),
    supportSuspendDebuggee => boolean(),
    supportsDelayedStackTraceLoading => boolean(),
    supportsLoadedSourcesRequest => boolean(),
    supportsLogPoints => boolean(),
    supportsTerminateThreadsRequest => boolean(),
    supportsSetExpression => boolean(),
    supportsTerminateRequest => boolean(),
    supportsDataBreakpoints => boolean(),
    supportsReadMemoryRequest => boolean(),
    supportsWriteMemoryRequest => boolean(),
    supportsDisassembleRequest => boolean(),
    supportsCancelRequest => boolean(),
    supportsBreakpointLocationsRequest => boolean(),
    supportsClipboardContext => boolean(),
    supportsSteppingGranularity => boolean(),
    supportsInstructionBreakpoints => boolean(),
    supportsExceptionFilterOptions => boolean(),
    supportsSingleThreadExecutionRequests => boolean(),
    supportsDataBreakpointBytes => boolean(),
    breakpointModes => [breakpointMode()]
}.
-type breakpointMode() :: #{
    mode := binary(), label := binary(), description => binary(), appliesTo => [breakpointModeApplicability()]
}.
-type breakpointModeApplicability() :: source | exception | data | instruction.
-type columnDescriptor() :: #{
    attributeName := binary(),
    label := string(),
    format => binary(),
    type => string | number | boolean | unixTimestampUTC,
    width => number()
}.
-type exceptionBreakpointsFilter() :: #{
    filter := binary(),
    label := binary(),
    description => binary(),
    default => boolean(),
    supportsCondition => boolean(),
    conditionDescription => binary()
}.
-type breakpoints() :: #{breakpoints := [breakpoint()]}.
-type breakpoint() :: #{
    id => number(),
    verified := boolean(),
    message => binary(),
    source => source(),
    line => number(),
    column => number(),
    endLine => number(),
    endColumn => number(),
    instructionReference => binary(),
    offset => number(),
    reason => binary()
}.
-type sourceBreakpoint() :: #{
    line := number(),
    column => number(),
    condition => binary(),
    hitCondition => binary(),
    logMessage => binary(),
    mode => binary()
}.
%% erlfmt:ignore
-type checksumAlgorithm() :: binary(). % 'MD5' | 'SHA1' | 'SHA256' | timestamp.
-type source() :: #{
    name => binary(),
    path => binary(),
    sourceReference => number(),
    presentationHint => binary(),
    origin => binary(),
    sources => [source()],
    adapterData => map(),
    checksums => [checksum()]
}.
-type checksum() :: #{
    algorithm := checksumAlgorithm(),
    checksum := binary()
}.
-type threads() :: #{
    threads := [thread()]
}.
-type thread() :: #{
    id := number(),
    name := binary()
}.

-type stepping_granularity() :: statement | line | instruction.

%%%---------------------------------------------------------------------------------
%%% Conversion functions
%%%---------------------------------------------------------------------------------

-spec thread_name(pid(), edb:process_info()) -> binary().
thread_name(Pid, Info) ->
    ProcessNameLabel = process_name_label(Pid, Info),
    MessageQueueLenLabel = message_queue_len_label(Info),
    edb:format(~"~s~s", [ProcessNameLabel, MessageQueueLenLabel]).

-spec process_name_label(pid(), edb:process_info()) -> binary().
process_name_label(Pid, Info) ->
    case maps:get(registered_name, Info, undefined) of
        undefined ->
            edb:format(~"~p", [Pid]);
        RegisteredName ->
            edb:format(~"~p (~p)", [Pid, RegisteredName])
    end.

-spec message_queue_len_label(edb:process_info()) -> binary().
message_queue_len_label(Info) ->
    case maps:get(message_queue_len, Info, 0) of
        0 ->
            ~"";
        N ->
            edb:format(~" (messages: ~p)", [N])
    end.

-spec stack_frame(edb_dap_state:context(), pid(), edb:stack_frame()) -> stack_frame().
stack_frame(Context, Pid, #{id := Id, mfa := {M, F, A}, source := FilePath, line := Location}) ->
    Name = to_binary(io_lib:format("~p:~p/~p", [M, F, A])),
    Line =
        case Location of
            undefined -> 0;
            L when is_integer(L) -> L
        end,
    FrameId = edb_dap_id_mappings:pid_frame_to_frame_id(#{pid => Pid, frame_no => Id}),
    Frame = #{id => FrameId, name => Name, line => Line, column => 0},
    case FilePath of
        undefined ->
            Frame;
        _ when is_list(FilePath) ->
            Frame#{source => source(Context, to_binary(FilePath))}
    end;
stack_frame(Context, Pid, #{id := Id, mfa := 'unknown'}) ->
    FrameId = edb_dap_id_mappings:pid_frame_to_frame_id(#{pid => Pid, frame_no => Id}),
    #{target_node := #{name := Node}} = Context,
    Info =
        % elp:ignore W0014 (cross_node_eval) -- debugging support @fb-only
        try erpc:call(Node, erlang, process_info, [Pid, [current_stacktrace, current_function, registered_name]]) of
            ProcessInfo -> ProcessInfo
        catch
            ErrClass:ErrMsg -> {ErrClass, ErrMsg}
        end,
    ?LOG_WARNING("Unknown MFA for ~p frame ~p. Info:~p", [Pid, Id, Info]),
    #{id => FrameId, name => <<"???">>, line => 0, column => 0}.

-spec source(edb_dap_state:context(), binary()) -> source().
source(#{cwd_no_source_prefix := CwdNoSourcePrefix}, FilePath0) ->
    FileName = filename:basename(FilePath0, ".erl"),
    FilePath =
        case filename:pathtype(FilePath0) of
            absolute ->
                FilePath0;
            _ ->
                filename:join(CwdNoSourcePrefix, FilePath0)
        end,
    #{name => FileName, path => FilePath}.

-spec to_binary(io_lib:chars()) -> binary().
to_binary(String) ->
    case unicode:characters_to_binary(String) of
        Binary when is_binary(Binary) -> Binary
    end.
