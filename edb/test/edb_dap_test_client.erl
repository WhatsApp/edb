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
%% @doc DAP Test Client
%%
%%      This module is used to test the DAP server End-to-End.
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(edb_dap_test_client).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).
-typing([eqwalizer]).

-behaviour(gen_server).

-export([start_link/2]).

-export([
    initialize/2,
    attach/2,
    launch/2,
    set_breakpoints/2,
    set_exception_breakpoints/2,
    configuration_done/1,
    threads/1,
    stack_trace/2,
    pause/2,
    continue/2,
    next/2,
    step_out/2,
    scopes/2,
    variables/2,
    disconnect/2
]).
-export([wait_for_event/2]).
-export([wait_for_reverse_request/2, respond_success/3]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).

-type awaitable_key() :: {event, edb_dap:event_type()} | {reverse_request, edb_dap:command()}.
-type awaitable() :: edb_dap:event() | edb_dap:request().

-type state() :: #{
    io := port(),
    buffer := binary(),
    requests := [{pos_integer(), gen_server:from()}],
    seq := pos_integer(),
    waiting := #{awaitable_key() => [gen_server:from()]},
    received := #{awaitable_key() => [awaitable()]}
}.

-export_type([client/0]).
-type client() :: pid().

-type request_no_seq() :: #{type := request, command := edb_dap:command(), arguments => edb_dap:arguments()}.

-spec start_link(file:filename_all(), [string()]) -> {ok, pid()}.
start_link(Executable, Args) ->
    {ok, _Pid} = gen_server:start_link(?MODULE, #{executable => Executable, args => Args}, []).

-spec initialize(client(), edb_dap_request_initialize:arguments()) -> edb_dap:response().
initialize(Client, Args) ->
    Request = #{type => request, command => ~"initialize", arguments => Args},
    call(Client, Request).

-spec attach(client(), edb_dap_request_attach:arguments()) -> edb_dap:response().
attach(Client, Args) ->
    Request = #{type => request, command => ~"attach", arguments => Args},
    call(Client, Request).

-spec launch(client(), edb_dap_request_launch:arguments()) -> edb_dap:response().
launch(Client, Args) ->
    Request = #{type => request, command => ~"launch", arguments => Args},
    call(Client, Request).

-spec set_exception_breakpoints(client(), edb_dap_request_set_exception_breakpoints:arguments()) -> edb_dap:response().
set_exception_breakpoints(Client, Args) ->
    Request = #{type => request, command => ~"setExceptionBreakpoints", arguments => Args},
    call(Client, Request).

-spec set_breakpoints(client(), edb_dap_request_set_breakpoints:arguments()) -> edb_dap:response().
set_breakpoints(Client, Args) ->
    Request = #{type => request, command => ~"setBreakpoints", arguments => Args},
    call(Client, Request).

-spec configuration_done(client()) -> edb_dap:response().
configuration_done(Client) ->
    Request = #{type => request, command => ~"configurationDone", arguments => #{}},
    call(Client, Request).

-spec threads(client()) -> edb_dap:response().
threads(Client) ->
    Request = #{type => request, command => ~"threads"},
    call(Client, Request).

-spec stack_trace(client(), edb_dap_request_stack_trace:arguments()) -> edb_dap:response().
stack_trace(Client, Args) ->
    Request = #{type => request, command => ~"stackTrace", arguments => Args},
    call(Client, Request).

-spec pause(client(), edb_dap_request_pause:arguments()) -> edb_dap:response().
pause(Client, Args) ->
    Request = #{type => request, command => ~"pause", arguments => Args},
    call(Client, Request).

-spec continue(client(), edb_dap_request_continue:arguments()) -> edb_dap:response().
continue(Client, Args) ->
    Request = #{type => request, command => ~"continue", arguments => Args},
    call(Client, Request).

-spec next(client(), edb_dap_request_next:arguments()) -> edb_dap:response().
next(Client, Args) ->
    Request = #{type => request, command => ~"next", arguments => Args},
    call(Client, Request).

-spec step_out(client(), edb_dap_request_step_out:arguments()) -> edb_dap:response().
step_out(Client, Args) ->
    Request = #{type => request, command => ~"stepOut", arguments => Args},
    call(Client, Request).

-spec scopes(client(), edb_dap_request_scopes:arguments()) -> edb_dap:response().
scopes(Client, Args) ->
    Request = #{type => request, command => ~"scopes", arguments => Args},
    call(Client, Request).

-spec variables(client(), edb_dap_request_variables:arguments()) -> edb_dap:response().
variables(Client, Args) ->
    Request = #{type => request, command => ~"variables", arguments => Args},
    call(Client, Request).

-spec disconnect(client(), edb_dap_request_disconnect:arguments()) -> edb_dap:response().
disconnect(Client, Args) ->
    Request = #{type => request, command => ~"disconnect", arguments => Args},
    call(Client, Request).

-spec wait_for_event(edb_dap:event_type(), client()) -> {ok, [edb_dap:event()]}.
wait_for_event(Type, Client) ->
    WaitTimeoutSecs = 10_000,
    call(Client, {wait_for, {event, Type}}, WaitTimeoutSecs).

-spec wait_for_reverse_request(edb_dap:command(), client()) -> {ok, [edb_dap:request()]}.
wait_for_reverse_request(Type, Client) ->
    WaitTimeoutSecs = 10_000,
    call(Client, {wait_for, {reverse_request, Type}}, WaitTimeoutSecs).

-spec respond_success(Client, ReverseRequest, ResponseBody) -> ok when
    Client :: client(),
    ReverseRequest :: edb_dap:request(),
    ResponseBody :: edb_dap:body().
respond_success(Client, ReverseRequest, ResponseBody) ->
    call(Client, {respond, true, ReverseRequest, ResponseBody}).

-spec init(#{executable := file:filename_all(), args := [string()]}) -> {ok, state()}.
init(#{executable := Executable, args := Args}) ->
    Opts = [{args, Args}, exit_status, eof, binary, stream, use_stdio],
    Port = open_port({spawn_executable, Executable}, Opts),
    State = #{
        io => Port,
        buffer => <<>>,
        requests => [],
        seq => 1,
        waiting => #{},
        received => #{}
    },
    {ok, State}.

-type call_request() ::
    {wait_for, awaitable_key()}
    | {respond, Success :: boolean(), edb_dap:request(), edb_dap:body()}
    | request_no_seq().

-spec call
    (client(), request_no_seq()) -> edb_dap:response();
    (client(), {wait_for, awaitable_key(), edb_dap:event_type()}) -> {ok, [awaitable()]};
    (client(), {respond, Success :: boolean(), edb_dap:request(), edb_dap:body()}) -> ok.
call(Client, Request) ->
    gen_server:call(Client, Request).

-spec call(client(), call_request(), timeout()) -> dynamic().
call(Client, Request, Timeout) ->
    gen_server:call(Client, Request, Timeout).

-spec handle_call(call_request(), gen_server:from(), state()) ->
    {noreply, state()} | {stop | reply, term(), state()}.
handle_call({wait_for, Key}, From, State0) ->
    something_wanted(Key, From, State0);
handle_call({respond, Success, Request, Body}, _From, #{io := IO, seq := StateSeq} = State0) ->
    #{seq := Seq, command := Command} = Request,
    Response = #{
        type => response,
        command => Command,
        success => Success,
        body => Body,
        request_seq => Seq,
        seq => StateSeq
    },
    Data = edb_dap:encode_frame(edb_dap:frame(Response)),
    send(IO, Data),
    State1 = State0#{seq => StateSeq + 1},
    {reply, ok, State1};
handle_call(#{command := _Command} = Request, From, #{io := IO, requests := Requests, seq := Seq} = State) ->
    Data = edb_dap:encode_frame(edb_dap:frame(Request#{seq => Seq})),
    send(IO, Data),
    {noreply, State#{seq => Seq + 1, requests => [{Seq, From} | Requests]}}.

-type cast_request() ::
    {event_received, edb_dap:event()}
    | {request_received, edb_dap:request()}
    | {response_received, edb_dap:response()}.

-spec cast(client(), cast_request()) -> ok.
cast(Client, Request) ->
    gen_server:cast(Client, Request).

-spec handle_cast(cast_request(), state()) -> {noreply, state()}.
handle_cast({event_received, Event}, State) ->
    something_received(Event, State);
handle_cast({request_received, Request}, State) ->
    something_received(Request, State);
handle_cast({response_received, Response}, #{requests := Requests} = State) ->
    #{request_seq := Seq} = Response,
    {value, {Seq, Client}, NewRequests} = lists:keytake(Seq, 1, Requests),
    ok = gen_server:reply(Client, Response),
    {noreply, State#{requests => NewRequests}}.

-spec handle_info(term(), state()) -> {noreply, state()} | {stop, normal, state()}.
handle_info({IO, {data, Data}}, #{io := IO, buffer := Buffer} = State) when
    is_binary(Data), is_port(IO)
->
    {Frames, NewBuffer} = edb_dap:decode_frames(<<Buffer/binary, Data/binary>>),
    [handle_message_async(edb_dap:unframe(Frame)) || Frame <- Frames],
    {noreply, State#{buffer => NewBuffer}};
handle_info({IO, {exit_status, _Status}}, #{io := IO} = State) when is_port(IO) ->
    {stop, normal, State};
handle_info({IO, eof}, #{io := IO} = State) ->
    erlang:halt(0),
    {noreply, State}.

-spec send(port(), binary()) -> ok.
send(IO, Data) ->
    IO ! {self(), {command, [Data]}},
    ok.

-spec handle_message_async(edb_dap:request() | edb_dap:response()) -> ok.
handle_message_async(#{type := request} = Message) ->
    cast(self(), {request_received, Message});
handle_message_async(#{type := response} = Message) ->
    cast(self(), {response_received, Message});
handle_message_async(#{type := event} = Message) ->
    cast(self(), {event_received, Message}).

-spec something_received(What, state()) -> {noreply, state()} when
    What :: awaitable().
something_received(What, State0) ->
    Key =
        case What of
            #{type := event, event := Type} -> {event, Type};
            #{type := request, command := Type} -> {reverse_request, Type}
        end,

    #{waiting := Waiting, received := Received} = State0,
    State1 =
        case maps:get(Key, Waiting, []) of
            [] ->
                NewReceived = Received#{Key => [What | maps:get(Key, Received, [])]},
                State0#{received => NewReceived};
            WaitingForThis ->
                [gen_server:reply(Client, {ok, [What]}) || Client <- WaitingForThis],
                State0#{waiting => Waiting#{Key => []}}
        end,
    {noreply, State1}.

-spec something_wanted(Key, From, state()) -> {noreply, state()} | {reply, {ok, [What]}, state()} when
    Key :: awaitable_key(),
    From :: gen_server:from(),
    What :: awaitable().
something_wanted(Key, From, State0) ->
    #{waiting := Waiting, received := Received} = State0,
    case maps:get(Key, Received, []) of
        [] ->
            NewWaiting = Waiting#{Key => [From | maps:get(Key, Waiting, [])]},
            {noreply, State0#{waiting => NewWaiting}};
        AlreadyReceived ->
            {reply, {ok, AlreadyReceived}, State0#{received := Received#{Key => []}}}
    end.
