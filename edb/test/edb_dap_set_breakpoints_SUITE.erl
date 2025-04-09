%% Copyright (c) Meta Platforms, Inc. and affiliates.
%%
%% Licensed under the Apache License, Version 2.0 (the ~"License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an ~"AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%% % @format

%% Tests for the ~"set_breakpoints" request of the EDB DAP server

-module(edb_dap_set_breakpoints_SUITE).

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
-export([test_error_set_breakpoint_bad_line/1]).
-export([test_error_set_breakpoint_unknown_module/1]).

all() ->
    [
        test_error_set_breakpoint_bad_line,
        test_error_set_breakpoint_unknown_module
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_error_set_breakpoint_bad_line(Config) ->
    {ok, Client, #{modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).             %L01\n",
                    ~"-export([go/0]).          %L02\n",
                    ~"                          %L03\n",
                    ~"go() ->                   %L04\n",
                    ~"    ok.                   %L05\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, []),

    Response = edb_dap_test_client:set_breakpoints(Client, #{
        source => #{path => FooSrc},
        breakpoints => [#{line => L} || L <- lists:seq(1, 6)]
    }),

    ?assertMatch(
        #{
            command := ~"setBreakpoints",
            type := response,
            success := true,
            body :=
                #{
                    breakpoints :=
                        [
                            #{
                                line := 1,
                                message := ~"Line is not executable",
                                reason := ~"failed",
                                verified := false
                            },
                            #{
                                line := 2,
                                message := ~"Line is not executable",
                                reason := ~"failed",
                                verified := false
                            },
                            #{
                                line := 3,
                                message := ~"Line is not executable",
                                reason := ~"failed",
                                verified := false
                            },
                            #{
                                line := 4,
                                message :=
                                    ~"Can't set a breakpoint on this line",
                                reason := ~"failed",
                                verified := false
                            },
                            #{
                                line := 5,
                                verified := true
                            },
                            #{
                                line := 6,
                                message := ~"Line is not executable",
                                reason := ~"failed",
                                verified := false
                            }
                        ]
                }
        },
        Response
    ),
    ok.

test_error_set_breakpoint_unknown_module(Config) ->
    {ok, Client, #{}} = edb_dap_test_support:start_session_via_launch(Config, #{}),
    ok = edb_dap_test_support:configure(Client, []),

    Response = edb_dap_test_client:set_breakpoints(Client, #{
        source => #{path => ~"/blah/blah/foo.erl"},
        breakpoints => [#{line => 42}]
    }),

    ?assertMatch(
        #{
            command := ~"setBreakpoints",
            type := response,
            success := true,
            body :=
                #{
                    breakpoints :=
                        [
                            #{
                                line := 42,
                                message := ~"Module not found",
                                reason := ~"failed",
                                verified := false
                            }
                        ]
                }
        },

        Response
    ),
    ok.
