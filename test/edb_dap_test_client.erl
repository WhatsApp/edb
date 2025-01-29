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

-behaviour(gen_server).

-export([start_link/2]).

-export([
    initialize/2,
    wait_for_event/2,
    launch/2,
    set_breakpoints/2,
    threads/2,
    stack_trace/2,
    pause/2,
    continue/2,
    next/2,
    step_out/2,
    scopes/2,
    variables/2,
    disconnect/2
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).

-type state() :: #{
    io := port(),
    buffer := binary(),
    requests := [{pos_integer(), gen_server:from()}],
    seq := pos_integer(),
    waiting := #{binary => [gen_server:from()]},
    events := #{binary() => [edb_dap:event()]}
}.
-type client() :: pid().

-spec start_link(file:filename_all(), [string()]) -> {ok, pid()}.
start_link(Executable, Args) ->
    {ok, _Pid} = gen_server:start_link(?MODULE, #{executable => Executable, args => Args}, []).

-spec initialize(client(), edb_dap:initialize_request_arguments()) -> ok.
initialize(Client, Args) ->
    Request = #{type => request, command => <<"initialize">>, arguments => Args},
    gen_server:call(Client, Request).

-spec wait_for_event(edb_dap:event_type(), client()) -> ok.
wait_for_event(Type, Client) ->
    WaitTimeoutSecs = 10_000,
    gen_server:call(Client, {'$wait_for_event', Type}, WaitTimeoutSecs).

-spec launch(client(), edb_dap:launch_request_arguments()) -> ok.
launch(Client, Args) ->
    Request = #{type => request, command => <<"launch">>, arguments => Args},
    gen_server:call(Client, Request).

-spec set_breakpoints(client(), edb_dap:set_breakpoints_arguments()) -> ok.
set_breakpoints(Client, Args) ->
    Request = #{type => request, command => <<"setBreakpoints">>, arguments => Args},
    gen_server:call(Client, Request).

-spec threads(client(), edb_dap:threads_arguments()) -> ok.
threads(Client, Args) ->
    Request = #{type => request, command => <<"threads">>, arguments => Args},
    gen_server:call(Client, Request).

-spec stack_trace(client(), edb_dap:stack_trace_request_arguments()) -> ok.
stack_trace(Client, Args) ->
    Request = #{type => request, command => <<"stackTrace">>, arguments => Args},
    gen_server:call(Client, Request).

-spec pause(client(), edb_dap:pause_request_arguments()) -> ok.
pause(Client, Args) ->
    Request = #{type => request, command => <<"pause">>, arguments => Args},
    gen_server:call(Client, Request).

-spec continue(client(), edb_dap:continue_request_arguments()) -> ok.
continue(Client, Args) ->
    Request = #{type => request, command => <<"continue">>, arguments => Args},
    gen_server:call(Client, Request).

-spec next(client(), edb_dap:next_request_arguments()) -> ok.
next(Client, Args) ->
    Request = #{type => request, command => <<"next">>, arguments => Args},
    gen_server:call(Client, Request).

-spec step_out(client(), edb_dap:step_out_request_arguments()) -> ok.
step_out(Client, Args) ->
    Request = #{type => request, command => <<"stepOut">>, arguments => Args},
    gen_server:call(Client, Request).

-spec scopes(client(), edb_dap:scopes_request_arguments()) -> ok.
scopes(Client, Args) ->
    Request = #{type => request, command => <<"scopes">>, arguments => Args},
    gen_server:call(Client, Request).

-spec variables(client(), edb_dap:variables_request_arguments()) -> ok.
variables(Client, Args) ->
    Request = #{type => request, command => <<"variables">>, arguments => Args},
    gen_server:call(Client, Request).

-spec disconnect(client(), edb_dap:disonnect_request_arguments()) -> ok.
disconnect(Client, Args) ->
    Request = #{type => request, command => <<"disconnect">>, arguments => Args},
    gen_server:call(Client, Request).

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
        events => #{}
    },
    {ok, State}.

-spec handle_call({'$wait_for_event', edb_dap:event_type()} | edb_dap:request(), gen_server:from(), state()) ->
    {noreply, state()} | {stop | reply, term(), state()}.
handle_call({'$wait_for_event', Type}, From, #{waiting := Waiting, events := EventsReceived} = State) ->
    case maps:get(Type, EventsReceived, []) of
        [] ->
            NewWaiting = Waiting#{Type => [From | maps:get(Type, Waiting, [])]},
            {noreply, State#{waiting => NewWaiting}};
        Events ->
            {reply, {ok, Events}, State#{events := EventsReceived#{Type => []}}}
    end;
handle_call(#{command := _Command} = Request, From, #{io := IO, requests := Requests, seq := Seq} = State) ->
    Data = edb_dap:encode_frame(edb_dap:frame(Request#{seq => Seq})),
    send(IO, Data),
    {noreply, State#{seq => Seq + 1, requests => [{Seq, From} | Requests]}}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Request, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info({IO, {data, Data}}, #{io := IO, buffer := Buffer} = State) when
    is_binary(Data), is_port(IO)
->
    {Frames, NewBuffer} = edb_dap:decode_frames(<<Buffer/binary, Data/binary>>),
    [handle_message_async(edb_dap:unframe(Frame)) || Frame <- Frames],
    {noreply, State#{buffer => NewBuffer}};
handle_info({IO, {exit_status, _Status}}, #{io := IO} = State) when is_port(IO) ->
    {stop, normal, State};
handle_info({handle_event, #{event := Type} = Event}, #{waiting := Waiting, events := Events} = State) ->
    case maps:get(Type, Waiting, []) of
        [] ->
            NewEvents = Events#{Type => [Event | maps:get(Type, Events, [])]},
            {noreply, State#{events => NewEvents}};
        WaitingForEvent ->
            [gen_server:reply(Client, {ok, [Event]}) || Client <- WaitingForEvent],
            {noreply, State#{waiting => Waiting#{Type => []}}}
    end;
handle_info({handle_request, Request}, #{io := IO, seq := StateSeq} = State) ->
    #{seq := Seq, command := Command} = Request,
    % Just send empty responses to reverse requests for now
    Response = #{
        type => response, command => Command, success => true, body => #{}, request_seq => Seq, seq => StateSeq
    },
    Data = edb_dap:encode_frame(edb_dap:frame(Response)),
    send(IO, Data),
    {noreply, State};
handle_info({handle_response, Response}, #{requests := Requests} = State) ->
    #{request_seq := Seq} = Response,
    {value, {Seq, Client}, NewRequests} = lists:keytake(Seq, 1, Requests),
    ok = gen_server:reply(Client, Response),
    {noreply, State#{requests => NewRequests}};
handle_info({IO, eof}, #{io := IO} = State) ->
    erlang:halt(0),
    {noreply, State}.

-spec send(port(), binary()) -> ok.
send(IO, Data) ->
    IO ! {self(), {command, [Data]}},
    ok.

-spec handle_message_async(edb_dap:request() | edb_dap:response()) -> ok.
handle_message_async(#{type := request} = Message) ->
    self() ! {handle_request, Message},
    ok;
handle_message_async(#{type := response} = Message) ->
    self() ! {handle_response, Message},
    ok;
handle_message_async(#{type := event} = Message) ->
    self() ! {handle_event, Message},
    ok.
