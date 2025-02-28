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
%% @doc Behaviour for handling client requests
%%
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(edb_dap_request).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

%% Public API
-export([dispatch/2]).

%% Helpers for behaviour implementations
-export([unexpected_request/0]).
-export([unknown_resource/2]).
-export([not_paused/1]).

-include("edb_dap.hrl").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
-export_type([reaction/0, reaction/1, response/1, resource/0]).

-type reaction() :: reaction(none()).

-type reaction(T) ::
    #{
        response := response(T),
        actions => [edb_dap_server:action()],
        new_state => edb_dap_server:state()
    }
    | #{
        error := edb_dap_server:error(),
        actions => [edb_dap_server:action()],
        new_state => edb_dap_server:state()
    }.

-type response(T) :: #{
    success := boolean(),
    message => binary(),
    body => T
}.

-type resource() ::
    thread_id
    | variables_ref.

%% ------------------------------------------------------------------
%% Callbacks
%% ------------------------------------------------------------------
-callback parse_arguments(Arguments) -> {ok, ParsedArguments} | {error, Reason} when
    Arguments :: edb_dap:arguments(),
    ParsedArguments :: edb_dap:arguments(),
    Reason :: binary().

-callback handle(State, Arguments) -> reaction(edb_dap:body()) when
    State :: edb_dap_server:state(),
    Arguments :: edb_dap:arguments().

%% ------------------------------------------------------------------
%% Dispatching
%% ------------------------------------------------------------------
-spec dispatch(Request, State) -> Reaction when
    Request :: edb_dap:request(),
    State :: edb_dap_server:state(),
    Reaction :: reaction(edb_dap:response()).
dispatch(#{command := Method} = Request, State) ->
    case known_handlers() of
        #{Method := Handler} ->
            Arguments = maps:get(arguments, Request, #{}),
            case Handler:parse_arguments(Arguments) of
                {ok, ParsedArguments} ->
                    Handler:handle(State, ParsedArguments);
                {error, Reason} when is_binary(Reason) ->
                    #{error => {invalid_params, Reason}}
            end;
        _ ->
            #{error => {method_not_found, Method}}
    end.

-spec known_handlers() -> #{binary() => module()}.
known_handlers() ->
    #{
        ~"continue" => edb_dap_request_continue,
        ~"disconnect" => edb_dap_request_disconnect,
        ~"initialize" => edb_dap_request_initialize,
        ~"launch" => edb_dap_request_launch,
        ~"pause" => edb_dap_request_pause,
        ~"next" => edb_dap_request_next,
        ~"scopes" => edb_dap_request_scopes,
        ~"setBreakpoints" => edb_dap_request_set_breakpoints,
        ~"stackTrace" => edb_dap_request_stack_trace,
        ~"stepOut" => edb_dap_request_step_out,
        ~"threads" => edb_dap_request_threads,
        ~"variables" => edb_dap_request_variables
    }.

%% ------------------------------------------------------------------
%% Helpers for behaviour implementations
%% ------------------------------------------------------------------
-spec unexpected_request() -> reaction().
unexpected_request() ->
    #{error => {user_error, ?ERROR_PRECONDITION_VIOLATION, ~"Request sent when it was not expected"}}.

-spec unknown_resource(Type, Id) -> reaction() when
    Type :: resource(),
    Id :: number().
unknown_resource(thread_id, Id) -> unknown_resource_1(~"threadId", Id);
unknown_resource(variables_ref, Id) -> unknown_resource_1(~"variablesReference", Id).

-spec unknown_resource_1(Name, Id) -> reaction() when
    Name :: binary(),
    Id :: number().
unknown_resource_1(Name, Id) ->
    Msg = io_lib:format("Unknown ~s: ~p", [Name, Id]),
    #{error => {user_error, ?JSON_RPC_ERROR_INVALID_PARAMS, Msg}}.

-spec not_paused(Pid) -> reaction() when Pid :: pid().
not_paused(_Pid) ->
    % Not including the Pid in the message, since it will be displayed in the context of the wrong node
    % but useful to have here for troubleshooting
    #{error => {user_error, ?ERROR_PRECONDITION_VIOLATION, "Process is not paused"}}.
