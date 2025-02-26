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

%%% % @format

-module(edb_dap_request_stack_trace).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

-include_lib("kernel/include/logger.hrl").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_StackTrace
-type arguments() :: #{
    % Retrieve the stacktrace for this thread.
    threadId := edb_dap:thread_id(),
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

-type response_body() :: #{
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
}.

-type stack_frame() :: #{
    % An identifier for the stack frame. It must be unique across all threads.
    % This id can be used to retrieve the scopes of the frame with the `scopes`
    % request or to restart the execution of a stack frame.
    id := number(),
    % The name of the stack frame, typically a method name.
    name := binary(),
    % The source of the frame.
    source => edb_dap:source(),
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

-export_type([arguments/0, response_body/0]).
-export_type([stack_frame_format/0, stack_frame/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()}.
parse_arguments(Args) ->
    {ok, Args}.

-spec handle(State, Args) -> edb_dap_request:reaction(response_body()) when
    State :: edb_dap_state:t(),
    Args :: arguments().
handle(State, #{threadId := ThreadId}) ->
    StackFrames = #{stackFrames => stack_frames(State, ThreadId)},
    #{response => #{success => true, body => StackFrames}}.

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-spec stack_frames(edb_dap_state:t(), edb_dap:thread_id()) -> [stack_frame()].
stack_frames(State, ThreadId) ->
    Context = edb_dap_state:get_context(State),
    case edb_dap_id_mappings:thread_id_to_pid(ThreadId) of
        {ok, Pid} ->
            case edb:stack_frames(Pid) of
                not_paused ->
                    ?LOG_WARNING("Client requesting stack frames for not_paused thread ~p", [ThreadId]),
                    [];
                {ok, Frames} ->
                    [stack_frame(Context, Pid, Frame) || Frame <- Frames]
            end;
        {error, not_found} ->
            ?LOG_WARNING("Cannot find pid for thread id ~p", [ThreadId]),
            []
    end.

-spec stack_frame(edb_dap_state:context(), pid(), edb:stack_frame()) -> stack_frame().
stack_frame(Context, Pid, #{id := Id, mfa := {M, F, A}, source := FilePath, line := Location}) ->
    Name = edb_dap:to_binary(io_lib:format("~p:~p/~p", [M, F, A])),
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
            Frame#{source => source(Context, edb_dap:to_binary(FilePath))}
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

-spec source(edb_dap_state:context(), binary()) -> edb_dap:source().
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
