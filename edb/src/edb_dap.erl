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

-export([encode_frame/1, decode_frames/1, frame/1, unframe/1]).
-export([build_error_response/2]).
-export([to_binary/1]).

-export_type([
    arguments/0,
    body/0,
    checksumAlgorithm/0,
    command/0,

    error_response/0,
    event/0,
    event_type/0,
    exited_event_body/0,
    initialized_event_body/0,
    message/0,

    protocol_message_type/0,
    protocol_message/0,
    request/0,
    response/0,
    seq/0,
    source/0,
    stepping_granularity/0,

    stopped_event_body/0,
    terminated_event_body/0,
    thread_id/0
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

-spec build_error_response(number(), binary()) -> error_response().
build_error_response(Id, Format) ->
    #{
        success => false,
        body => #{error => #{id => Id, format => Format}}
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

-type thread_id() :: number().

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

-type stepping_granularity() :: statement | line | instruction.

%%%---------------------------------------------------------------------------------
%%% Conversion functions
%%%---------------------------------------------------------------------------------

-spec to_binary(io_lib:chars()) -> binary().
to_binary(String) ->
    case unicode:characters_to_binary(String) of
        Binary when is_binary(Binary) -> Binary
    end.
