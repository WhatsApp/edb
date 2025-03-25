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
%%% % @format

-module(edb_dap_server).

%% erlfmt:ignore
% @fb-only
-moduledoc """
Handling of DAP requests, responses and events

For details see https://microsoft.github.io/debug-adapter-protocol/specification
""".
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
-type client_info() :: edb_dap_request_initialize:arguments().

-type attach_type() ::
    #{
        request := attach,
        process_id := number()
    }
    | #{
        request := launch,
        process_id := number(),
        shell_process_id => number()
    }.

-type state() ::
    #{
        % Server is up, waiting for an `initialize` request from the client
        state := started
    }
    | #{
        % Server received an `initialize` request and is waiting for `attach`/`launch` requests
        state := initialized,
        client_info := client_info()
    }
    | #{
        % A `launch` request was received and we are waiting for the debuggee node to be up
        state := launching,
        client_info := client_info(),
        shell_process_id => number(),
        notification_ref := reference(),
        cwd := binary()
    }
    | #{
        % We are attached to the debuggee node, have paused it
        % and sent an `initialized` event to the client. We are now
        % waiting for the client to send all the initial configuration
        % requests (setBreakpoints, etc)
        state := configuring,
        type := attach_type(),
        client_info := client_info(),
        node := node(),
        cwd := binary()
    }
    | #{
        % We are attached to the debuggee node, and debugging is in progress
        state := attached,
        type := attach_type(),
        client_info := client_info(),
        node := node(),
        cwd := binary(),
        subscription := edb:event_subscription()
    }
    | #{
        % We are shutting down
        state := terminating
    }.

-export_type([state/0, attach_type/0, client_info/0]).

-type action() ::
    {event, edb_dap_event:event()}
    | {reverse_request, edb_dap_reverse_request:request()}
    | terminate.
-export_type([action/0]).

-type reaction() ::
    #{
        response := edb_dap_request:response(edb_dap:body()),
        request_context := #{command := edb_dap:command(), seq := edb_dap:seq()},
        actions => [edb_dap_server:action()],
        new_state => edb_dap_server:state()
    }
    | #{
        error := error(),
        request_context => #{command := edb_dap:command(), seq := edb_dap:seq()},
        actions => [edb_dap_server:action()],
        new_state => edb_dap_server:state()
    }
    | #{
        error => error(),
        actions => [edb_dap_server:action()],
        new_state => edb_dap_server:state()
    }.

-type error() ::
    {method_not_found, edb_dap:command()}
    | {invalid_params, Reason :: binary()}
    | {user_error, Id :: integer(), Msg :: iodata()}
    | {internal_error, #{class := error | exit | throw, reason := term(), stacktrace := erlang:stacktrace()}}.
-export_type([error/0]).

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
    {ok, #{state => started}}.

-spec terminate(Reason :: term(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

-define(REACTING_TO_UNEXPECTED_ERRORS(Fun, Arg, State),
    try
        Fun(Arg, State)
    catch
        Class:Reason:StackTrace ->
            #{
                error => {internal_error, #{class => Class, reason => Reason, stacktrace => StackTrace}}
            }
    end
).

-spec handle_call(term(), term(), state()) -> {noreply, state()} | {stop | reply, term(), state()}.
handle_call(_Request, _From, State) ->
    {noreply, State}.

-spec handle_cast(cast_request(), state()) -> {noreply, state()} | {stop, normal, state()}.
handle_cast({handle_message, Request = #{type := request}}, State0) ->
    Reaction0 = ?REACTING_TO_UNEXPECTED_ERRORS(
        fun edb_dap_request:dispatch/2,
        Request,
        State0
    ),

    RequestContext = maps:with([command, seq], Request),
    Reaction1 = Reaction0#{request_context => RequestContext},

    State1 = react(Reaction1, State0),
    {noreply, State1};
handle_cast({handle_message, Response = #{type := response}}, State0) ->
    Reaction = ?REACTING_TO_UNEXPECTED_ERRORS(
        fun edb_dap_reverse_request:dispatch_response/2,
        Response,
        State0
    ),
    State1 = react(Reaction, State0),
    {noreply, State1};
handle_cast(terminate, State) ->
    {stop, normal, State}.

-spec handle_info(Event, state()) -> {noreply, state()} when
    Event :: {reference(), edb_dap_internal_events:reverse_attach_result()} | edb:event_envelope(edb:event()).
handle_info(
    {NotificationRef, ReverseAttachResult}, State0 = #{state := launching, notification_ref := NotificationRef}
) ->
    ?LOG_DEBUG("Handle reverse attach result: ~p", [ReverseAttachResult]),
    Reaction = ?REACTING_TO_UNEXPECTED_ERRORS(
        fun edb_dap_internal_events:handle_reverse_attach_result/2, ReverseAttachResult, State0
    ),
    State1 = react(Reaction, State0),
    {noreply, State1};
handle_info(Event = {edb_event, _, _}, State) ->
    handle_edb_event(Event, State);
handle_info(Unexpected, State) ->
    ?LOG_WARNING("Unexpected message: ~p", [Unexpected]),
    {noreply, State}.

-spec handle_edb_event(Event, state()) -> {noreply, state()} when
    Event :: edb:event_envelope(edb:event()).
handle_edb_event({edb_event, Subscription, Event}, State0 = #{subscription := Subscription}) ->
    ?LOG_DEBUG("Handle event: ~p", [Event]),
    Reaction = ?REACTING_TO_UNEXPECTED_ERRORS(fun edb_dap_internal_events:handle_edb_event/2, Event, State0),
    State1 = react(Reaction, State0),
    {noreply, State1};
handle_edb_event(_UnexpectedEvent, State0) ->
    ?LOG_WARNING("Invalid Subscription, skipping."),
    {noreply, State0}.

-spec react(Reaction, state()) -> state() when
    Reaction :: reaction().
react(Reaction, State = #{state := attached}) ->
    react_1(Reaction, State);
react(Reaction0 = #{error := {internal_error, _}}, State) ->
    % We are not attached and crashing handling client messages, we
    % are unlikely to be able to do any work, so just terminate
    % the session
    Reaction1 = Reaction0#{
        new_state => #{state => terminating},
        actions => [{event, edb_dap_event:terminated()}]
    },
    react_1(Reaction1, State);
react(Reaction, State) ->
    react_1(Reaction, State).

-spec react_1(Reaction, state()) -> state() when
    Reaction :: reaction().
react_1(Reaction, State0) ->
    Actions = maps:get(actions, Reaction, []),
    [handle_action(Action) || Action <- Actions],
    case Reaction of
        #{error := ErrorToLog} ->
            IsHandlingRequest = maps:is_key(request_context, Reaction),
            log_error(IsHandlingRequest, ErrorToLog);
        _ ->
            ok
    end,
    case Reaction of
        #{request_context := ReqCtx, response := Response} ->
            edb_dap_transport:send_response(ReqCtx, Response);
        #{request_context := ReqCtx, error := Error} ->
            edb_dap_transport:send_response(ReqCtx, error_response(Error));
        _ ->
            ok
    end,
    State1 = maps:get(new_state, Reaction, State0),
    State1.

-spec error_response(Error :: error()) -> edb_dap:error_response().
error_response({method_not_found, Method}) ->
    Error = <<"Method not found: ", Method/binary>>,
    build_error_response(?JSON_RPC_ERROR_METHOD_NOT_FOUND, Error);
error_response({invalid_params, Reason}) ->
    Error = <<"Invalid parameters: ", Reason/binary>>,
    build_error_response(?JSON_RPC_ERROR_INVALID_PARAMS, Error);
error_response({user_error, Id, Msg}) ->
    build_error_response(Id, Msg);
error_response({internal_error, #{class := Class, reason := Reason, stacktrace := ST}}) ->
    Error = format_exception(Class, Reason, ST),
    ?LOG_ERROR("Unexpected Error: ~p", [Error]),
    build_error_response(?JSON_RPC_ERROR_INTERNAL_ERROR, Error).

-spec handle_action(action()) -> ok.
handle_action({event, Event}) ->
    edb_dap_transport:send_event(Event);
handle_action({reverse_request, ReverseRequest}) ->
    edb_dap_transport:send_reverse_request(ReverseRequest);
handle_action(terminate) ->
    gen_server:cast(self(), terminate).

-spec format_exception(Class, Reason, StackTrace) -> binary() when
    Class :: 'error' | 'exit' | 'throw',
    Reason :: term(),
    StackTrace :: erlang:stacktrace().
format_exception(Class, Reason, StackTrace) ->
    case unicode:characters_to_binary(erl_error:format_exception(Class, Reason, StackTrace)) of
        Binary when is_binary(Binary) -> Binary;
        _ -> ~"Error converting error to binary"
    end.

-spec build_error_response(number(), iodata()) -> edb_dap:error_response().
build_error_response(Id, Message) ->
    #{
        success => false,
        body => #{error => #{id => Id, format => erlang:iolist_to_binary(Message)}}
    }.

-spec log_error(IsHandlingRequest, Error) -> ok when
    IsHandlingRequest :: boolean(),
    Error :: error().
log_error(_, {internal_error, #{class := Class, reason := Reason, stacktrace := ST}}) ->
    ?LOG_ERROR("Internal error: ~s", [erl_error:format_exception(Class, Reason, ST)]);
log_error(true, _) ->
    % A user error: will be logged as part of the response to the client, so we avoid
    % duplicating this
    ok;
log_error(false, {method_not_found, Method}) ->
    ?LOG_WARNING("Method not found: ~p", [Method]);
log_error(false, {invalid_params, Reason}) ->
    ?LOG_INFO("Invalid parameters: ~p", [Reason]);
log_error(false, {user_error, _Id, Msg}) ->
    ?LOG_DEBUG("User error: ~s", [Msg]).
