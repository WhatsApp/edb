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
    test_run_in_terminal_requires_client_support/1,
    test_passes_run_in_terminal_stuff_to_client/1,
    test_respects_whatever_was_given_in_erl_zflags_env/1,
    test_checks_client_supports_argsCanBeInterpretedByShell/1
]).

all() ->
    [
        test_run_in_terminal_requires_client_support,
        test_passes_run_in_terminal_stuff_to_client,
        test_respects_whatever_was_given_in_erl_zflags_env,
        test_checks_client_supports_argsCanBeInterpretedByShell
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
        config => #{targetNode => #{name => 'foo@bar', cookie => some_cookie}}
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
        config => #{targetNode => #{name => 'foo@bar', cookie => some_cookie}}
    }),

    Expected = RunInTerminal#{
        kind => ~"external",
        env => #{
            'MY_VAR' => ~"my_value",
            'ERL_ZFLAGS' => null,

            % ERL_FLAGS is PATCHED
            'ERL_FLAGS' => ~"+D"
        }
    },
    {ok, [#{arguments := Actual}]} =
        edb_dap_test_client:wait_for_reverse_request(~"runInTerminal", Client),

    ?assertEqual(Expected, Actual),
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
            ~"ERL_FLAGS" => ~"+foo -bar baz"
        }
    },
    #{success := true} = edb_dap_test_client:launch(Client, #{
        runInTerminal => RunInTerminal,
        config => #{targetNode => #{name => 'foo@bar', cookie => some_cookie}}
    }),

    Expected = RunInTerminal#{
        env => #{
            'ERL_FLAGS' => ~"+foo -bar baz +D"
        }
    },
    {ok, [#{arguments := Actual}]} =
        edb_dap_test_client:wait_for_reverse_request(~"runInTerminal", Client),

    ?assertEqual(Expected, Actual),
    ok.

test_checks_client_supports_argsCanBeInterpretedByShell(Config) ->
    % Common "launch" args for "runInTerminal"
    LaunchArgsWithArgsCanBeInterpretedByShell = #{
        runInTerminal => #{
            cwd => ~"/tmp/blah",
            args => [~"erl", ~"--foo=$FOO_VAL"],
            argsCanBeInterpretedByShell => true
        },
        config => #{targetNode => #{name => 'foo@bar', cookie => some_cookie}}
    },

    {ok, Client1} = edb_dap_test_support:start_test_client(Config),
    #{success := true} = edb_dap_test_client:initialize(Client1, #{
        adapterID => ~"edb for BSCode",
        supportsRunInTerminalRequest => true
    }),
    #{success := false, body := #{error := #{format := ~"argsCanBeInterpretedByShell is not supported by the client"}}} =
        edb_dap_test_client:launch(Client1, LaunchArgsWithArgsCanBeInterpretedByShell),

    ok.
