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

-module(edb_dap_reverse_request_start_debugging).

-moduledoc """
Handles Debug Adapter Protocol (DAP) startDebugging reverse requests for the Erlang debugger.

The module follows the Microsoft Debug Adapter Protocol specification for
startDebugging reverse requests: https://microsoft.github.io/debug-adapter-protocol/specification#Reverse_Requests_StartDebugging
""".

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_reverse_request).

-export([make_request/1, handle_response/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

% https://microsoft.github.io/debug-adapter-protocol//specification.html#Reverse_Requests_StartDebugging
-type arguments() ::
    #{
        request := attach,
        configuration := edb_dap_request_attach:arguments()
    }
    | #{
        request := launch,
        configuration := edb_dap_request_launch:arguments()
    }.

-type response_body() :: #{}.

-export_type([arguments/0, response_body/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec make_request(Args) -> edb_dap_reverse_request:request(Args) when
    Args :: arguments().
make_request(Args) ->
    #{command => ~"startDebugging", arguments => Args}.

-spec handle_response(edb_dap_server:state(), response_body()) -> edb_dap_reverse_request:reaction().
handle_response(_State0, _Body) ->
    #{}.
