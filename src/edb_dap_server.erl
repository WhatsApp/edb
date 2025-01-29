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
%% @doc DAP server
%%      A simple debug adapter which can be used to interface with
%%      the edb Erlang debugger.
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(edb_dap_server).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(gen_server).

-include_lib("kernel/include/logger.hrl").
-include("edb_dap.hrl").

-export([start_link/0]).

%% gen_server callbacks
-export([
    init/1,
    terminate/2,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).
-define(SERVER, ?MODULE).

-type transport_state() :: #{
    io := port(),
    buffer := binary(),
    seq := pos_integer()
}.
-type state() :: {transport_state(), edb_dap_state:t()}.

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
    Transport = #{io => Port, buffer => <<>>, seq => 1},
    DAPState = edb_dap_state:new(),
    {ok, {Transport, DAPState}}.

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

-spec handle_call(term(), term(), state()) -> {noreply, state()} | {stop | reply, term(), state()}.
handle_call(_Request, _From, State) ->
    {noreply, State}.

-spec handle_cast(Request, state()) -> {noreply, state()} | {stop, normal, state()} when
    Request ::
        {handle_message, edb_dap:request() | edb_dap:response()}
        | terminate.
handle_cast(
    {handle_message, #{type := request, seq := RequestSeq, command := Command} = Request}, {Transport, DAPState}
) ->
    ?LOG_DEBUG("Handle request: ~p", [Request]),
    {NewTransport, NewDAPState} =
        case edb_dap_state:is_initialized(DAPState) of
            false when Command =/= <<"initialize">> ->
                Response = edb_dap:build_error_response(
                    ?ERROR_SERVER_NOT_INITIALIZED, <<"DAP server not initialized">>
                ),
                {send_response(Transport, Response, Command, RequestSeq), DAPState};
            _ ->
                #{response := Response} =
                    Reaction =
                    try
                        validate_and_dispatch_request(Request, DAPState)
                    catch
                        throw:{method_not_found, Method}:_StackTrace ->
                            Error = <<"Method not found: ", Method/binary>>,
                            #{response => edb_dap:build_error_response(?JSON_RPC_ERROR_METHOD_NOT_FOUND, Error)};
                        throw:{invalid_params, Reason}:_StackTrace when is_binary(Reason) ->
                            Error = edb_dap:to_binary(
                                lists:flatten(
                                    io_lib:format("Invalid parameters for request '~s': ~s", [Command, Reason])
                                )
                            ),
                            #{response => edb_dap:build_error_response(?JSON_RPC_ERROR_INVALID_PARAMS, Error)};
                        Class:Reason:StackTrace ->
                            {Error, Actions} = react_to_unxpected_failure({Class, Reason, StackTrace}, DAPState),
                            ErrorResponse = edb_dap:build_error_response(?JSON_RPC_ERROR_INTERNAL_ERROR, Error),
                            #{response => ErrorResponse, actions => Actions}
                    end,
                ReactionDAPState = maps:get(state, Reaction, DAPState),
                {send_response(handle_actions(Transport, Reaction), Response, Command, RequestSeq), ReactionDAPState}
        end,
    {noreply, {NewTransport, NewDAPState}};
handle_cast({handle_message, #{type := response} = Response}, {Transport, DAPState}) ->
    ?LOG_DEBUG("Handle response: ~p", [Response]),
    Reaction =
        try
            dispatch_response(Response, DAPState)
        catch
            Class:Reason:StackTrace ->
                {_Error, Actions} = react_to_unxpected_failure({Class, Reason, StackTrace}, DAPState),
                #{actions => Actions}
        end,
    ReactionDAPState = maps:get(state, Reaction, DAPState),
    {noreply, {handle_actions(Transport, Reaction), ReactionDAPState}};
handle_cast(terminate, State) ->
    {stop, normal, State}.

-spec handle_info(
    {port(), {data, binary()}}
    | {port(), eof}
    | edb:event_envelope(edb:event()),
    state()
) -> {noreply, state()} | {stop, Reason :: normal, state()}.
handle_info(PortEvent = {IO, _}, State = {#{io := IO}, _}) when is_port(IO) ->
    handle_port_event(PortEvent, State);
handle_info(Event = {edb_event, _, _}, State) ->
    handle_edb_event(Event, State);
handle_info(Unexpected, State) ->
    ?LOG_WARNING("Unexpected message: ~p", [Unexpected]),
    {noreply, State}.

-spec handle_port_event(Event, state()) -> {noreply, state()} | {stop, normal, state()} when
    Event :: {port(), {data, binary()}} | {port(), eof}.
handle_port_event({IO, {data, Data}}, {#{io := IO, buffer := Buffer} = Transport, DAPState}) ->
    ?LOG_DEBUG("Received data: ~p (buffer: ~p)", [Data, Buffer]),
    {Frames, NewBuffer} = edb_dap:decode_frames(<<Buffer/binary, Data/binary>>),
    [gen_server:cast(self(), {handle_message, edb_dap:unframe(Frame)}) || Frame <- Frames],
    {noreply, {Transport#{buffer => NewBuffer}, DAPState}};
handle_port_event({IO, eof}, {#{io := IO} = _Transport, _DAP} = State) ->
    ?LOG_INFO("Connection closed, exiting..."),
    {stop, normal, State}.

-spec handle_edb_event(Event, state()) -> {noreply, state()} when
    Event :: edb:event_envelope(edb:event()).
handle_edb_event({edb_event, Subscription, Event}, {Transport, DAPState}) ->
    ?LOG_DEBUG("Handle event: ~p", [Event]),
    Reaction =
        case edb_dap_state:is_valid_subscription(DAPState, Subscription) of
            true ->
                try
                    dispatch_event(Event, DAPState)
                catch
                    Class:Reason:StackTrace ->
                        {_Errors, Actions} = react_to_unxpected_failure({Class, Reason, StackTrace}, DAPState),
                        #{actions => Actions}
                end;
            false ->
                ?LOG_WARNING("Invalid Subscription, skipping."),
                #{}
        end,
    ReactionDAPState = maps:get(state, Reaction, DAPState),
    {noreply, {handle_actions(Transport, Reaction), ReactionDAPState}}.

-spec handle_actions(
    transport_state(), edb_dap_requests:reaction(edb_dap:response()) | edb_dap_responses:reaction()
) ->
    transport_state().
handle_actions(Transport, Reaction) ->
    Actions = maps:get(actions, Reaction, []),
    lists:foldl(fun handle_action/2, Transport, Actions).

-spec handle_action(action(), transport_state()) -> transport_state().
handle_action({event, Type, Body}, State) ->
    send_event(State, Type, Body);
handle_action({reverse_request, Command, Args}, State) ->
    send_reverse_request(State, Command, Args);
handle_action(terminate, State) ->
    gen_server:cast(self(), terminate),
    State.

-spec send_event(transport_state(), edb_dap:event_type(), edb_dap:body()) -> transport_state().
send_event(State, Type, Body) ->
    Message =
        #{
            type => event,
            event => Type,
            body => Body
        },
    send(State, Message).

-spec send_reverse_request(transport_state(), edb_dap:command(), edb_dap:arguments()) -> transport_state().
send_reverse_request(State, Command, Args) ->
    Message = #{
        type => request,
        command => Command,
        arguments => Args
    },
    send(State, Message).

-spec send_response(transport_state(), map(), edb_dap:command(), edb_dap:seq()) -> transport_state().
send_response(Transport, Response, Command, RequestSeq) ->
    Message = Response#{type => response, request_seq => RequestSeq, command => Command},
    send(Transport, Message).

-spec send(transport_state(), map()) -> transport_state().
send(#{io := IO, seq := Seq} = Transport, #{type := Type} = Message) ->
    Data = edb_dap:encode_frame(edb_dap:frame(Message#{seq => Seq})),
    ?LOG_DEBUG("Sending data (type: ~p): ~p", [Type, Data]),
    IO ! {self(), {command, [Data]}},
    Transport#{seq => Seq + 1}.

-spec validate_and_dispatch_request(edb_dap:request(), edb_dap_state:t()) ->
    edb_dap_requests:reaction(edb_dap:response()).
validate_and_dispatch_request(#{command := Command} = Request, DAPState) ->
    Method = method_to_atom(Command),
    Arguments = maps:get(arguments, Request, #{}),
    case Method of
        launch ->
            case edb_dap_launch_config:parse(Arguments) of
                {ok, LaunchConfig} ->
                    edb_dap_requests:Method(DAPState, LaunchConfig);
                {error, Reason} ->
                    throw({invalid_params, Reason})
            end;
        _ ->
            edb_dap_requests:Method(DAPState, Arguments)
    end.

-spec dispatch_response(edb_dap:response(), edb_dap_state:t()) ->
    edb_dap_responses:reaction().
dispatch_response(#{command := Command, body := Body}, DAPState) ->
    Method = method_to_atom(Command),
    edb_dap_responses:Method(DAPState, Body).

-spec dispatch_event(edb:event(), edb_dap_state:t()) ->
    edb_dap_events:reaction().
dispatch_event({paused, PausedEvent}, DAPState) ->
    edb_dap_events:stopped(DAPState, PausedEvent);
dispatch_event({nodedown, Node, Reason}, DAPState) ->
    edb_dap_events:exited(DAPState, Node, Reason);
dispatch_event(Event, _DAPState) ->
    ?LOG_DEBUG("Skipping event: ~p", [Event]),
    #{}.

%% @doc Explicit mapping to avoid the risk of atom exhaustion
-spec method_to_atom(binary()) -> atom().
% Requests
method_to_atom(<<"initialize">>) ->
    initialize;
method_to_atom(<<"launch">>) ->
    launch;
method_to_atom(<<"disconnect">>) ->
    disconnect;
method_to_atom(<<"setBreakpoints">>) ->
    set_breakpoints;
method_to_atom(<<"threads">>) ->
    threads;
method_to_atom(<<"stackTrace">>) ->
    stack_trace;
method_to_atom(<<"continue">>) ->
    continue;
method_to_atom(<<"next">>) ->
    next;
method_to_atom(<<"stepOut">>) ->
    step_out;
method_to_atom(<<"scopes">>) ->
    scopes;
method_to_atom(<<"variables">>) ->
    variables;
% Reverse requests
method_to_atom(<<"runInTerminal">>) ->
    run_in_terminal;
method_to_atom(Method) ->
    ?LOG_WARNING("Method not found: ~p", [Method]),
    throw({method_not_found, Method}).

-spec format_exception(Class, Reason, StackTrace) -> binary() when
    Class :: 'error' | 'exit' | 'throw',
    Reason :: term(),
    StackTrace :: erlang:stacktrace().
format_exception(Class, Reason, StackTrace) ->
    case unicode:characters_to_binary(erl_error:format_exception(Class, Reason, StackTrace)) of
        Binary when is_binary(Binary) -> Binary;
        _ -> <<"Error converting error to binary">>
    end.

-spec react_to_unxpected_failure({Class, Reason, StackTrace}, DAPState) -> {Error, Actions} when
    Class :: error | exit | throw,
    Reason :: term(),
    StackTrace :: erlang:stacktrace(),
    DAPState :: edb_dap_state:t(),
    Error :: binary(),
    Actions :: [action()].
react_to_unxpected_failure({Class, Reason, StackTrace}, DAPState) ->
    Error = format_exception(Class, Reason, StackTrace),
    ?LOG_ERROR("Unexpected Error: ~p", [Error]),
    Actions =
        case edb_dap_state:is_attached(DAPState) of
            true ->
                [];
            false ->
                % We are not attached and crashing handling client messages, we
                % are unlikely to be able to do any work, so just terminate
                % the session
                [{event, <<"terminated">>, #{}}]
        end,
    {Error, Actions}.
