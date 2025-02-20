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
%% @doc DAP Response Handlers
%%      The actual implementation for the DAP responses (reverse requests).
%%      This function should be invoked by the DAP server.
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(edb_dap_responses).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-export([run_in_terminal/2]).

-type reaction() :: #{
    actions => [edb_dap_server:action()],
    state => edb_dap_state:t()
}.
-export_type([reaction/0]).

-include_lib("kernel/include/logger.hrl").

-spec run_in_terminal(edb_dap_state:t(), edb_dap:run_in_terminal_response()) ->
    reaction().
run_in_terminal(State, _Body) ->
    #{
        target_node := #{name := NodeName, cookie := Cookie},
        attach_timeout := AttachTimeoutInSecs
    } = edb_dap_state:get_context(State),
    case edb:attach(#{node => NodeName, timeout => AttachTimeoutInSecs * 1000, cookie => Cookie}) of
        ok ->
            {ok, Subscription} = edb:subscribe(),
            NewState = edb_dap_state:set_status(State, {attached, Subscription}),
            #{actions => [{event, <<"initialized">>, #{}}], state => NewState};
        {error, Reason} ->
            ?LOG_ERROR("Attaching (node: ~p) (reason: ~p)", [NodeName, Reason]),
            NewState = edb_dap_state:set_status(State, cannot_attach),
            #{actions => [{event, <<"terminated">>, #{}}], state => NewState}
    end.
