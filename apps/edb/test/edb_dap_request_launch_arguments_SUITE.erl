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
-module(edb_dap_request_launch_arguments_SUITE).

%% erlfmt;ignore

% @fb-only
-oncall("whatsapp_server_devx").

-include_lib("assert/include/assert.hrl").

%% CT callbacks
-export([all/0]).

%% Test cases
-export([
    test_validate/1
]).

all() ->
    [
        test_validate
    ].

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

test_validate(_Config) ->
    Minimal = #{
        runInTerminal => #{
            args => [~"foo"],
            cwd => ~"/blah"
        },
        config => #{
            nameDomain => ~"shortnames"
        }
    },

    ExpectedMinimal = #{
        runInTerminal => #{
            args => [~"foo"],
            cwd => ~"/blah"
        },
        config => #{
            nameDomain => shortnames
        }
    },

    ?assertEqual(
        {ok, ExpectedMinimal},
        edb_dap_request_launch:parse_arguments(Minimal#{})
    ),

    Maximal = #{
        irrelevantStuff => ~"blah",

        runInTerminal => #{
            kind => ~"integrated",
            title => ~"Some title",
            cwd => ~"/foo/bar",
            args => [
                ~"run-stuff.sh",
                ~"arg1",
                ~"arg2",
                ~"arg3"
            ],
            env => #{
                ~"SOME_ENV" => ~"some value",
                ~"ANOTHER_ENV" => null
            },
            argsCanBeInterpretedByShell => true
        },
        config => #{
            nameDomain => ~"shortnames",
            nodeInitCodeInEnvVar => ~"EDB_DAP_INIT_CODE",
            timeout => 300,
            stripSourcePrefix => ~"blah/blah"
        }
    },
    ExpectedMaximal = #{
        runInTerminal => #{
            kind => integrated,
            title => ~"Some title",
            cwd => ~"/foo/bar",
            args => [
                ~"run-stuff.sh",
                ~"arg1",
                ~"arg2",
                ~"arg3"
            ],
            env => #{
                ~"SOME_ENV" => ~"some value",
                ~"ANOTHER_ENV" => null
            },
            argsCanBeInterpretedByShell => true
        },
        config => #{
            nameDomain => shortnames,
            nodeInitCodeInEnvVar => ~"EDB_DAP_INIT_CODE",
            timeout => 300,
            stripSourcePrefix => ~"blah/blah"
        }
    },

    ?assertEqual(
        {ok, ExpectedMaximal},
        edb_dap_request_launch:parse_arguments(Maximal)
    ).
