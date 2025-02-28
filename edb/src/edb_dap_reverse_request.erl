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
%% @doc Behaviour for handling reverse-requests to the client
%%
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(edb_dap_reverse_request).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

%% Public API
-export([dispatch_response/2]).

%% Helpers for behaviour implementations
-export([unexpected_response/0]).

-include("edb_dap.hrl").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
-export_type([request/0, request/1, reaction/0]).

-type reaction() :: #{
    error => edb_dap_server:error(),
    actions => [edb_dap_server:action()],
    new_state => edb_dap_server:state()
}.

-type request() :: request(edb_dap:arguments()).

-type request(T) :: #{
    command := binary(),
    arguments => T
}.

%% ------------------------------------------------------------------
%% Callbacks
%% ------------------------------------------------------------------
-callback make_request(Args) -> request(Args) when
    Args :: edb_dap:arguments().

-callback handle_response(State, Body) -> reaction() when
    State :: edb_dap_server:state(),
    Body :: edb_dap:body().

%% ------------------------------------------------------------------
%% Dispatching
%% ------------------------------------------------------------------
-spec dispatch_response(Response, State) -> reaction() when
    Response :: edb_dap:response(),
    State :: edb_dap_server:state().
dispatch_response(#{command := Method} = Response, State) ->
    case known_handlers() of
        #{Method := Handler} ->
            Body = maps:get(body, Response, #{}),
            Handler:handle_response(State, Body);
        _ ->
            #{error => {method_not_found, Method}}
    end.

-spec known_handlers() -> #{binary() => module()}.
known_handlers() ->
    #{
        ~"runInTerminal" => edb_dap_reverse_request_run_in_terminal
    }.

%% ------------------------------------------------------------------
%% Helpers for behaviour implementations
%% ------------------------------------------------------------------
-spec unexpected_response() -> reaction().
unexpected_response() ->
    #{error => {user_error, ?JSON_RPC_ERROR_INVALID_REQUEST, ~"Response sent when it was not expected"}}.
