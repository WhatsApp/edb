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

%%% % @format

-module(edb_dap_request_step_out).

-moduledoc """
Handles Debug Adapter Protocol (DAP) stepOut requests for the Erlang debugger.

The module follows the Microsoft Debug Adapter Protocol specification for
stepOut requests: https://microsoft.github.io/debug-adapter-protocol/specification#Requests_StepOut
""".

%% erlfmt:ignore
% @fb-only[end= ]: -oncall("whatsapp_server_devx").
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_StepOut
-type arguments() :: #{
    %  Specifies the thread for which to resume execution for one step-out (of the
    %  given granularity).
    threadId := number(),

    %  If this flag is true, all other suspended threads are not resumed.
    singleThread => boolean(),

    %  Stepping granularity. If no granularity is specified, a granularity of
    %  `statement` is assumed.
    granularity => edb_dap:stepping_granularity()
}.

-export_type([arguments/0]).

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        threadId => edb_dap_parse:number(),
        singleThread => {optional, edb_dap_parse:boolean()},
        granularity => {optional, edb_dap_request_next:parse_stepping_granularity()}
    }.

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()} | {error, Reason :: binary()}.
parse_arguments(Args) ->
    Template = arguments_template(),
    edb_dap_parse:parse(Template, Args, reject_unknown).

-spec handle(State, Args) -> edb_dap_request:reaction() when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(State, #{threadId := ThreadId}) ->
    edb_dap_request_next:stepper(State, ThreadId, 'step-out').
