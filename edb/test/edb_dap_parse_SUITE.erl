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

%% Tests for the DAP arguments parser

-module(edb_dap_parse_SUITE).

%% erlfmt:ignore
% @fb-only
-typing([eqwalizer]).

%% CT callbacks
-export([
    all/0,
    groups/0
]).

%% Parser testcases
-export([
    test_null/1,
    test_boolean/1,
    test_non_neg_integer/1,
    test_number/1,
    test_atom_0/1,
    test_atom_1/1,
    test_atoms/1,
    test_binary/1,
    test_empty_list/1,
    test_list/1,
    test_nonempty_list/1,
    test_map/1,
    test_choice/1
]).

%% parse function testcases
-export([
    test_optional_fields/1,
    test_nested_errors/1
]).

%% parse function testcases
-export([
    test_parse_rejecting_unknown/1,
    test_parse_allowing_unknown/1
]).

all() ->
    [
        {group, parsers},
        {group, templates},
        {group, parse_function}
    ].

groups() ->
    [
        {parsers, [
            test_null,
            test_boolean,
            test_non_neg_integer,
            test_number,
            test_atom_0,
            test_atom_1,
            test_atoms,
            test_binary,
            test_empty_list,
            test_list,
            test_nonempty_list,
            test_map,
            test_choice
        ]},

        {templates, [
            test_optional_fields,
            test_nested_errors
        ]},

        {parse_function, [
            test_parse_rejecting_unknown,
            test_parse_allowing_unknown
        ]}
    ].

%%--------------------------------------------------------------------
%% PARSER TEST CASES
%%--------------------------------------------------------------------
test_null(_Config) ->
    Template = #{k => edb_dap_parse:null()},

    {ok, #{k := null}} = parse(Template, #{k => null}),

    {error, ~"on field 'k': invalid value"} = parse(Template, #{k => ~"null"}),
    ok.

test_boolean(_Config) ->
    Template = #{is_foo => edb_dap_parse:boolean()},

    {ok, #{is_foo := true}} = parse(Template, #{is_foo => true}),
    {ok, #{is_foo := false}} = parse(Template, #{is_foo => false}),

    {error, ~"on field 'is_foo': invalid value"} = parse(Template, #{is_foo => ~"true"}),
    {error, ~"on field 'is_foo': invalid value"} = parse(Template, #{is_foo => ~"false"}),

    ok.

test_non_neg_integer(_Config) ->
    Template = #{count => edb_dap_parse:non_neg_integer()},

    {ok, #{count := 0}} = parse(Template, #{count => 0}),
    {ok, #{count := 42}} = parse(Template, #{count => 42}),

    {error, ~"on field 'count': invalid value"} = parse(Template, #{count => -1}),
    {error, ~"on field 'count': invalid value"} = parse(Template, #{count => ~"42"}),

    ok.

test_number(_Config) ->
    Template = #{fooId => edb_dap_parse:number()},

    {ok, #{fooId := 1.5}} = parse(Template, #{fooId => 1.5}),
    {ok, #{fooId := -1.5}} = parse(Template, #{fooId => -1.5}),
    {ok, #{fooId := 42}} = parse(Template, #{fooId => 42}),
    {ok, #{fooId := -42}} = parse(Template, #{fooId => -42}),

    {error, ~"on field 'fooId': invalid value"} = parse(Template, #{fooId => ~"42.0"}),

    ok.

test_atom_0(_Config) ->
    Template = #{k => edb_dap_parse:atom()},

    {ok, #{k := foo}} = parse(Template, #{k => ~"foo"}),
    {ok, #{k := bar}} = parse(Template, #{k => ~"bar"}),

    {error, ~"on field 'k': invalid value"} = parse(Template, #{k => true}),
    {error, ~"on field 'k': invalid value"} = parse(Template, #{k => false}),
    {error, ~"on field 'k': invalid value"} = parse(Template, #{k => null}),
    {error, ~"on field 'k': invalid value"} = parse(Template, #{k => 42}),

    ok.

test_atom_1(_Config) ->
    Template = #{k => edb_dap_parse:atom(foo)},

    {ok, #{k := foo}} = parse(Template, #{k => foo}),
    {ok, #{k := foo}} = parse(Template, #{k => ~"foo"}),

    {error, ~"on field 'k': invalid value"} = parse(Template, #{k => bar}),
    {error, ~"on field 'k': invalid value"} = parse(Template, #{k => ~"bar"}),

    ok.

test_atoms(_Config) ->
    Template = #{kind => edb_dap_parse:atoms([foo, bar, hey])},

    {ok, #{kind := foo}} = parse(Template, #{kind => foo}),
    {ok, #{kind := bar}} = parse(Template, #{kind => bar}),
    {ok, #{kind := hey}} = parse(Template, #{kind => hey}),
    {ok, #{kind := foo}} = parse(Template, #{kind => ~"foo"}),
    {ok, #{kind := bar}} = parse(Template, #{kind => ~"bar"}),
    {ok, #{kind := hey}} = parse(Template, #{kind => ~"hey"}),

    {error, ~"on field 'kind': invalid value"} = parse(Template, #{kind => ho}),
    {error, ~"on field 'kind': invalid value"} = parse(Template, #{kind => ~"ho"}),
    ok.

test_binary(_Config) ->
    Template = #{kind => edb_dap_parse:binary()},

    {ok, #{kind := ~"foo"}} = parse(Template, #{kind => ~"foo"}),
    {ok, #{kind := ~"bar"}} = parse(Template, #{kind => ~"bar"}),

    {error, ~"on field 'kind': invalid value"} = parse(Template, #{kind => foo}),
    ok.

test_empty_list(_Config) ->
    Template = #{k => edb_dap_parse:empty_list()},

    {ok, #{k := []}} = parse(Template, #{k => []}),

    {error, ~"on field 'k': invalid value"} = parse(Template, #{k => [foo]}),
    ok.

test_list(_Config) ->
    Template = #{
        ints => edb_dap_parse:list(edb_dap_parse:non_neg_integer()),
        atoms => edb_dap_parse:list(edb_dap_parse:atom())
    },

    {ok, #{ints := [], atoms := []}} = parse(Template, #{ints => [], atoms => []}),
    {ok, #{ints := [1, 2], atoms := [foo]}} = parse(Template, #{ints => [1, 2], atoms => [foo]}),

    {error, ~"on field 'ints': invalid value"} = parse(Template, #{ints => [1, foo], atoms => []}),
    ok.

test_nonempty_list(_Config) ->
    Template = #{
        ints => edb_dap_parse:nonempty_list(edb_dap_parse:non_neg_integer()),
        atoms => edb_dap_parse:nonempty_list(edb_dap_parse:atom())
    },

    {ok, #{ints := [1, 2], atoms := [foo]}} = parse(Template, #{ints => [1, 2], atoms => [foo]}),

    {error, ~"on field 'ints': invalid value"} = parse(Template, #{ints => [], atoms => [foo]}),
    {error, ~"on field 'ints': invalid value"} = parse(Template, #{ints => [1, foo], atoms => [bar]}),
    ok.

test_map(_Config) ->
    Template = #{
        m1 => edb_dap_parse:map(
            edb_dap_parse:binary(),
            edb_dap_parse:boolean()
        ),
        m2 => edb_dap_parse:map(
            edb_dap_parse:atom(),
            edb_dap_parse:non_neg_integer()
        )
    },

    EmptyMap = #{},
    {ok, #{m1 := EmptyMap, m2 := EmptyMap}} = parse(Template, #{m1 => #{}, m2 => #{}}),
    {ok, #{m1 := #{~"foo" := true, ~"bar" := false}, m2 := #{foo := 42}}} = parse(Template, #{
        m1 => #{~"foo" => true, ~"bar" => false},
        m2 => #{foo => 42}
    }),

    % Map keys come converted to atom when decode JSON, so need to handle those as well
    {ok, #{m1 := #{~"foo" := true, ~"bar" := false}, m2 := #{foo := 42}}} = parse(Template, #{
        m1 => #{foo => true, bar => false},
        m2 => #{foo => 42}
    }),

    {error, ~"on field 'm1': invalid value"} = parse(Template, #{m1 => #{42 => true}, m2 => #{}}),
    {error, ~"on field 'm1': invalid value"} = parse(Template, #{m1 => #{~"foo" => 42}, m2 => #{}}),
    ok.

test_choice(_Config) ->
    Template = #{
        k => edb_dap_parse:choice([
            edb_dap_parse:boolean(),
            edb_dap_parse:non_neg_integer()
        ])
    },

    {ok, #{k := true}} = parse(Template, #{k => true}),
    {ok, #{k := 42}} = parse(Template, #{k => 42}),

    {error, ~"on field 'k': invalid value"} = parse(Template, #{k => ~"foo"}),
    ok.

%%--------------------------------------------------------------------
%% TEMPLATE TEST CASES
%%--------------------------------------------------------------------
test_optional_fields(_Config) ->
    Template = #{
        foo => {optional, edb_dap_parse:binary()},
        bar => {optional, #{hey => edb_dap_parse:boolean()}}
    },

    EmptyMap = #{},
    {ok, EmptyMap} = parse(Template, #{}),
    {ok, #{foo := ~"bar"}} = parse(Template, #{foo => ~"bar"}),
    {ok, #{bar := #{hey := true}}} = parse(Template, #{bar => #{hey => true}}),

    {error, ~"on field 'foo': invalid value"} = parse(Template, #{foo => 42}),
    ok.

test_nested_errors(_Config) ->
    Template = #{
        foo => #{bar => edb_dap_parse:boolean()}
    },
    {ok, #{foo := #{bar := true}}} = parse(Template, #{foo => #{bar => true}}),

    {error, ~"on field 'foo.bar': invalid value"} = parse(Template, #{foo => #{bar => ~"true"}}),
    ok.

%%--------------------------------------------------------------------
%% "PARSE" FUNCTION TEST CASES
%%--------------------------------------------------------------------
test_parse_rejecting_unknown(_Config) ->
    Template = #{k1 => edb_dap_parse:boolean(), k2 => {optional, edb_dap_parse:binary()}},

    M = #{k1 => true, k2 => ~"foo"},
    {ok, M} = edb_dap_parse:parse(Template, M, reject_unknown),

    {error, ~"unexpected field: 'k3'"} = edb_dap_parse:parse(Template, M#{k3 => 42}, reject_unknown),
    ok.

test_parse_allowing_unknown(_Config) ->
    Template = #{k1 => edb_dap_parse:boolean(), k2 => {optional, edb_dap_parse:binary()}},

    M = #{k1 => true, k2 => ~"foo"},
    {ok, M} = edb_dap_parse:parse(Template, M, allow_unknown),
    {ok, M} = edb_dap_parse:parse(Template, M#{k3 => 42}, allow_unknown),
    ok.

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------
-spec parse(edb_dap_parse:template(), term()) ->
    {ok, map()} | {error, HumarReadableReason :: binary()}.
parse(Template, Term) ->
    edb_dap_parse:parse(Template, Term, reject_unknown).
