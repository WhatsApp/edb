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

%% Scopes/variables tests for the EDB DAP adapter

-module(edb_dap_scopes_SUITE).

%% erlfmt:ignore
% @fb-only
-typing([eqwalizer]).

% @fb-only
-include_lib("stdlib/include/assert.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_reports_locals_scope/1,
    test_reports_registers_scope_when_locals_not_available/1,
    test_reports_messages_scope/1
]).

all() ->
    [
        test_reports_locals_scope,
        test_reports_registers_scope_when_locals_not_available,
        test_reports_messages_scope
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_reports_locals_scope(Config) ->
    {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),
    {ok, Client, _Cwd} = edb_dap_test_support:start_session(Config, Node, Cookie),
    ModuleSource = iolist_to_binary([
        ~"-module(foo).     %L01\n",
        ~"-export([go/2]).  %L02\n",
        ~"go(X, Y) ->       %L03\n",
        ~"    X + 2 * Y.    %L04\n"
    ]),
    {ok, _ThreadId, ST} = edb_dap_test_support:ensure_process_in_bp(
        Config, Client, Peer, {source, ModuleSource}, go, [42, 7], {line, 4}
    ),
    case ST of
        [#{id := TopFrameId} | _] ->
            Scopes = edb_dap_test_support:get_scopes(Client, TopFrameId),
            ?assertEqual(
                #{
                    ~"Locals" =>
                        #{
                            name => ~"Locals",
                            expensive => false,
                            presentationHint => ~"locals",
                            variablesReference => 1
                        }
                },
                Scopes
            ),

            LocalVars = edb_dap_test_support:get_variables(Client, maps:get(~"Locals", Scopes)),
            ?assertEqual(
                #{
                    ~"X" => #{name => ~"X", value => ~"42", variablesReference => 0},
                    ~"Y" => #{name => ~"Y", value => ~"7", variablesReference => 0}
                },
                LocalVars
            )
    end,
    ok.

test_reports_registers_scope_when_locals_not_available(Config) ->
    {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),
    {ok, Client, _Cwd} = edb_dap_test_support:start_session(Config, Node, Cookie),
    ModuleSource = iolist_to_binary([
        ~"-module(foo).     %L01\n",
        ~"-export([go/2]).  %L02\n",
        ~"go(X, Y) ->       %L03\n",
        ~"    X + 2 * Y.    %L04\n"
    ]),
    {ok, _ThreadId, ST} = edb_dap_test_support:ensure_process_in_bp(
        Config, Client, Peer, {source, ModuleSource}, go, [42, 7], {line, 4}
    ),
    case ST of
        [_, #{id := NonTopFrameId} | _] ->
            Scopes = edb_dap_test_support:get_scopes(Client, NonTopFrameId),
            ?assertEqual(
                #{
                    ~"Registers" =>
                        #{
                            name => ~"Registers",
                            expensive => false,
                            presentationHint => ~"registers",
                            variablesReference => 1
                        }
                },
                Scopes
            ),

            RegVars = edb_dap_test_support:get_variables(Client, maps:get(~"Registers", Scopes)),
            ?assertMatch(
                #{
                    ~"Y0" := #{name := ~"Y0", value := _, variablesReference := 0},
                    ~"Y1" := #{name := ~"Y1", value := _, variablesReference := 0},
                    ~"Y2" := #{name := ~"Y2", value := _, variablesReference := 0},
                    ~"Y3" := #{name := ~"Y3", value := _, variablesReference := 0}
                },
                RegVars
            )
    end,
    ok.

test_reports_messages_scope(Config) ->
    {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, #{}),
    {ok, Client, _Cwd} = edb_dap_test_support:start_session(Config, Node, Cookie),
    ModuleSource = iolist_to_binary([
        ~"-module(foo).      %L01\n",
        ~"-export([go/2]).   %L02\n",
        ~"go(X, Y) ->        %L03\n",
        ~"    self() ! hola, %L04\n",
        ~"    X + 2 * Y.     %L05\n"
    ]),
    {ok, _ThreadId, ST} = edb_dap_test_support:ensure_process_in_bp(
        Config, Client, Peer, {source, ModuleSource}, go, [42, 7], {line, 5}
    ),
    case ST of
        [_, #{id := NonTopFrameId} | _] ->
            Scopes = edb_dap_test_support:get_scopes(Client, NonTopFrameId),
            ?assertEqual(
                #{
                    ~"Messages" =>
                        #{
                            name => ~"Messages",
                            expensive => false,
                            variablesReference => 2
                        },
                    ~"Registers" =>
                        #{
                            name => ~"Registers",
                            expensive => false,
                            presentationHint => ~"registers",
                            variablesReference => 1
                        }
                },
                Scopes
            ),

            RegVars = edb_dap_test_support:get_variables(Client, maps:get(~"Messages", Scopes)),
            ?assertMatch(
                #{
                    ~"0" := #{name := ~"0", value := _, variablesReference := 0}
                },
                RegVars
            )
    end,
    ok.
