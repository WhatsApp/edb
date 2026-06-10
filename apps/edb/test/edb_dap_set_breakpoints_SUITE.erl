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

-oncall("whatsapp_server_devx").

-include_lib("assert/include/assert.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([test_error_set_breakpoint_bad_line/1]).
-export([test_error_set_breakpoint_unknown_module/1]).
-export([test_set_breakpoint_by_source_module_callback/1]).
-export([test_clear_breakpoints_removes_cached_source_modules/1]).
-export([test_set_breakpoint_by_module_name_when_source_lookup_unavailable/1]).

all() ->
    [
        test_error_set_breakpoint_bad_line,
        test_error_set_breakpoint_unknown_module,
        test_set_breakpoint_by_source_module_callback,
        test_clear_breakpoints_removes_cached_source_modules,
        test_set_breakpoint_by_module_name_when_source_lookup_unavailable
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
                                message := ~"Module not found or failing to load",
                                reason := ~"failed",
                                verified := false
                            }
                        ]
                }
        },

        Response
    ),
    ok.

test_set_breakpoint_by_source_module_callback(Config) ->
    {ok, Client, #{peer := Peer, srcdir := SrcDir}} = edb_dap_test_support:start_session_via_launch(Config, #{
        modules => [
            {source, [
                ~"-module(edb_source_breakpoint_one).\n",
                ~"-export([go/0]).\n",
                ~"go() -> ok.\n"
            ]},
            {source, [
                ~"-module(edb_source_breakpoint_two).\n",
                ~"-export([go/0]).\n",
                ~"go() ->\n",
                ~"    ok.\n"
            ]},
            {source, [
                ~"-module(edb_source_breakpoint_cb).\n",
                ~"-export([modules/1]).\n",
                ~"modules(_) ->\n",
                ~"    [edb_source_breakpoint_one, edb_source_breakpoint_two].\n"
            ]}
        ]
    }),
    SourcePath = filename:join(edb_test_support:file_name_all_to_string(SrcDir), "breakpoint.erl"),
    SourcePathBin = edb_test_support:safe_string_to_binary(SourcePath),

    ok = edb_dap_test_support:configure(Client, []),
    ok = peer:call(Peer, application, set_env, [
        edb, file_to_module_cb, {eval, fun edb_source_breakpoint_cb:modules/1}
    ]),

    Response = edb_dap_test_client:set_breakpoints(Client, #{
        source => #{path => SourcePathBin},
        breakpoints => [#{line => 3}, #{line => 4}, #{line => 42}]
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
                            #{line := 3, verified := true},
                            #{line := 4, verified := true},
                            #{
                                line := 42,
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

test_clear_breakpoints_removes_cached_source_modules(Config) ->
    Module1 = edb_cached_source_breakpoint_one,
    Module2 = edb_cached_source_breakpoint_two,

    {ok, Client, #{peer := Peer, node := Node, srcdir := SrcDir}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(edb_cached_source_breakpoint_one).\n",
                    ~"-export([go/0]).\n",
                    ~"go() -> ok.\n"
                ]},
                {source, [
                    ~"-module(edb_cached_source_breakpoint_two).\n",
                    ~"-export([go/0]).\n",
                    ~"go() ->\n",
                    ~"    ok.\n"
                ]},
                {source, [
                    ~"-module(edb_cached_source_breakpoint_cb).\n",
                    ~"-export([modules/1]).\n",
                    ~"modules(_) ->\n",
                    ~"    [edb_cached_source_breakpoint_one, edb_cached_source_breakpoint_two].\n"
                ]}
            ]
        }),
    SourcePath = filename:join(edb_test_support:file_name_all_to_string(SrcDir), "cached_breakpoint.erl"),
    SourcePathBin = edb_test_support:safe_string_to_binary(SourcePath),

    ok = edb_dap_test_support:configure(Client, []),
    ok = peer:call(Peer, application, set_env, [
        edb, file_to_module_cb, {eval, fun edb_cached_source_breakpoint_cb:modules/1}
    ]),

    SetResponse = edb_dap_test_client:set_breakpoints(Client, #{
        source => #{path => SourcePathBin},
        breakpoints => [#{line => 3}, #{line => 4}]
    }),
    ?assertMatch(
        #{
            command := ~"setBreakpoints",
            type := response,
            success := true,
            body := #{breakpoints := [#{line := 3, verified := true}, #{line := 4, verified := true}]}
        },
        SetResponse
    ),
    ?assertMatch(
        #{
            Module1 := [#{line := 3, module := Module1, type := line}],
            Module2 := [#{line := 4, module := Module2, type := line}]
        },
        target_breakpoints(Peer, Node)
    ),

    ok = peer:call(Peer, application, unset_env, [edb, file_to_module_cb]),
    ClearResponse = edb_dap_test_client:set_breakpoints(Client, #{
        source => #{path => SourcePathBin},
        breakpoints => []
    }),
    ?assertMatch(
        #{
            command := ~"setBreakpoints",
            type := response,
            success := true,
            body := #{breakpoints := []}
        },
        ClearResponse
    ),
    ?assertEqual(#{}, target_breakpoints(Peer, Node)),

    SetAfterClearResponse = edb_dap_test_client:set_breakpoints(Client, #{
        source => #{path => SourcePathBin},
        breakpoints => [#{line => 3}]
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
                                line := 3,
                                message := ~"Module not found or failing to load",
                                reason := ~"failed",
                                verified := false
                            }
                        ]
                }
        },
        SetAfterClearResponse
    ),
    ok.

test_set_breakpoint_by_module_name_when_source_lookup_unavailable(Config) ->
    {ok, Client, #{srcdir := SrcDir}} = edb_dap_test_support:start_session_via_launch(Config, #{
        modules => [
            {source, [
                ~"-module(edb_no_source_breakpoint).\n",
                ~"-export([go/0]).\n",
                ~"go() ->\n",
                ~"    ok.\n"
            ]}
        ]
    }),
    SourcePath = filename:join(edb_test_support:file_name_all_to_string(SrcDir), "edb_no_source_breakpoint.erl"),
    ok = edb_dap_test_support:configure(Client, []),

    Response = edb_dap_test_client:set_breakpoints(Client, #{
        source => #{path => edb_test_support:safe_string_to_binary(SourcePath)},
        breakpoints => [#{line => 4}]
    }),

    ?assertMatch(
        #{
            command := ~"setBreakpoints",
            type := response,
            success := true,
            body := #{breakpoints := [#{line := 4, verified := true}]}
        },
        Response
    ),
    ok.

target_breakpoints(Peer, Node) ->
    peer:call(Peer, edb_server, call, [Node, get_breakpoints]).
