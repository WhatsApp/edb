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

-module(edb_dap_language_SUITE).

-oncall("whatsapp_server_devx").

-include_lib("assert/include/assert.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([test_set_breakpoint_with_custom_dap_language/1]).

%% edb_dap_language callbacks
-export([init/0, source_to_modules/3]).

all() ->
    [
        test_set_breakpoint_with_custom_dap_language
    ].

init_per_testcase(_TestCase, Config) ->
    {ok, _} = application:ensure_all_started(edb_core),
    ok = application:set_env(edb, dap_language, ?MODULE),
    {ok, _} = edb_dap_language:start_link(),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok = stop_language_server(),
    application:unset_env(edb, dap_language),
    application:unset_env(edb, dap_language_test_state),
    _ = application:stop(edb_core),
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_set_breakpoint_with_custom_dap_language(Config) ->
    Module = edb_custom_language_target,
    {ok, #{node := Node, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{
        modules => [
            {source, [
                ~"-module(edb_custom_language_target).\n",
                ~"-export([go/0]).\n",
                ~"go() ->\n",
                ~"    ok.\n"
            ]}
        ]
    }),
    ok = edb:attach(#{node => Node, cookie => Cookie}),

    SourcePath = ~"custom://source.edbtest",
    BreakpointLines = [4],
    DapLanguageState0 = #{
        modules_by_source => #{SourcePath => [Module]},
        source_lookups => []
    },
    application:set_env(edb, dap_language_test_state, DapLanguageState0),
    ok = edb_dap_language:reset(),
    Reaction = edb_dap_request_set_breakpoints:handle(
        #{state => attached},
        #{
            source => #{path => SourcePath},
            breakpoints => [#{line => Line} || Line <- BreakpointLines]
        }
    ),

    ?assertMatch(
        #{
            response :=
                #{
                    success := true,
                    body := #{breakpoints := [#{line := 4, verified := true}]}
                }
        },
        Reaction
    ),
    #{callback_state := #{source_lookups := [{SourcePath, BreakpointLines}]}} = sys:get_state(edb_dap_language),
    ok.

%%--------------------------------------------------------------------
%% edb_dap_language callbacks
%%--------------------------------------------------------------------
init() ->
    application:get_env(edb, dap_language_test_state, #{source_lookups => []}).

source_to_modules(Path, Lines, State0 = #{modules_by_source := ModulesBySource}) ->
    Modules = maps:get(Path, ModulesBySource),
    SourceLookups = maps:get(source_lookups, State0),
    State1 = State0#{source_lookups => SourceLookups ++ [{Path, Lines}]},
    {ok, Modules, State1}.

stop_language_server() ->
    case erlang:whereis(edb_dap_language) of
        undefined -> ok;
        Pid -> gen_server:stop(Pid)
    end.
