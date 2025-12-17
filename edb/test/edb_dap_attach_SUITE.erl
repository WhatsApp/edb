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

%% Attaching tests for the EDB DAP adapter

-module(edb_dap_attach_SUITE).

%% erlfmt:ignore
% @fb-only: -oncall("whatsapp_server_devx").

% @fb-only: % elp:fixme WA003 - Open source app
-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([test_attaches_if_node_is_alive/1]).
-export([test_fails_to_attach_if_node_is_down/1]).
-export([test_fails_to_attach_if_wrong_cookie_is_given/1]).
-export([test_validates_input/1]).

all() ->
    [
        test_attaches_if_node_is_alive,
        test_fails_to_attach_if_node_is_down,
        test_fails_to_attach_if_wrong_cookie_is_given,
        test_validates_input
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_attaches_if_node_is_alive(Config) ->
    % Start a debuggee node
    {ok, #{node := DebuggeeNode, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),

    % Start a client and connect
    {ok, Client} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client, #{adapterID => ~"edb for BSCode"}),

    % Attach to the node
    #{success := true} = edb_dap_test_client:attach(Client, #{
        config => #{
            node => DebuggeeNode,
            cookie => Cookie,
            cwd => cwd(Config)
        }
    }),

    {ok, [#{event := ~"initialized"}]} = edb_dap_test_client:wait_for_event(~"initialized", Client),
    ok.

test_fails_to_attach_if_node_is_down(Config) ->
    % Random node to ensure it is not up
    DownNode = edb_test_support:random_node("downer"),

    % Start a client and connect
    {ok, Client} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client, #{adapterID => ~"edb for BSCode"}),

    % Attaching fails
    #{success := false, body := #{error := #{format := ~"Node not found"}}} = edb_dap_test_client:attach(Client, #{
        config => #{
            node => DownNode,
            cwd => cwd(Config)
        }
    }),

    Config.

test_fails_to_attach_if_wrong_cookie_is_given(Config) ->
    % Start a debuggee node
    {ok, #{node := DebuggeeNode, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),

    % Start a client and connect
    {ok, Client} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client, #{adapterID => ~"edb for BSCode"}),

    WrongCookie = binary_to_atom(<<"Wrong", (atom_to_binary(Cookie))/binary>>),

    % Attach to the node
    #{success := false, body := #{error := #{format := ~"Node not found"}}} = edb_dap_test_client:attach(Client, #{
        config => #{
            node => DebuggeeNode,
            cookie => WrongCookie,
            cwd => cwd(Config)
        }
    }),

    % But we can still succeed if we use the right cookie
    #{success := true} = edb_dap_test_client:attach(Client, #{
        config => #{
            node => DebuggeeNode,
            cookie => Cookie,
            cwd => cwd(Config)
        }
    }),

    {ok, [#{event := ~"initialized"}]} = edb_dap_test_client:wait_for_event(~"initialized", Client),
    ok.

test_validates_input(Config) ->
    % Start a debuggee node
    {ok, #{node := DebuggeeNode, cookie := Cookie}} = edb_test_support:start_peer_node(Config, #{}),

    % Start a client and connect
    {ok, Client} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client, #{adapterID => ~"edb for BSCode"}),

    % Try to attach with bad arguments
    #{
        success := false,
        body := #{error := #{format := ~"Invalid parameters: on field 'config.stripSourcePrefix': invalid value"}}
    } =
        % eqwalizer:ignore: We are actually trying to send a request with the wrong type
        edb_dap_test_client:attach(Client, #{
            config => #{
                node => DebuggeeNode,
                cookie => Cookie,
                cwd => cwd(Config),
                stripSourcePrefix => 42
            }
        }),

    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
-spec cwd(ct_suite:ct_config()) -> binary().
cwd(Config) ->
    PrivDir = ?config(priv_dir, Config),
    case unicode:characters_to_binary(PrivDir) of
        Cwd when is_binary(Cwd) -> Cwd
    end.
