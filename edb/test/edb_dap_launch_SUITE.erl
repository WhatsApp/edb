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

%% Tests for the "launch" request of the EDB DAP server

-module(edb_dap_launch_SUITE).

%% erlfmt:ignore
% @fb-only: -oncall("whatsapp_server_devx").
-typing([eqwalizer]).

-include_lib("assert/include/assert.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_run_in_terminal_requires_client_support/1,
    test_passes_run_in_terminal_stuff_to_client/1,
    test_respects_whatever_was_given_in_erl_zflags_env/1,
    test_checks_client_supports_argsCanBeInterpretedByShell/1,
    test_can_inject_code_automatically/1,
    test_can_return_the_code_to_inject_in_an_env_var/1,
    test_it_honors_the_timeout/1
]).

all() ->
    [
        test_run_in_terminal_requires_client_support,
        test_passes_run_in_terminal_stuff_to_client,
        test_respects_whatever_was_given_in_erl_zflags_env,
        test_checks_client_supports_argsCanBeInterpretedByShell,
        test_can_inject_code_automatically,
        test_can_return_the_code_to_inject_in_an_env_var,
        test_it_honors_the_timeout
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_run_in_terminal_requires_client_support(Config) ->
    % Common "launch" args for "runInTerminal"
    LaunchArgs = #{
        runInTerminal => #{cwd => ~"/tmp/blah", args => [~"erl"]},
        config => #{nameDomain => shortnames}
    },

    % CASE 1: supportsRunInTerminal not given, no client name given either
    {ok, Client1} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client1, #{
        adapterID => ~"edb for BSCode"
    }),
    #{success := false, body := #{error := #{format := ~"runInTerminal is not supported by the client"}}} =
        edb_dap_test_client:launch(Client1, LaunchArgs),

    % CASE 2: supportsRunInTerminal explicitly false, client name given
    {ok, Client2} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client2, #{
        adapterID => ~"edb for BSCode",
        clientName => ~"BSCode 2.71828",
        supportsRunInTerminalRequest => false
    }),
    #{success := false, body := #{error := #{format := ~"runInTerminal is not supported by BSCode 2.71828"}}} =
        edb_dap_test_client:launch(Client2, LaunchArgs),

    ok.

test_passes_run_in_terminal_stuff_to_client(Config) ->
    {ok, Client} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client, #{
        adapterID => ~"edb for BSCode",
        supportsRunInTerminalRequest => true,
        supportsArgsCanBeInterpretedByShell => true
    }),

    RunInTerminal = #{
        kind => external,
        title => ~"My debugging session",
        cwd => ~"/tmp/blah",
        args => [~"erl"],
        env => #{
            ~"MY_VAR" => ~"my_value",
            ~"ERL_ZFLAGS" => null
        },
        argsCanBeInterpretedByShell => true
    },
    #{success := true} = edb_dap_test_client:launch(Client, #{
        runInTerminal => RunInTerminal,
        config => #{
            nameDomain => longnames,
            nodeInitCodeInEnvVar => ~"EDB_DAP_DEBUGGEE_INIT"
        }
    }),

    {ok, [#{arguments := Actual}]} =
        edb_dap_test_client:wait_for_reverse_request(~"runInTerminal", Client),

    OLD_ERL_AFLAGS = list_to_binary(
        % elp:ignore WA014 (no_os_get_env) test parametrisation
        case os:getenv("ERL_AFLAGS", "") of
            "" -> "";
            Flags -> " " ++ Flags
        end
    ),

    ?assertMatch(
        #{
            kind := ~"external",
            title := ~"My debugging session",
            cwd := ~"/tmp/blah",
            args := [~"erl"],
            env := #{
                'MY_VAR' := ~"my_value",
                'ERL_ZFLAGS' := null,

                % ERL_AFLAGS is PATCHED
                'ERL_AFLAGS' := <<"+D", OLD_ERL_AFLAGS/binary>>,

                % Added by DAP server
                'EDB_DAP_DEBUGGEE_INIT' := _
            }
        },
        Actual
    ),
    ok.

test_respects_whatever_was_given_in_erl_zflags_env(Config) ->
    {ok, Client} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client, #{
        adapterID => ~"edb for BSCode",
        supportsRunInTerminalRequest => true
    }),

    RunInTerminal = #{
        cwd => ~"/tmp/blah",
        args => [~"erl"],
        env => #{
            ~"ERL_AFLAGS" => ~"+foo -bar baz"
        }
    },
    #{success := true} = edb_dap_test_client:launch(Client, #{
        runInTerminal => RunInTerminal,
        config => #{
            nameDomain => shortnames,
            nodeInitCodeInEnvVar => ~"EDB_DAP_DEBUGGEE_INIT"
        }
    }),

    {ok, [#{arguments := Actual}]} =
        edb_dap_test_client:wait_for_reverse_request(~"runInTerminal", Client),

    ?assertMatch(
        #{
            cwd := ~"/tmp/blah",
            args := [~"erl"],
            env := #{
                'ERL_AFLAGS' := ~"+D +foo -bar baz",
                'EDB_DAP_DEBUGGEE_INIT' := _
            }
        },
        Actual
    ),
    ok.

test_checks_client_supports_argsCanBeInterpretedByShell(Config) ->
    % Common "launch" args for "runInTerminal"
    LaunchArgsWithArgsCanBeInterpretedByShell = #{
        runInTerminal => #{
            cwd => ~"/tmp/blah",
            args => [~"erl", ~"--foo=$FOO_VAL"],
            argsCanBeInterpretedByShell => true
        },
        config => #{nameDomain => longnames}
    },

    {ok, Client1} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client1, #{
        adapterID => ~"edb for BSCode",
        supportsRunInTerminalRequest => true
    }),
    #{success := false, body := #{error := #{format := ~"argsCanBeInterpretedByShell is not supported by the client"}}} =
        edb_dap_test_client:launch(Client1, LaunchArgsWithArgsCanBeInterpretedByShell),

    ok.

test_can_inject_code_automatically(Config) ->
    % Start client
    {ok, Client} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client, #{
        adapterID => ~"edb for BSCode",
        supportsRunInTerminalRequest => true
    }),

    % Send "launch" request, and wait for "runInTerminal" request
    #{success := true} = edb_dap_test_client:launch(Client, #{
        runInTerminal => #{
            cwd => ~"/tmp/blah",
            args => [~"erl"]
        },
        config => #{
            nameDomain => shortnames,
            timeout => 20
        }
    }),
    {ok, [RunInTerminalReq]} = edb_dap_test_client:wait_for_reverse_request(~"runInTerminal", Client),
    edb_dap_test_client:respond_success(Client, RunInTerminalReq, #{}),

    % Get the init code, and use it to start the debuggee
    #{arguments := #{env := Env}} = RunInTerminalReq,
    {ok, _PeerInfo} = edb_test_support:start_peer_node(Config, #{
        env => #{atom_to_binary(K) => V || K := V <- Env}
    }),
    % As the debuggee is up and ran the InitCode, the DAP server should send us an "initialized" event
    {ok, [#{event := ~"initialized"}]} = edb_dap_test_client:wait_for_event(~"initialized", Client),

    % Let's skip the configuration phase
    #{success := true} = edb_dap_test_client:configuration_done(Client),

    % Sanity-check: we get some processes
    #{success := true, body := #{threads := [_ | _]}} = edb_dap_test_client:threads(Client),

    ok.

test_can_return_the_code_to_inject_in_an_env_var(Config) ->
    % Start client
    {ok, Client} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client, #{
        adapterID => ~"edb for BSCode",
        supportsRunInTerminalRequest => true
    }),

    % Send "launch" request, and wait for "runInTerminal" request
    #{success := true} = edb_dap_test_client:launch(Client, #{
        runInTerminal => #{
            cwd => ~"/tmp/blah",
            args => [~"erl"]
        },
        config => #{
            nameDomain => shortnames,
            nodeInitCodeInEnvVar => ~"EDB_DAP_DEBUGGEE_INIT",
            timeout => 20
        }
    }),
    {ok, [RunInTerminalReq]} = edb_dap_test_client:wait_for_reverse_request(~"runInTerminal", Client),
    edb_dap_test_client:respond_success(Client, RunInTerminalReq, #{}),

    % Get the init code, and use it to start the debuggee
    #{arguments := #{env := #{'EDB_DAP_DEBUGGEE_INIT' := InitCode}}} = RunInTerminalReq,
    {ok, _PeerInfo} = edb_test_support:start_peer_node(Config, #{
        extra_args => ["-eval", InitCode]
    }),
    % As the debuggee is up and ran the InitCode, the DAP server should send us an "initialized" event
    {ok, [#{event := ~"initialized"}]} = edb_dap_test_client:wait_for_event(~"initialized", Client),

    % Let's skip the configuration phase
    #{success := true} = edb_dap_test_client:configuration_done(Client),

    % Sanity-check: we get some processes
    #{success := true, body := #{threads := [_ | _]}} = edb_dap_test_client:threads(Client),

    ok.

test_it_honors_the_timeout(Config) ->
    % Start client
    {ok, Client} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client, #{
        adapterID => ~"edb for BSCode",
        supportsRunInTerminalRequest => true
    }),

    % Send "launch" request, and wait for "runInTerminal" request
    #{success := true} = edb_dap_test_client:launch(Client, #{
        runInTerminal => #{
            cwd => ~"/tmp/blah",
            args => [~"erl"]
        },
        config => #{
            nameDomain => shortnames,
            % ! ms
            timeout => 1
        }
    }),
    {ok, [RunInTerminalReq]} = edb_dap_test_client:wait_for_reverse_request(~"runInTerminal", Client),
    edb_dap_test_client:respond_success(Client, RunInTerminalReq, #{}),

    % We DONT start the debuggee, so the DAP server should send us a "terminated" event
    {ok, [#{event := ~"terminated"}]} = edb_dap_test_client:wait_for_event(~"terminated", Client),
    ok.
