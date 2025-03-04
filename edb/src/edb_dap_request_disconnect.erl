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

-module(edb_dap_request_disconnect).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Disconnect
-type arguments() :: #{
    %  A value of true indicates that this `disconnect` request is part of a
    % restart sequence
    restart => boolean(),

    % Indicates whether the debuggee should be terminated when the debugger is
    % disconnected.
    % If unspecified, the debug adapter is free to do whatever it thinks is best.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportTerminateDebuggee` is true.
    terminateDebuggee => boolean(),

    % Indicates whether the debuggee should stay suspended when the debugger is
    % disconnected.
    % If unspecified, the debuggee should resume execution.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportSuspendDebuggee` is true.
    supportSuspendDebuggee => boolean()
}.

-export_type([arguments/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()}.
parse_arguments(Args) ->
    {ok, Args}.

-spec handle(State, Args) -> edb_dap_request:reaction() when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(_State, _Args) ->
    % TODO(T206222651) make the behaviour compliant
    ok = edb:terminate(),
    #{
        response => edb_dap_request:success(),
        actions => [terminate]
    }.
