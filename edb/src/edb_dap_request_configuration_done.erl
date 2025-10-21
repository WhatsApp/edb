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

-module(edb_dap_request_configuration_done).

-moduledoc """
Handles Debug Adapter Protocol (DAP) configurationDone requests for the Erlang debugger.

The module follows the Microsoft Debug Adapter Protocol specification for
configurationDone requests: https://microsoft.github.io/debug-adapter-protocol/specification#Requests_ConfigurationDone
""".

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_ConfigurationDone
-type arguments() :: #{}.
-export_type([arguments/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()} | {error, Reason} when Reason :: binary().
parse_arguments(Args) ->
    edb_dap_request:parse_empty_arguments(Args).

-spec handle(State, Args) -> edb_dap_request:reaction() when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(State0 = #{state := configuring}, #{}) ->
    {ok, Subscription} = edb:subscribe(),
    {ok, resumed} = edb:continue(),
    #{
        new_state => State0#{
            state => attached,
            subscription => Subscription
        },
        response => edb_dap_request:success()
    };
handle(_UnexpectedState, _) ->
    edb_dap_request:unexpected_request().
