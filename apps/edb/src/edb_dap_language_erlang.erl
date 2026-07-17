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

-module(edb_dap_language_erlang).

-oncall("whatsapp_server_devx").
-moduledoc """
Default Erlang language hooks.
""".
-compile(warn_missing_spec_all).

-behaviour(edb_dap_language).

-export([init/0, source_to_modules/3]).

-type state() :: #{}.

-spec init() -> state().
init() ->
    #{}.

-spec source_to_modules(Path, Lines, State) -> {ok, [module()], State} when
    Path :: binary(),
    Lines :: [edb:line()],
    State :: state().
source_to_modules(Path, _Lines, State) ->
    Extension = filename:extension(Path),
    ModuleName = filename:basename(Path, Extension),
    case unicode:characters_to_binary(ModuleName) of
        ModuleNameBin when is_binary(ModuleNameBin) ->
            {ok, [binary_to_atom(ModuleNameBin)], State}
    end.
