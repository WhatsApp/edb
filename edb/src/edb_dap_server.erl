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
%% @doc Handling of DAP requests, responses and events
%%
%% For details see https://microsoft.github.io/debug-adapter-protocol/specification
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

% Public API
-export([start_link/0]).
-export([handle_message/1]).

%% gen_server callbacks
-export([
    init/1,
    terminate/2,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).
-define(SERVER, ?MODULE).

%%%---------------------------------------------------------------------------------
%%% Types
%%%---------------------------------------------------------------------------------

-type state() :: edb_dap_state:t().

-type action() ::
    {event, edb_dap:event_type(), edb_dap:arguments()}
    | {reverse_request, edb_dap_reverse_request:request()}
    | terminate.
-export_type([action/0]).

-type cast_request() ::
    {handle_message, edb_dap:request() | edb_dap:response()}
    | {handle_response, edb_dap:response()}
    | terminate.

%%%---------------------------------------------------------------------------------
%%% API
%%%---------------------------------------------------------------------------------

-spec start_link() -> {ok, pid()}.
start_link() ->
    {ok, _Pid} = gen_server:start_link({local, ?SERVER}, ?MODULE, noargs, []).

-spec handle_message(Message) -> ok when
    Message :: edb_dap:request() | edb_dap:response().
handle_message(Message) ->
    gen_server:cast(?SERVER, {handle_message, Message}).

%%%---------------------------------------------------------------------------------
%%% Callbacks
%%%---------------------------------------------------------------------------------

-spec init(noargs) -> {ok, state()}.
init(noargs) ->
    {ok, edb_dap_state:new()}.

-spec terminate(Reason :: term(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec handle_call(term(), term(), state()) -> {noreply, state()} | {stop | reply, term(), state()}.
handle_call(_Request, _From, State) ->
    {noreply, State}.

-spec handle_cast(cast_request(), state()) -> {noreply, state()} | {stop, normal, state()}.
handle_cast({handle_message, Message = #{command := Cmd, type := Type}}, State0) when
    is_binary(Cmd), Type =:= request; Type =:= response
->
    ?LOG_DEBUG("Handle message: ~p", [Message]),
    #{command := Command, type := Type} = Message,

    Reaction =
        case edb_dap_state:is_initialized(State0) of
            false when Command =/= ~"initialize" ->
                ErrorResponse = edb_dap:build_error_response(
                    ?ERROR_SERVER_NOT_INITIALIZED, ~"DAP server not initialized"
                ),
                #{response => ErrorResponse};
            _ ->
                try
                    case Message of
                        Request = #{type := request} -> edb_dap_request:dispatch(Request, State0);
                        Response = #{type := response} -> edb_dap_reverse_request:dispatch_response(Response, State0)
                    end
                catch
                    throw:{method_not_found, Method}:_StackTrace ->
                        Error = <<"Method not found: ", Method/binary>>,
                        #{response => edb_dap:build_error_response(?JSON_RPC_ERROR_METHOD_NOT_FOUND, Error)};
                    throw:{invalid_params, Reason}:_StackTrace when is_binary(Reason) ->
                        Error = edb_dap:to_binary(
                            io_lib:format("Invalid parameters for request '~s': ~s", [Command, Reason])
                        ),
                        #{response => edb_dap:build_error_response(?JSON_RPC_ERROR_INVALID_PARAMS, Error)};
                    Class:Reason:StackTrace ->
                        {Error, Actions} = react_to_unxpected_failure({Class, Reason, StackTrace}, State0),
                        ErrorResponse = edb_dap:build_error_response(?JSON_RPC_ERROR_INTERNAL_ERROR, Error),
                        #{response => ErrorResponse, actions => Actions}
                end
        end,
    ok = handle_reaction(Reaction),
    case {Message, Reaction} of
        {Req = #{type := request}, #{response := RequestResponse}} ->
            edb_dap_transport:send_response(Req, RequestResponse);
        {#{type := response}, _} ->
            % Error responses from catch-handler can be ignored when handling reverse-request responses
            ok
    end,
    State1 = maps:get(state, Reaction, State0),
    {noreply, State1};
handle_cast(terminate, State) ->
    {stop, normal, State}.

-spec handle_info(Event, state()) -> {noreply, state()} when
    Event :: edb:event_envelope(edb:event()).
handle_info(Event = {edb_event, _, _}, State) ->
    handle_edb_event(Event, State);
handle_info(Unexpected, State) ->
    ?LOG_WARNING("Unexpected message: ~p", [Unexpected]),
    {noreply, State}.

-spec handle_edb_event(Event, state()) -> {noreply, state()} when
    Event :: edb:event_envelope(edb:event()).
handle_edb_event({edb_event, Subscription, Event}, State0) ->
    ?LOG_DEBUG("Handle event: ~p", [Event]),
    Reaction =
        case edb_dap_state:is_valid_subscription(State0, Subscription) of
            true ->
                try
                    dispatch_event(Event, State0)
                catch
                    Class:Reason:StackTrace ->
                        {_Errors, Actions} = react_to_unxpected_failure({Class, Reason, StackTrace}, State0),
                        #{actions => Actions}
                end;
            false ->
                ?LOG_WARNING("Invalid Subscription, skipping."),
                #{}
        end,
    ok = handle_reaction(Reaction),
    State1 = maps:get(state, Reaction, State0),
    {noreply, State1}.

-spec handle_reaction(Reaction) -> ok when
    Reaction :: edb_dap_request:reaction(edb_dap:response()) | edb_dap_reverse_request:reaction().
handle_reaction(Reaction) ->
    Actions = maps:get(actions, Reaction, []),
    [handle_action(Action) || Action <- Actions],
    ok.

-spec handle_action(action()) -> ok.
handle_action({event, Type, Body}) ->
    edb_dap_transport:send_event(Type, Body);
handle_action({reverse_request, ReverseRequest}) ->
    edb_dap_transport:send_reverse_request(ReverseRequest);
handle_action(terminate) ->
    gen_server:cast(self(), terminate).

-spec dispatch_event(EdbEvent, State) -> Reaction when
    EdbEvent :: edb:event(),
    State :: state(),
    Reaction :: edb_dap_events:reaction().
dispatch_event({paused, PausedEvent}, State) ->
    edb_dap_events:stopped(State, PausedEvent);
dispatch_event({nodedown, Node, Reason}, State) ->
    edb_dap_events:exited(State, Node, Reason);
dispatch_event(Event, _State) ->
    ?LOG_DEBUG("Skipping event: ~p", [Event]),
    #{}.

-spec format_exception(Class, Reason, StackTrace) -> binary() when
    Class :: 'error' | 'exit' | 'throw',
    Reason :: term(),
    StackTrace :: erlang:stacktrace().
format_exception(Class, Reason, StackTrace) ->
    case unicode:characters_to_binary(erl_error:format_exception(Class, Reason, StackTrace)) of
        Binary when is_binary(Binary) -> Binary;
        _ -> <<"Error converting error to binary">>
    end.

-spec react_to_unxpected_failure({Class, Reason, StackTrace}, State) -> {Error, Actions} when
    Class :: error | exit | throw,
    Reason :: term(),
    StackTrace :: erlang:stacktrace(),
    State :: state(),
    Error :: binary(),
    Actions :: [action()].
react_to_unxpected_failure({Class, Reason, StackTrace}, State) ->
    Error = format_exception(Class, Reason, StackTrace),
    ?LOG_ERROR("Unexpected Error: ~p", [Error]),
    Actions =
        case edb_dap_state:is_attached(State) of
            true ->
                [];
            false ->
                % We are not attached and crashing handling client messages, we
                % are unlikely to be able to do any work, so just terminate
                % the session
                [{event, ~"terminated", #{}}]
        end,
    {Error, Actions}.
