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
-typing([eqwalizer]).

% @fb-only
-include_lib("stdlib/include/assert.hrl").

%% CT callbacks
-export([all/0]).

%% Test cases
-export([
    test_validate_old_style/1,
    test_validate/1
]).

all() ->
    [
        test_validate_old_style,
        test_validate
    ].

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

test_validate_old_style(_Config) ->
    ?assertEqual(
        {error, ~"invalid value"},
        % eqwalizer:ignore Checking that parsing works on random input
        edb_dap_request_launch:parse_arguments(foo)
    ),

    ?assertEqual(
        {error, ~"on field 'launchCommand': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => foo
        })
    ),

    ?assertEqual(
        {error, ~"on field 'launchCommand': mandatory field missing 'command'"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => #{}
        })
    ),

    ?assertEqual(
        {error, ~"on field 'launchCommand.command': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => #{
                command => foo
            }
        })
    ),

    ?assertEqual(
        {error, ~"on field 'launchCommand': mandatory field missing 'cwd'"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => #{
                command => ~"foo"
            }
        })
    ),

    ?assertEqual(
        {error, ~"on field 'launchCommand.cwd': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => #{
                command => ~"foo",
                cwd => blah
            }
        })
    ),
    ?assertEqual(
        {error, ~"on field 'launchCommand.arguments': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah",
                arguments => 42
            }
        })
    ),
    ?assertEqual(
        {error, ~"on field 'launchCommand': unexpected field: garments"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah",
                garments => [~"foo", ~"bar"]
            }
        })
    ),

    ?assertEqual(
        {error, ~"mandatory field missing 'targetNode'"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah"
            }
        })
    ),
    ?assertEqual(
        {error, ~"on field 'targetNode': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah"
            },
            targetNode => ~"some_node@localhost"
        })
    ),
    ?assertEqual(
        {error, ~"on field 'targetNode': mandatory field missing 'name'"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah"
            },
            targetNode => #{}
        })
    ),

    ?assertEqual(
        {error, ~"on field 'targetNode.name': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah"
            },
            targetNode => #{
                name => 42
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
        {ok, MinimalLaunchConfig#{targetNode => #{name => 'some_node@localhost'}}},
        edb_dap_request_launch:parse_arguments(MinimalLaunchConfig)
    ),

    ?assertEqual(
        {error, ~"on field 'timeout': invalid value"},
        edb_dap_request_launch:parse_arguments(MinimalLaunchConfig#{timeout => on})
    ),
    ?assertEqual(
        {error, ~"on field 'stripSourcePrefix': invalid value"},
        edb_dap_request_launch:parse_arguments(MinimalLaunchConfig#{stripSourcePrefix => on})
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
        stripSourcePrefix => ~"blah/blah"
    },

    MaximalLaunchConfigWithExtraStuff = MaximalLaunchConfig#{
        % Anything else is Ignored
        type => ~"edb",
        request => ~"launch",
        name => ~"Some config",
        presentation => #{blah => blah},
        '__sessionId' => ~"some session"
    },
    ?assertEqual(
        {ok, MaximalLaunchConfig#{
            targetNode => #{
                name => 'test42-123-atn@localhost',
                cookie => 'connect_cookie',
                type => 'shortnames'
            }
        }},
        edb_dap_request_launch:parse_arguments(MaximalLaunchConfigWithExtraStuff)
    ).

test_validate(_Config) ->
    ?assertEqual(
        {error, ~"invalid value"},
        % eqwalizer:ignore Checking that parsing works on random input
        edb_dap_request_launch:parse_arguments(foo)
    ),

    ?assertEqual(
        {error, ~"on field 'config.launchCommand': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => foo
            }
        })
    ),

    ?assertEqual(
        {error, ~"on field 'config.launchCommand': mandatory field missing 'command'"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => #{}
            }
        })
    ),

    ?assertEqual(
        {error, ~"on field 'config.launchCommand.command': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => #{
                    command => foo
                }
            }
        })
    ),

    ?assertEqual(
        {error, ~"on field 'config.launchCommand': mandatory field missing 'cwd'"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => #{
                    command => ~"foo"
                }
            }
        })
    ),

    ?assertEqual(
        {error, ~"on field 'config.launchCommand.cwd': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => #{
                    command => ~"foo",
                    cwd => blah
                }
            }
        })
    ),
    ?assertEqual(
        {error, ~"on field 'config.launchCommand.arguments': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => #{
                    command => ~"foo",
                    cwd => ~"/blah",
                    arguments => 42
                }
            }
        })
    ),
    ?assertEqual(
        {error, ~"on field 'config.launchCommand': unexpected field: garments"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => #{
                    command => ~"foo",
                    cwd => ~"/blah",
                    garments => [~"foo", ~"bar"]
                }
            }
        })
    ),

    ?assertEqual(
        {error, ~"on field 'config': mandatory field missing 'targetNode'"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => #{
                    command => ~"foo",
                    cwd => ~"/blah"
                }
            }
        })
    ),
    ?assertEqual(
        {error, ~"on field 'config.targetNode': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => #{
                    command => ~"foo",
                    cwd => ~"/blah"
                },
                targetNode => ~"some_node@localhost"
            }
        })
    ),
    ?assertEqual(
        {error, ~"on field 'config.targetNode': mandatory field missing 'name'"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => #{
                    command => ~"foo",
                    cwd => ~"/blah"
                },
                targetNode => #{}
            }
        })
    ),

    ?assertEqual(
        {error, ~"on field 'config.targetNode.name': invalid value"},
        edb_dap_request_launch:parse_arguments(#{
            config => #{
                launchCommand => #{
                    command => ~"foo",
                    cwd => ~"/blah"
                },
                targetNode => #{
                    name => 42
                }
            }
        })
    ),

    Minimal = #{
        launchCommand => #{
            command => ~"foo",
            cwd => ~"/blah"
        },
        targetNode => #{
            name => ~"some_node@localhost"
        }
    },
    ?assertEqual(
        {ok, Minimal#{targetNode => #{name => 'some_node@localhost'}}},
        edb_dap_request_launch:parse_arguments(#{config => Minimal})
    ),

    ?assertEqual(
        {error, ~"on field 'config.timeout': invalid value"},
        edb_dap_request_launch:parse_arguments(#{config => Minimal#{timeout => on}})
    ),
    ?assertEqual(
        {error, ~"on field 'config.stripSourcePrefix': invalid value"},
        edb_dap_request_launch:parse_arguments(#{config => Minimal#{stripSourcePrefix => on}})
    ),
    ?assertEqual(
        {error, ~"on field 'config': unexpected field: foo"},
        edb_dap_request_launch:parse_arguments(#{config => Minimal#{foo => bar}})
    ),

    Maximal = #{
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
        stripSourcePrefix => ~"blah/blah"
    },

    MaximalLaunchConfig = #{
        type => ~"edb",
        request => ~"~launch",
        name => ~"Some config",
        presentation => #{blah => blah},
        '__sessionId' => ~"some session",
        config => Maximal
    },
    ?assertEqual(
        {ok, Maximal#{
            targetNode => #{
                name => 'test42-123-atn@localhost',
                cookie => 'connect_cookie',
                type => 'shortnames'
            }
        }},
        edb_dap_request_launch:parse_arguments(MaximalLaunchConfig)
    ).
