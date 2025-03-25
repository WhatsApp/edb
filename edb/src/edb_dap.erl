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
%%% % @format

-module(edb_dap).

%% erlfmt:ignore
% @fb-only
-moduledoc """
Support for the DAP Protocol

The Debug Adapter Protocol (DAP) defines the abstract protocol
used between a development tool (e.g. IDE or editor) and a
debugger, using JSON-RPC as the underlying transport protocol.

This module implements the types and functions required to
encode and decode messages to and from the DAP protocol.

For the full specification, please refer to:

https://microsoft.github.io/debug-adapter-protocol/specification
""".
-compile(warn_missing_spec_all).

-export([encode_frame/1, decode_frames/1, frame/1, unframe/1]).
-export([to_binary/1]).

-export_type([
    arguments/0,
    body/0,
    checksumAlgorithm/0,
    command/0,

    error_response/0,
    event/0,
    event_type/0,
    message/0,

    protocol_message_type/0,
    protocol_message/0,
    request/0,
    response/0,
    seq/0,
    source/0,
    stepping_granularity/0,

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
