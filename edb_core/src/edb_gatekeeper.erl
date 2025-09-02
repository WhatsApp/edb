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
%% % @format
%%
%% Ephemeral gen_server that waits for a freshly launched debuggee node
%% to reverse-attach

-module(edb_gatekeeper).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-moduledoc false.

-behavior(gen_server).

%% Public API
-export([new/0, new/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2]).

%% -------------------------------------------------------------------
%% Types
%% -------------------------------------------------------------------
-export_type([id/0]).
-opaque id() :: integer().

-type state() :: #{id := id(), multi_node_enabled := boolean()}.

%% -------------------------------------------------------------------
%% Public API
%% -------------------------------------------------------------------
-spec new() -> {ok, Id, CallGatekeeperCode} when
    Id :: id(),
    CallGatekeeperCode :: binary().
-spec new(Options) -> {ok, Id, CallGatekeeperCode} when
    Options :: #{multi_node_enabled => boolean()},
    Id :: id(),
    CallGatekeeperCode :: binary().
new() ->
    new(#{}).
new(Options) when node() /= 'nonode@nohost' ->
    Id = erlang:unique_integer([positive]),
    GatekeeperName = binary_to_atom(list_to_binary(io_lib:format("edb-~p", [Id]))),

    {ok, _Pid} = gen_server:start(
        {local, GatekeeperName},
        ?MODULE,
        Options#{id => Id},
        []
    ),

    #{name_domain := NameDomain} = net_kernel:get_state(),

    CallGatekeeperCode = io_lib:format(
        ~"""
        case net_kernel:get_state() of
        #{started := no} -> {ok, _} = net_kernel:start(undefined, #{name_domain => ~p});
        _ -> ok
        end,
        erlang:set_cookie(~p, ~p),
        true = net_kernel:connect_node(~p),
        ok = gen_server:call({~p, ~p}, [])
        """,
        [
            NameDomain,
            node(),
            erlang:get_cookie(),
            node(),
            GatekeeperName,
            node()
        ]
    ),

    SingleLine = iolist_to_binary(re:replace(CallGatekeeperCode, "\\n", " ", [global])),
    {ok, Id, SingleLine}.

%% -------------------------------------------------------------------
%% gen_server callbacks
%% -------------------------------------------------------------------

-spec init(#{id := Id, multi_node_enabled => MultiNodeEnabled}) -> {ok, state()} when
    Id :: id(),
    MultiNodeEnabled :: boolean().
init(Options = #{id := Id}) ->
    MultiNodeEnabled = maps:get(multi_node_enabled, Options, false),
    State0 = #{id => Id, multi_node_enabled => MultiNodeEnabled},
    {ok, State0}.

-spec handle_call([], From, state()) -> {noreply, state()} | {stop, normal, state()} when
    From :: gen_server:from().
handle_call([], From, State = #{id := Id, multi_node_enabled := MultiNodeEnabled}) ->
    {ClientPid, _ReplayTag} = From,
    DebuggeeNode = node(ClientPid),
    ok = edb_node_monitor:reverse_attach_notification(Id, DebuggeeNode),
    gen_server:reply(From, ok),
    case MultiNodeEnabled of
        true ->
            {noreply, State};
        false ->
            {stop, normal, State}
    end.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_, State) ->
    {noreply, State}.
