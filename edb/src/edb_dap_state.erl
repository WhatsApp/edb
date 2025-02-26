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
%% @doc DAP state
%%      An interface around the state of the DAP server.
%% @end
%%%-------------------------------------------------------------------
%%% % @format
-module(edb_dap_state).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-type status() :: started | initialized | {attached, edb:event_subscription()} | cannot_attach.
-type target_node_type() :: shortnames | longnames.
-type target_node() :: #{name := node(), cookie := atom(), type => target_node_type()}.
-type context() :: #{
    target_node => target_node(),
    attach_timeout := non_neg_integer(),
    cwd := binary(),
    strip_source_prefix := binary(),
    % This is `cwd` with the suffix that matches `strip_source_prefix` removed
    % This is used to make sure that the source paths are relative to the
    % repo root, and not the cwd, in they case they do not coincide.
    % It is stored in the context to avoid recomputing it every time.
    cwd_no_source_prefix := binary()
}.
-opaque t() :: #{
    status := status(),
    context => context()
}.
-export_type([status/0, target_node/0, context/0, t/0]).

-export([
    new/0,
    set_status/2,
    is_initialized/1,
    is_attached/1,
    set_context/2,
    get_context/1,
    is_valid_subscription/2
]).

-export([make_target_node/1]).

-include_lib("kernel/include/logger.hrl").

-spec new() -> t().
new() ->
    #{status => started}.

-spec set_status(t(), status()) -> t().
set_status(State, Status) ->
    State#{status => Status}.

-spec is_initialized(t()) -> boolean().
is_initialized(#{status := Status}) ->
    Status =/= started.

-spec is_attached(t()) -> boolean().
is_attached(#{status := Status}) ->
    case Status of
        {attached, _} -> true;
        _ -> false
    end.

-spec set_context(t(), context()) -> t().
set_context(State, Context) ->
    State#{context => Context}.

-spec get_context(t()) -> context().
get_context(#{context := Context}) ->
    Context.

-spec make_target_node(edb_dap_request_launch:target_node()) -> target_node().
make_target_node(#{name := Name} = TargetNode) ->
    #{
        name => binary_to_atom(Name),
        cookie => target_node_cookie(TargetNode),
        type => target_node_type(TargetNode)
    }.

% Internal functions
-spec target_node_cookie(edb_dap_request_launch:target_node()) -> atom().
target_node_cookie(#{cookie := Cookie}) ->
    binary_to_atom(Cookie);
target_node_cookie(_) ->
    erlang:get_cookie().

-spec target_node_type(edb_dap_request_launch:target_node()) -> target_node_type().
target_node_type(#{type := <<"shortnames">>}) ->
    shortnames;
target_node_type(#{type := <<"longnames">>}) ->
    longnames;
target_node_type(_) ->
    ?LOG_DEBUG("Missing or invalid target node type. Defaulting to shortnames", []),
    shortnames.

-spec is_valid_subscription(State :: t(), Subscription :: edb:event_subscription()) -> boolean().
is_valid_subscription(#{status := {attached, Subscription}}, Subscription) ->
    true;
is_valid_subscription(_State, _Subscription) ->
    false.
