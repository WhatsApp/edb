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
%% @doc JSON-RPC / DAP Constants, as defined in
%%      https://www.jsonrpc.org/specification
%% @end
%%%-------------------------------------------------------------------
%%% % @format
%%%
% @fb-only

%%%---------------------------------------------------------------------------------
%%% Callbacks
%%%---------------------------------------------------------------------------------
%% Invalid JSON was received by the server.
%% An error occurred on the server while parsing the JSON text.
-define(JSON_RPC_ERROR_PARSE_ERROR, -32700).
%% The JSON sent is not a valid Request object.
-define(JSON_RPC_ERROR_INVALID_REQUEST, -32600).
%% The method does not exist / is not available.
-define(JSON_RPC_ERROR_METHOD_NOT_FOUND, -32601).
%% Invalid method parameter(s).
-define(JSON_RPC_ERROR_INVALID_PARAMS, -32602).
%% Internal JSON-RPC error.
-define(JSON_RPC_ERROR_INTERNAL_ERROR, -32603).

%%%---------------------------------------------------------------------------------
%%% Reserved for implementation-defined server-errors.
%%%---------------------------------------------------------------------------------
-define(ERROR_TIMED_OUT, -32001).
-define(ERROR_PRECONDITION_VIOLATION, -32002).
-define(ERROR_NOT_SUPPORTED, -32003).
-define(ERROR_NODE_NOT_FOUND, -32004).
