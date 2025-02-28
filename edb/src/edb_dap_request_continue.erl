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

-module(edb_dap_request_continue).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Continue
-type arguments() :: #{
    % Specifies the active thread. If the debug adapter supports single thread
    % execution (see `supportsSingleThreadExecutionRequests`) and the argument
    % `singleThread` is true, only the thread with this ID is resumed.
    threadId := edb_dap:thread_id(),
    % If this flag is true, execution is resumed only for the thread with given
    % `threadId`.
    singleThread => boolean()
}.

-type response_body() :: #{
    % The value true (or a missing property) signals to the client that all
    % threads have been resumed. The value false indicates that not all threads
    % were resumed.
    allThreadsContinued => boolean()
}.

-export_type([arguments/0, response_body/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()}.
parse_arguments(Args) ->
    {ok, Args}.

-spec handle(State, Args) -> edb_dap_request:reaction(response_body()) when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(#{state := attached}, _Args) ->
    edb_dap_id_mappings:reset(),
    {ok, _} = edb:continue(),
    #{response => #{success => true, body => #{allThreadsContinued => true}}};
handle(_UnexpectedState, _) ->
    edb_dap_request:unexpected_request().
