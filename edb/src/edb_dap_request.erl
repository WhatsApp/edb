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
-export([success/0, success/1]).
-export([abort/1]).
-export([unexpected_request/0]).
-export([unknown_resource/2]).
-export([not_paused/1]).
-export([precondition_violation/1]).
-export([unsupported/1]).

-export([thread_id_to_pid/1]).

-export([parse_empty_arguments/1]).

-include("edb_dap.hrl").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
-export_type([reaction/0, reaction/1, error_reaction/0, response/1, resource/0]).

-type reaction() :: reaction(none()).

-type error_reaction() :: #{
    error := edb_dap_server:error(),
    actions => [edb_dap_server:action()],
    new_state => edb_dap_server:state()
}.

-type reaction(T) ::
    #{
        response := response(T),
        actions => [edb_dap_server:action()],
        new_state => edb_dap_server:state()
    }
    | error_reaction().

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
                    try
                        Handler:handle(State, ParsedArguments)
                    catch
                        throw:{'__$abort$__', Error} -> Error
                    end;
                {error, Reason} when is_binary(Reason) ->
                    #{error => {invalid_params, Reason}}
            end;
        _ ->
            #{error => {method_not_found, Method}}
    end.

-spec known_handlers() -> #{binary() => module()}.
known_handlers() ->
    #{
        ~"attach" => edb_dap_request_attach,
        ~"configurationDone" => edb_dap_request_configuration_done,
        ~"continue" => edb_dap_request_continue,
        ~"disconnect" => edb_dap_request_disconnect,
        ~"initialize" => edb_dap_request_initialize,
        ~"launch" => edb_dap_request_launch,
        ~"pause" => edb_dap_request_pause,
        ~"next" => edb_dap_request_next,
        ~"scopes" => edb_dap_request_scopes,
        ~"setBreakpoints" => edb_dap_request_set_breakpoints,
        ~"setExceptionBreakpoints" => edb_dap_request_set_exception_breakpoints,
        ~"stackTrace" => edb_dap_request_stack_trace,
        ~"stepIn" => edb_dap_request_step_in,
        ~"stepOut" => edb_dap_request_step_out,
        ~"threads" => edb_dap_request_threads,
        ~"variables" => edb_dap_request_variables
    }.

%% ------------------------------------------------------------------
%% Helpers for behaviour implementations
%% ------------------------------------------------------------------

-spec success() -> response(none()).
success() ->
    #{success => true}.

-spec success(Body) -> response(Body) when Body :: edb_dap:body().
success(Body) ->
    #{success => true, body => Body}.

-spec abort(Error) -> no_return() when Error :: error_reaction().
abort(Error) ->
    throw({'__$abort$__', Error}).

-spec precondition_violation(Msg) -> error_reaction() when Msg :: iodata().
precondition_violation(Msg) ->
    #{error => {user_error, ?ERROR_PRECONDITION_VIOLATION, Msg}}.

-spec unexpected_request() -> error_reaction().
unexpected_request() ->
    precondition_violation(~"Request sent when it was not expected").

-spec unknown_resource(Type, Id) -> error_reaction() when
    Type :: resource(),
    Id :: number().
unknown_resource(thread_id, Id) -> unknown_resource_1(~"threadId", Id);
unknown_resource(variables_ref, Id) -> unknown_resource_1(~"variablesReference", Id).

-spec unknown_resource_1(Name, Id) -> error_reaction() when
    Name :: binary(),
    Id :: number().
unknown_resource_1(Name, Id) ->
    Msg = io_lib:format("Unknown ~s: ~p", [Name, Id]),
    #{error => {user_error, ?JSON_RPC_ERROR_INVALID_PARAMS, Msg}}.

-spec not_paused(Pid) -> error_reaction() when Pid :: pid().
not_paused(_Pid) ->
    % Not including the Pid in the message, since it will be displayed in the context of the wrong node
    % but useful to have here for troubleshooting
    precondition_violation(~"Process is not paused").

-spec unsupported(Msg) -> error_reaction() when Msg :: iodata().
unsupported(Msg) ->
    #{error => {user_error, ?ERROR_NOT_SUPPORTED, Msg}}.

-spec thread_id_to_pid(ThreadId) -> pid() when ThreadId :: edb_dap:thread_id().
thread_id_to_pid(ThreadId) ->
    case edb_dap_id_mappings:thread_id_to_pid(ThreadId) of
        {ok, Pid} -> Pid;
        {error, not_found} -> edb_dap_request:abort(edb_dap_request:unknown_resource(thread_id, ThreadId))
    end.

-spec parse_empty_arguments(Arguments) -> {ok, #{}} | {error, Reason} when
    Arguments :: edb_dap:arguments(),
    Reason :: binary().
parse_empty_arguments(Args) ->
    Template = #{},
    edb_dap_parse:parse(Template, Args, reject_unknown).
