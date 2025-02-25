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
%% @doc Transport layer of the DAP server
%%      This module deals with serialization/deserialization, sequencing
%%      and other low-level details of the DAP frontend for the edb Erlang
%%      debugger.
%%
%%      For the actual handling of requests, etc. see the edb_dap_server
%%      module.
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(edb_dap_transport).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(gen_server).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([start_link/0]).
-export([send_response/2, send_reverse_request/2, send_event/2]).

%% gen_server callbacks
-export([
    init/1,
    terminate/2,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).
-define(SERVER, ?MODULE).

-type state() :: #{
    io := port(),
    buffer := binary(),
    seq := pos_integer()
}.

-type action() ::
    {event, edb_dap:event_type(), edb_dap:arguments()}
    | {reverse_request, edb_dap:command(), edb_dap:body()}
    | terminate.
-export_type([action/0]).

%%%---------------------------------------------------------------------------------
%%% API
%%%---------------------------------------------------------------------------------

-spec start_link() -> {ok, pid()}.
start_link() ->
    {ok, _Pid} = gen_server:start_link({local, ?SERVER}, ?MODULE, noargs, []).

-spec send_response(OriginalRequest, Response) -> ok when
    OriginalRequest :: edb_dap:request(),
    Response :: map().
send_response(OriginalRequest, Response) ->
    #{command := Command, seq := RequestSeq} = OriginalRequest,
    Payload = Response#{type => response, request_seq => RequestSeq, command => Command},
    ok = gen_server:cast(?SERVER, {send, Payload}).

-spec send_reverse_request(Command, Arguments) -> ok when
    Command :: edb_dap:command(),
    Arguments :: edb_dap:arguments().
send_reverse_request(Command, Args) ->
    Payload = #{
        type => request,
        command => Command,
        arguments => Args
    },
    ok = gen_server:cast(?SERVER, {send, Payload}).

-spec send_event(EventType, EventBody) -> ok when
    EventType :: edb_dap:event_type(),
    EventBody :: edb_dap:body().
send_event(Type, Body) ->
    Payload = #{
        type => event,
        event => Type,
        body => Body
    },
    ok = gen_server:cast(?SERVER, {send, Payload}).

%%%---------------------------------------------------------------------------------
%%% Callbacks
%%%---------------------------------------------------------------------------------

-spec init(noargs) -> {ok, state()}.
init(noargs) ->
    %% Open stdin/out as a port, requires node to be started with -noinput
    %% We do this to avoid the overhead of the normal Erlang stdout/in stack
    %% which is very significant for raw binary data, mostly because it's prepared
    %% to work with unicode input and does multiple encoding/decoding rounds for raw bytes
    Port = open_port({fd, 0, 1}, [eof, binary, stream]),
    State = #{io => Port, buffer => <<>>, seq => 1},
    {ok, State}.

-spec terminate(Reason :: term(), state()) -> ok.
terminate(Reason, _State) ->
    case Reason of
        normal ->
            case application:get_env(on_exit) of
                undefined ->
                    ok;
                {ok, Action} ->
                    Action()
            end;
        _ ->
            ok
    end.

-spec handle_call(term(), term(), state()) -> {noreply, state()}.
handle_call(_Request, _From, State) ->
    {noreply, State}.

-spec handle_cast(Request, state()) -> {noreply, state()} when
    Request :: {send, map()}.
handle_cast({send, Payload}, State) ->
    {noreply, send(Payload, State)};
handle_cast(_, State) ->
    {noreply, State}.

-spec handle_info(InfoMessage, state()) -> {noreply, state()} | {stop, Reason :: normal, state()} when
    InfoMessage :: {port(), {data, binary()} | eof}.
handle_info(PortEvent = {IO, _}, State = #{io := IO}) when is_port(IO) ->
    handle_port_event(PortEvent, State);
handle_info(Unexpected, State) ->
    ?LOG_WARNING("Unexpected message: ~p", [Unexpected]),
    {noreply, State}.

-spec handle_port_event(Event, state()) -> {noreply, state()} | {stop, normal, state()} when
    Event :: {port(), {data, binary()}} | {port(), eof}.
handle_port_event({IO, {data, Data}}, State0 = #{io := IO, buffer := Buffer}) ->
    ?LOG_DEBUG("Received data: ~p (buffer: ~p)", [Data, Buffer]),
    {Frames, NewBuffer} = edb_dap:decode_frames(<<Buffer/binary, Data/binary>>),
    [forward_incoming(edb_dap:unframe(Frame)) || Frame <- Frames],
    State1 = State0#{buffer => NewBuffer},
    {noreply, State1};
handle_port_event({IO, eof}, State0 = #{io := IO}) ->
    ?LOG_INFO("Connection closed, exiting..."),
    {stop, normal, State0}.

-spec forward_incoming(Message) -> ok when
    Message :: edb_dap:request() | edb_dap:response().
forward_incoming(Message) ->
    ?LOG_INFO("==> ~p", [Message]),
    edb_dap_server:handle_message(Message).

-spec send(Payload, State) -> State when
    Payload :: map(),
    State :: state().
send(Payload, State0 = #{io := IO, seq := Seq}) ->
    ?LOG_INFO("<== ~p", [Payload]),
    Data = edb_dap:encode_frame(edb_dap:frame(Payload#{seq => Seq})),
    ?LOG_DEBUG("Sending data: ~p", [Data]),
    IO ! {self(), {command, [Data]}},
    State1 = State0#{seq => Seq + 1},
    State1.
