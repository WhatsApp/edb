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
%% @format
%%
-module(prepare_edb_tests).
-compile(warn_missing_spec_all).
-oncall("was_devx").

-export([init/1, do/1, format_error/1]).

-include_lib("kernel/include/file.hrl").

-define(PROVIDER, prepare_edb_tests).
-define(DEPS, [escriptize]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {module, ?MODULE},
        {bare, true},
        {deps, ?DEPS},
        {example, "rebar3 prepare_edb_tests"},
        {short_desc, "Copy edb binary to test data directories"},
        {desc, "Copies the edb binary to all test suite data directories in edb app"},
        {opts, []}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, term()}.
do(State) ->
    rebar_api:info("Copying edb binary to test data directories...", []),

    App = rebar_state:current_app(State),
    ProfileDir = rebar_dir:profile_dir(rebar_state:opts(State), rebar_state:current_profiles(State)),
    BinarySrc = filename:join([ProfileDir, "bin", "edb"]),

    case filelib:is_file(BinarySrc) of
        false ->
            {error, {?MODULE, {binary_not_found, BinarySrc}}};
        true ->
            SrcTestDir = filename:join([rebar_app_info:dir(App), "test"]),
            Suites = discover_suites(SrcTestDir),

            OutTestDir = filename:join([rebar_app_info:out_dir(App), "test"]),

            lists:foreach(
                fun(Suite) ->
                    DataDir = filename:join([OutTestDir, Suite ++ "_data"]),
                    ok = filelib:ensure_path(DataDir),
                    Dest = filename:join([DataDir, "edb"]),
                    {ok, _} = file:copy(BinarySrc, Dest),
                    case os:type() of
                        {unix, _} ->
                            {ok, #file_info{mode = Mode}} = file:read_file_info(BinarySrc),
                            file:change_mode(Dest, Mode);
                        _ ->
                            ok
                    end
                end,
                Suites
            ),
            rebar_api:info("Copied binary to ~p test suites", [length(Suites)]),
            {ok, State}
    end.

-spec format_error(term()) -> iolist().
format_error({binary_not_found, Path}) ->
    io_lib:format("edb binary not found at ~s", [Path]);
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%% Discover all test suites in the edb app
-spec discover_suites(file:filename()) -> [string()].
discover_suites(TestDir) ->
    Pattern = filename:join([TestDir, "*_SUITE.erl"]),
    Files = filelib:wildcard(Pattern),
    [filename:basename(F, ".erl") || F <- Files].
