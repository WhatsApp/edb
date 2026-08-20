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

-module(edb_dap_language).

-oncall("whatsapp_server_devx").
-moduledoc """
Language-specific hooks for the DAP adapter.
""".
-compile(warn_missing_spec_all).

-behaviour(gen_server).

-export([start_link/0]).
-export([source_to_modules/2]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).

-export_type([state/0, source_to_modules_result/0]).

-include_lib("kernel/include/logger.hrl").

-define(SERVER, ?MODULE).

-type state() :: dynamic().
-type source_to_modules_result() :: {ok, [module()]} | {error, binary()}.
-type server_state() :: #{
    impl := module(),
    callback_state := state()
}.

-doc """
Initializes language-specific state for one debug session.
""".
-callback init() -> state().

-doc """
Maps a source path and the requested breakpoint lines in that source to the
runtime modules that should receive those breakpoints.

Return `{ok, Modules, State}` when the lookup ran successfully. `Modules` may be
empty when the source does not map to any module known to the implementation.
Return `{error, Reason, State}` when the lookup could not be performed; `Reason`
is shown to the DAP client.
""".
-callback source_to_modules(Path, Lines, State) -> {ok, Modules, State} | {error, Reason, State} when
    Path :: binary(),
    Lines :: [edb:line()],
    Modules :: [module()],
    Reason :: binary(),
    State :: state().

-spec start_link() -> gen_server:start_ret().
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec source_to_modules(Path, Lines) -> source_to_modules_result() when
    Path :: binary(),
    Lines :: [edb:line()].
source_to_modules(Path, Lines) ->
    gen_server:call(?SERVER, {source_to_modules, Path, Lines}).

-spec init([]) -> {ok, server_state()}.
init([]) ->
    {ok, init_state()}.

-spec handle_call(term(), term(), server_state()) -> {reply, term(), server_state()}.
handle_call({source_to_modules, Path, Lines}, _From, State0 = #{impl := Impl, callback_state := CallbackState0}) ->
    case Impl:source_to_modules(Path, Lines, CallbackState0) of
        {ok, Modules, CallbackState1} ->
            {reply, {ok, Modules}, State0#{callback_state := CallbackState1}};
        {error, Reason, CallbackState1} ->
            {reply, {error, Reason}, State0#{callback_state := CallbackState1}}
    end.

-spec handle_cast(term(), server_state()) -> {noreply, server_state()}.
handle_cast(Unexpected, State) ->
    ?LOG_WARNING("Unexpected message: ~p", [Unexpected]),
    {noreply, State}.

-spec handle_info(term(), server_state()) -> {noreply, server_state()}.
handle_info(Unexpected, State) ->
    ?LOG_WARNING("Unexpected message: ~p", [Unexpected]),
    {noreply, State}.

-spec init_state() -> server_state().
init_state() ->
    Impl = application:get_env(edb, dap_language, edb_dap_language_erlang),
    #{impl => Impl, callback_state => Impl:init()}.
