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

-module(edb_dap_request_attach).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).
-export([handle_bootstrap_failure/1]).

-include_lib("edb/include/edb_dap.hrl").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Attach
%%% Notice that, since , the arguments for this request are
%%% not part of the DAP specification itself.

-export_type([arguments/0, config/0]).
-type arguments() :: #{config := config()}.

-type config() :: #{
    node := node(),
    cookie => atom(),
    cwd := binary(),
    stripSourcePrefix => binary()
}.

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        config => #{
            node => edb_dap_parse:atom(),
            cookie => {optional, edb_dap_parse:atom()},
            cwd => edb_dap_parse:binary(),
            stripSourcePrefix => {optional, edb_dap_parse:binary()}
        }
    }.

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()} | {error, Reason :: binary()}.
parse_arguments(Args) ->
    Template = arguments_template(),
    edb_dap_parse:parse(Template, Args, allow_unknown).

-spec handle(State, Args) -> edb_dap_request:reaction() when
    State :: edb_dap_server:state(),
    Args :: config().
handle(State0 = #{state := initialized}, Args) ->
    #{config := Config} = Args,
    AttachArgs = maps:without([cwd, stripSourcePrefix], Config),
    case edb:attach(AttachArgs) of
        ok ->
            ok = edb:pause(),
            Cwd = maps:get(cwd, Config),
            StripSourcePrefix = maps:get(stripSourcePrefix, Config, ~""),
            Node = maps:get(node, Config),
            % elp:ignore W0014 -- debugger relies on dist
            ProcessId = list_to_integer(erpc:call(Node, os, getpid, [])),
            {ok, Subscription} = edb:subscribe(),
            State1 = State0#{
                state => configuring,
                type => #{
                    request => attach,
                    process_id => ProcessId
                },
                node => Node,
                reverse_attach_ref => undefined,
                cwd => edb_dap_utils:strip_suffix(Cwd, StripSourcePrefix),
                subscription => Subscription
            },
            #{
                new_state => State1,
                response => edb_dap_request:success(),
                actions => [{event, edb_dap_event:initialized()}]
            };
        {error, Reason} ->
            handle_error(Reason)
    end;
handle(_InvalidState, _Args) ->
    edb_dap_request:unexpected_request().

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-spec handle_error(Reason) -> edb_dap_request:reaction() when
    Reason ::
        attachment_in_progress
        | nodedown
        | {bootstrap_failed, edb:bootstrap_failure()}.
handle_error(attachment_in_progress) ->
    throw(attachment_in_progress);
handle_error(nodedown) ->
    #{error => {user_error, ?ERROR_NODE_NOT_FOUND, ~"Node not found"}};
handle_error({bootstrap_failed, BootstrapFailure}) ->
    handle_bootstrap_failure(BootstrapFailure).

-spec handle_bootstrap_failure(edb:bootstrap_failure()) -> edb_dap_request:reaction().
handle_bootstrap_failure({no_debugger_support, not_enabled}) ->
    edb_dap_request:unsupported(
        ~"Debugging was not enabled on the node: the +D emu flag was not used to start the node"
    );
handle_bootstrap_failure({no_debugger_support, {missing, erl_debugger}}) ->
    edb_dap_request:unsupported(
        ~"Node is running unsupported OTP version: the erl_debugger module is not available"
    );
handle_bootstrap_failure(Unexpected = {module_injection_failed, _Module, _Reason}) ->
    throw(Unexpected).
