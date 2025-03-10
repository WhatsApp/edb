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
    Minimal = #{
        launchCommand => #{
            command => ~"foo",
            cwd => ~"/blah"
        },
        targetNode => #{
            name => ~"some_node@localhost"
        }
    },
    ExpectedMinimal = #{
        launchCommand => #{
            command => ~"foo",
            cwd => ~"/blah"
        },
        targetNode => #{
            name => 'some_node@localhost'
        }
    },

    ?assertEqual(
        {ok, ExpectedMinimal},
        edb_dap_request_launch:parse_arguments(Minimal)
    ),

    Maximal = #{
        irrelevantStuff => true,

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

    ExpectedMaximal = #{
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
            name => 'test42-123-atn@localhost',
            cookie => connect_cookie,
            type => shortnames
        },
        timeout => 300,
        stripSourcePrefix => ~"blah/blah"
    },

    ?assertEqual(
        {ok, ExpectedMaximal},
        edb_dap_request_launch:parse_arguments(Maximal)
    ).

test_validate(_Config) ->
    Minimal = #{
        config => #{
            launchCommand => #{
                command => ~"foo",
                cwd => ~"/blah"
            },
            targetNode => #{
                name => ~"some_node@localhost"
            }
        }
    },
    ExpectedMinimal = #{
        launchCommand => #{
            command => ~"foo",
            cwd => ~"/blah"
        },
        targetNode => #{
            name => 'some_node@localhost'
        }
    },
    ?assertEqual(
        {ok, ExpectedMinimal},
        edb_dap_request_launch:parse_arguments(Minimal)
    ),

    Maximal = #{
        irrelevantStuff => true,

        config => #{
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
        }
    },

    ExpectedMaximal = #{
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
            name => 'test42-123-atn@localhost',
            cookie => connect_cookie,
            type => shortnames
        },
        timeout => 300,
        stripSourcePrefix => ~"blah/blah"
    },
    ?assertEqual(
        {ok, ExpectedMaximal},
        edb_dap_request_launch:parse_arguments(Maximal)
    ).
