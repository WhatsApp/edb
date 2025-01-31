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
-module(edb_dap_launch_config_SUITE).

%% erlfmt;ignore

% @fb-only
-oncall("whatsapp_server_devx").

% @fb-only: 
-include_lib("stdlib/include/assert.hrl").

%% CT callbacks
-export([all/0]).

%% Test cases
-export([
    test_validate/1
]).

all() ->
    [test_validate].

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

test_validate(_Config) ->
    ?assertEqual(
        {error, ~"invalid value"},
        edb_dap_launch_config:parse(foo)
    ),

    ?assertEqual(
        {error, ~"mandatory field missing 'launchCommand'"},
        edb_dap_launch_config:parse(#{})
    ),

    ?assertEqual(
        {error, ~"on field 'launchCommand': invalid value"},
        edb_dap_launch_config:parse(#{
            launchCommand => foo
        })
    ),

    ?assertEqual(
        {error, ~"on field 'launchCommand': mandatory field missing 'command'"},
        edb_dap_launch_config:parse(#{
            launchCommand => #{}
        })
    ),

    ?assertEqual(
        {error, ~"on field 'launchCommand.command': invalid value"},
        edb_dap_launch_config:parse(#{
            launchCommand => #{
                command => foo
            }
        })
    ),

    ?assertEqual(
        {error, ~"on field 'launchCommand': mandatory field missing 'cwd'"},
        edb_dap_launch_config:parse(#{
            launchCommand => #{
                command => ~"foo"
            }
        })
    ),

    ?assertEqual(
        {error, ~"on field 'launchCommand.cwd': invalid value"},
        edb_dap_launch_config:parse(#{
            launchCommand => #{
                command => ~"foo",
                cwd => blah
            }
        })
    ),
    ?assertEqual(
        {error, ~"on field 'launchCommand.arguments': invalid value"},
        edb_dap_launch_config:parse(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah",
                arguments => 42
            }
        })
    ),
    ?assertEqual(
        {error, ~"on field 'launchCommand': unexpected field: garments"},
        edb_dap_launch_config:parse(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah",
                garments => [~"foo", ~"bar"]
            }
        })
    ),

    ?assertEqual(
        {error, ~"mandatory field missing 'targetNode'"},
        edb_dap_launch_config:parse(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah"
            }
        })
    ),
    ?assertEqual(
        {error, ~"on field 'targetNode': invalid value"},
        edb_dap_launch_config:parse(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah"
            },
            targetNode => ~"some_node@localhost"
        })
    ),
    ?assertEqual(
        {error, ~"on field 'targetNode': mandatory field missing 'name'"},
        edb_dap_launch_config:parse(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah"
            },
            targetNode => #{}
        })
    ),

    ?assertEqual(
        {error, ~"on field 'targetNode.name': invalid value"},
        edb_dap_launch_config:parse(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah"
            },
            targetNode => #{
                name => true
            }
        })
    ),

    MinimalLaunchConfig = #{
        launchCommand => #{
            command => ~"foo",
            cwd => ~"/blah"
        },
        targetNode => #{
            name => ~"some_node@localhost"
        }
    },
    ?assertEqual(
        {ok, MinimalLaunchConfig},
        edb_dap_launch_config:parse(MinimalLaunchConfig)
    ),

    ?assertEqual(
        {error, ~"on field 'timeout': invalid value"},
        edb_dap_launch_config:parse(MinimalLaunchConfig#{timeout => on})
    ),
    ?assertEqual(
        {error, ~"on field 'stripSourcePrefix': invalid value"},
        edb_dap_launch_config:parse(MinimalLaunchConfig#{stripSourcePrefix => on})
    ),
    ?assertEqual(
        {error, ~"unexpected field: foo"},
        edb_dap_launch_config:parse(MinimalLaunchConfig#{foo => bar})
    ),

    MaximalLaunchConfig = #{
        launchCommand => #{
            cwd => ~"/foo/bar",
            command => ~"run-stuff.sh",
            arguments => [
                ~"arg1",
                ~"arg2",
                ~"arg3"
            ]
        },
        targetNode => #{
            name => ~"test42-123-atn@localhost",
            cookie => ~"connect_cookie",
            type => ~"shortnames"
        },
        timeout => 300,
        stripSourcePrefix => ~"blah/blah",

        % Ignored
        type => ~"edb",
        request => ~"~launch",
        name => ~"Some config",
        presentation => #{blah => blah},
        '__sessionId' => ~"some session"
    },
    ?assertEqual(
        {ok, MaximalLaunchConfig},
        edb_dap_launch_config:parse(MaximalLaunchConfig)
    ).
