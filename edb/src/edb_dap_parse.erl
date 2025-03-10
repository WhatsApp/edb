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
%%%-------------------------------------------------------------------
%% @doc Support for parsing of request arguments, etc
%% @end
%%%-------------------------------------------------------------------
%%% % @format
-module(edb_dap_parse).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-export([parse/3]).
-export([
    choice/1,
    null/0,
    boolean/0,
    non_neg_integer/0,
    atom/0,
    atom/1,
    atoms/1,
    binary/0,
    empty_list/0,
    list/1,
    nonempty_list/1,
    map/2
]).

%% --------------------------------------------------------------------
%% Types
%% --------------------------------------------------------------------
-export_type([template/0, parser/1]).
-type parser(T) :: fun((term()) -> {ok, T}).
-type value_parser() :: parser(term()) | template().
-type field_parser() :: value_parser() | {optional, value_parser()}.
-type template() :: #{atom() => field_parser()}.

%% --------------------------------------------------------------------
%% Public API
%% --------------------------------------------------------------------
-spec parse(template(), term(), allow_unknown | reject_unknown) ->
    {ok, map()} | {error, HumarReadableReason :: binary()}.
parse(Template, Map0, allow_unknown) when is_map(Map0) ->
    Map1 = maps:with(maps:keys(Template), Map0),
    parse(Template, Map1, reject_unknown);
parse(Template, Term, _) ->
    try
        parse_map(Template, Term)
    catch
        throw:{parse_error, Reason} ->
            {error, human_readable_error(Reason)}
    end.

-spec choice([parser(T)]) -> parser(T).
choice(Options) ->
    fun(X) ->
        TryInOrder = fun F([P | Ps]) ->
            try P(X) of
                Res = {ok, _} -> Res;
                _ -> F(Ps)
            catch
                _:_ -> F(Ps)
            end
        end,
        TryInOrder(Options)
    end.

%% THe json library treats JSON NULL as the atom 'null'
-spec null() -> parser(null).
null() ->
    fun(null) -> {ok, null} end.

-spec boolean() -> parser(boolean()).
boolean() ->
    fun
        (true) -> {ok, true};
        (false) -> {ok, false}
    end.

-spec non_neg_integer() -> parser(non_neg_integer()).
non_neg_integer() ->
    fun(N) when is_integer(N) andalso N >= 0 -> {ok, N} end.

-spec atom() -> parser(atom()).
atom() ->
    fun
        (A) when is_atom(A), A /= true, A /= false, A /= null -> {ok, A};
        (B) when is_binary(B) -> {ok, binary_to_atom(B)}
    end.

-spec atom(A) -> parser(A) when A :: atom().
atom(A) when is_atom(A) ->
    fun
        F(X) when X =:= A -> {ok, A};
        F(X) when is_binary(X) -> F(binary_to_atom(X))
    end.

-spec atoms(A) -> parser(atom()) when A :: [atom()].
atoms(As) when is_list(As) ->
    choice([atom(A) || A <- As]).

-spec binary() -> parser(binary()).
binary() ->
    fun(B) when is_binary(B) -> {ok, B} end.

-spec empty_list() -> parser([none()]).
empty_list() ->
    fun([]) -> {ok, []} end.

-spec list(parser(T)) -> parser([T]).
list(Parser) ->
    fun(L) when is_list(L) ->
        {ok, [run_parser(Parser, Raw) || Raw <- L]}
    end.

-spec nonempty_list(parser(T)) -> parser(nonempty_list(T)).
nonempty_list(Parser) ->
    fun(L = [_ | _]) ->
        {ok, [run_parser(Parser, Raw) || Raw <- L]}
    end.

-spec map(parser(K), parser(V)) -> parser(#{K => V}).
map(KParser, VParser) ->
    %% HACK! In edb_dap:unframe/1, we convert all map keys from binary to atom,
    %% which makes sense as most messages are "shapes", but breaks when we pass
    %% things like "environments". So here we need to undo that conversion.
    UnparseAtom = fun
        (A) when is_atom(A) -> atom_to_binary(A);
        (X) -> X
    end,
    fun(M) when is_map(M) ->
        {ok, #{run_parser(KParser, UnparseAtom(RawK)) => run_parser(VParser, RawV) || RawK := RawV <- M}}
    end.

%% --------------------------------------------------------------------
%% Helpers
%% --------------------------------------------------------------------

-spec run_parser(parser(T), term()) -> T.
run_parser(Parser, Raw) ->
    {ok, Parsed} = Parser(Raw),
    Parsed.

-spec parse_value(value_parser(), Raw) -> {ok, Parsed} when
    Raw :: term(),
    Parsed :: term().
parse_value(Parser, V) when is_function(Parser) ->
    try
        Parser(V)
    catch
        _:_ -> throw({parse_error, {invalid, V}})
    end;
parse_value(Template, V) when is_map(Template) ->
    parse_map(Template, V).

-spec parse_field(Field :: atom(), field_parser(), map()) -> {ok, map()}.
parse_field(Field, FieldValidation, Map) ->
    Action =
        case {maps:find(Field, Map), FieldValidation} of
            {error, {optional, _}} -> ignore;
            {error, _} -> throw({parse_error, {missing, Field}});
            {{ok, Val}, {optional, Validation}} -> {parse, Val, Validation};
            {{ok, Val}, Validation} -> {parse, Val, Validation}
        end,
    case Action of
        ignore ->
            {ok, Map};
        {parse, Raw, With} ->
            try parse_value(With, Raw) of
                {ok, Parsed} -> {ok, Map#{Field => Parsed}}
            catch
                throw:{parse_error, {fields, Fields, Reason}} when is_list(Fields) ->
                    throw({parse_error, {fields, [Field | Fields], Reason}});
                throw:{parse_error, Reason} ->
                    throw({parse_error, {fields, [Field], Reason}})
            end
    end.

-spec parse_map(template(), term()) -> {ok, map()}.
parse_map(Template, Map0) when is_map(Map0) ->
    Map1 = maps:fold(
        fun(Field, FieldParser, Acc0) ->
            {ok, Acc1} = parse_field(Field, FieldParser, Acc0),
            Acc1
        end,
        Map0,
        Template
    ),
    case maps:without(maps:keys(Template), Map1) of
        Unexpected when map_size(Unexpected) =:= 0 -> {ok, Map1};
        Unexpected -> throw({parse_error, {unexpected, maps:keys(Unexpected)}})
    end;
parse_map(_, X) ->
    throw({parse_error, {invalid, X}}).

-spec human_readable_error(term()) -> binary().
human_readable_error(Reason) ->
    case unicode:characters_to_binary(lists:flatten(human_readable_error_1(Reason))) of
        HumanReadable when is_binary(HumanReadable) -> HumanReadable
    end.

-spec human_readable_error_1(term()) -> io_lib:chars().
human_readable_error_1({invalid, _X}) ->
    ["invalid value"];
human_readable_error_1({missing, Field}) when is_atom(Field) ->
    io_lib:format("mandatory field missing '~s'", [Field]);
human_readable_error_1({unexpected, [Field | _]}) when is_atom(Field) ->
    io_lib:format("unexpected field: '~s'", [Field]);
human_readable_error_1({fields, Fields, Error}) when is_list(Fields) ->
    FieldsPath = string:join([atom_to_list(Field) || Field <- Fields, is_atom(Field)], "."),
    [io_lib:format("on field '~s': ", [FieldsPath]), human_readable_error_1(Error)].
