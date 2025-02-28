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
    is_non_neg_integer/1,
    is_true/1
]).

%% --------------------------------------------------------------------
%% Types
%% --------------------------------------------------------------------
-export_type([template/0, predicate/0, value_validation/0, field_validation/0]).
-type predicate() :: fun((term()) -> boolean()).
-type value_validation() :: predicate() | template().
-type field_validation() :: value_validation() | {optional, value_validation()}.
-type template() :: #{atom() => field_validation()}.

%% --------------------------------------------------------------------
%% Public API
%% --------------------------------------------------------------------
-spec parse(template(), term(), allow_unknown | reject_unknown) ->
    {ok, dynamic()} | {error, HumarReadableReason :: binary()}.
parse(Template, Map0, allow_unknown) when is_map(Map0) ->
    Map1 = maps:with(maps:keys(Template), Map0),
    parse(Template, Map1, reject_unknown);
parse(Template, Term, _) ->
    try parse_map(Template, Term) of
        ok ->
            {ok, Term}
    catch
        throw:{parse_error, Reason} ->
            {error, human_readable_error(Reason)}
    end.

-spec is_non_neg_integer(term()) -> boolean().
is_non_neg_integer(N) ->
    is_integer(N) andalso N >= 0.

-spec is_true(boolean()) -> boolean().
is_true(true) -> true;
is_true(false) -> false.

%% --------------------------------------------------------------------
%% Helpers
%% --------------------------------------------------------------------

-spec parse_value(value_validation(), term()) -> ok.
parse_value(P, V) when is_function(P) ->
    case P(V) of
        true -> ok;
        false -> throw({parse_error, {invalid, V}})
    end;
parse_value(Template, V) when is_map(Template) ->
    parse_map(Template, V).

-spec parse_field(Field :: atom(), field_validation(), #{term() => term()}) -> ok.
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
            ok;
        {parse, What, With} ->
            try
                parse_value(With, What)
            catch
                throw:{parse_error, {fields, Fields, Reason}} when is_list(Fields) ->
                    throw({parse_error, {fields, [Field | Fields], Reason}});
                throw:{parse_error, Reason} ->
                    throw({parse_error, {fields, [Field], Reason}})
            end
    end.

-spec parse_map(template(), term()) -> ok.
parse_map(Template, Map) when is_map(Map) ->
    maps:foreach(
        fun(Field, Validation) ->
            parse_field(Field, Validation, Map)
        end,
        Template
    ),
    case maps:without(maps:keys(Template), Map) of
        Unexpected when map_size(Unexpected) =:= 0 -> ok;
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
    io_lib:format("unexpected field: ~s", [Field]);
human_readable_error_1({fields, Fields, Error}) when is_list(Fields) ->
    FieldsPath = string:join([atom_to_list(Field) || Field <- Fields, is_atom(Field)], "."),
    [io_lib:format("on field '~s': ", [FieldsPath]), human_readable_error_1(Error)].
