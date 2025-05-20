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

%% Evaluate tests for the EDB DAP adapter

-module(edb_dap_evaluate_SUITE).

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
-export([test_evaluate_simple_variable/1]).
-export([test_evaluate_complex_expression/1]).
-export([test_evaluate_exception/1]).
-export([test_evaluate_compile_error/1]).
-export([test_evaluate_structured_result/1]).

all() ->
    [
        test_evaluate_simple_variable,
        test_evaluate_complex_expression,
        test_evaluate_exception,
        test_evaluate_compile_error,
        test_evaluate_structured_result
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

test_evaluate_simple_variable(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).     %L01\n",
                    ~"-export([go/2]).  %L02\n",
                    ~"go(X, Y) ->       %L03\n",
                    ~"    X + 2 * Y.    %L04\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [42, 7]}),
    case ST of
        [#{id := TopFrameId} | _] ->
            % Evaluate the variable X
            EvalResponse = evaluate_expression(Client, TopFrameId, ~"X"),
            ?assertEqual(
                #{
                    success => true,
                    body => #{
                        result => ~"42",
                        variablesReference => 0
                    }
                },
                EvalResponse
            )
    end,
    ok.

test_evaluate_complex_expression(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).     %L01\n",
                    ~"-export([go/2]).  %L02\n",
                    ~"go(X, Y) ->       %L03\n",
                    ~"    X + 2 * Y.    %L04\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [42, 7]}),
    case ST of
        [#{id := TopFrameId} | _] ->
            % Evaluate a complex expression using variables in scope
            EvalResponse = evaluate_expression(Client, TopFrameId, ~"X + Y * 3 - 5"),
            ?assertEqual(
                #{
                    success => true,
                    body => #{
                        result => ~"58",
                        variablesReference => 0
                    }
                },
                EvalResponse
            )
    end,
    ok.

test_evaluate_exception(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).     %L01\n",
                    ~"-export([go/2]).  %L02\n",
                    ~"go(X, Y) ->       %L03\n",
                    ~"    X + 2 * Y.    %L04\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [42, 7]}),
    case ST of
        [#{id := TopFrameId} | _] ->
            % Evaluate an expression that raises an exception
            EvalResponse = evaluate_expression(Client, TopFrameId, ~"1 div 0"),
            ?assertEqual(
                #{
                    success => false,
                    body => #{error => #{id => -32002, format => ~"Uncaught exception -- error:badarith"}}
                },
                EvalResponse
            )
    end,
    ok.

test_evaluate_compile_error(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [
                    ~"-module(foo).     %L01\n",
                    ~"-export([go/2]).  %L02\n",
                    ~"go(X, Y) ->       %L03\n",
                    ~"    X + 2 * Y.    %L04\n"
                ]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 4}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo, go, [42, 7]}),
    case ST of
        [#{id := TopFrameId} | _] ->
            % Evaluate an expression with a syntax error
            EvalResponse = evaluate_expression(Client, TopFrameId, ~"X + "),
            ?assertEqual(
                #{
                    success => false,
                    body => #{error => #{id => -32002, format => ~"1:5:syntax error before: ';'"}}
                },
                EvalResponse
            ),

            % Evaluate an expression with a reference to a non-existent variable
            EvalResponse2 = evaluate_expression(Client, TopFrameId, ~"Z + 1"),
            ?assertEqual(
                #{
                    success => false,
                    body => #{
                        error => #{id => -32002, format => ~"1:1:variable 'Z' is unbound"}
                    }
                },
                EvalResponse2
            )
    end,
    ok.

test_evaluate_structured_result(Config) ->
    {ok, Client, #{peer := Peer, modules := #{foo := FooSrc}}} =
        edb_dap_test_support:start_session_via_launch(Config, #{
            modules => [
                {source, [~"""
                    -module(foo).            %L01\n
                    -export([go/2]).         %L02\n
                    go(L, X) ->              %L03\n
                        M = [4, [], {6, 7}], %L04\n
                        {L ++ M, X}.         %L05\n
                """]}
            ]
        }),
    ok = edb_dap_test_support:configure(Client, [{FooSrc, [{line, 5}]}]),
    {ok, _ThreadId, ST} = edb_dap_test_support:spawn_and_wait_for_bp(
        Client, Peer, {foo, go, [[1, 2, 3], #{life => 42}]}
    ),
    case ST of
        [#{id := TopFrameId} | _] ->
            % Evaluate an expression that returns a list
            EvalResponse = evaluate_expression(Client, TopFrameId, ~"L ++ M"),
            ?assertEqual(
                #{
                    success => true,
                    body => #{
                        result => ~"[1,2,3,4,[],{6,7}]",
                        variablesReference => 1
                    }
                },
                EvalResponse
            ),

            % Get the variablesReference to inspect the structure
            #{body := #{variablesReference := VarsRef}} = EvalResponse,

            % Inspect the structure using variables request
            Variables = edb_dap_test_support:get_variables(Client, VarsRef),
            ?assertEqual(
                #{
                    ~"1" => #{name => ~"1", value => ~"1", variablesReference => 0},
                    ~"2" => #{name => ~"2", value => ~"2", variablesReference => 0},
                    ~"3" => #{name => ~"3", value => ~"3", variablesReference => 0},
                    ~"4" => #{name => ~"4", value => ~"4", variablesReference => 0},
                    ~"5" => #{name => ~"5", value => ~"[]", variablesReference => 0},
                    ~"6" => #{
                        name => ~"6",
                        value => ~"{6,7}",
                        evaluateName => ~"lists:nth(6, L ++ M)",
                        variablesReference => 2
                    }
                },
                Variables
            )
    end,
    ok.

%%--------------------------------------------------------------------
%% Helpers
%% -------------------------------------------------------------------

-spec evaluate_expression(Client, FrameId, Expression) -> Result when
    Client :: edb_dap_test_support:client(),
    FrameId :: number(),
    Expression :: binary(),
    Result :: #{success := boolean(), body := edb_dap_request_evaluate:response_body()}.
evaluate_expression(Client, FrameId, Expression) ->
    Response = edb_dap_test_client:evaluate(Client, #{
        expression => Expression,
        frameId => FrameId,
        context => watch
    }),
    case Response of
        #{command := ~"evaluate", type := response, success := Success, body := Body} ->
            #{success => Success, body => Body}
    end.
