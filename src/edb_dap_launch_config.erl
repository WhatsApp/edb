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
%% @doc DAP Launch Configuration
%%      Validation functions for the DAP launch configuration
%% @end
%%%-------------------------------------------------------------------
%%% % @format
-module(edb_dap_launch_config).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-export([parse/1]).

-export_type([t/0]).
-type t() :: #{
    launchCommand => #{
        cwd := binary(),
        command := binary(),
        arguments => [binary()]
    },
    targetNode => #{
        name := binary(),
        cookie => binary(),
        type => binary()
    },
    stripSourcePath => binary(),
    timeout => non_neg_integer()
}.

-spec parse(term()) -> {ok, t()} | {error, HumarReadableReason :: binary()}.
parse(LaunchConfig) ->
    Template = #{
        launchCommand => #{
            cwd => fun is_binary/1,
            command => fun is_binary/1,
            arguments => {optional, fun is_valid_arguments/1},
            env => {optional, fun is_valid_env/1}
        },
        targetNode => #{
            name => fun is_binary/1,
            cookie => {optional, fun is_binary/1},
            type => {optional, fun is_node_type/1}
        },
        stripSourcePrefix => {optional, fun is_binary/1},
        timeout => {optional, fun is_non_neg_integer/1},

        %% The following may be received but are ignored
        %% TODO(T210035817): eventually remove these, and just ignore all top-level fields
        name => {optional, fun is_binary/1},
        type => {optional, fun(_) -> true end},
        request => {optional, fun(_) -> true end},
        presentation => {optional, fun(_) -> true end},
        '__sessionId' => {optional, fun(_) -> true end},
        '__configurationTarget' => {optional, fun(_) -> true end}
    },
    try parse_map(Template, LaunchConfig) of
        ok ->
            % eqwalizer:ignore Already parsed
            {ok, LaunchConfig}
    catch
        throw:{parse_error, Reason} ->
            {error, human_readable_error(Reason)}
    end.

-spec is_non_neg_integer(term()) -> boolean().
is_non_neg_integer(N) ->
    is_integer(N) andalso N >= 0.

-spec is_valid_arguments(term()) -> boolean().
is_valid_arguments(Arguments) when is_list(Arguments) ->
    lists:all(fun is_binary/1, Arguments);
is_valid_arguments(_) ->
    false.

-spec is_valid_env(term()) -> boolean().
is_valid_env(Env) when is_map(Env) ->
    lists:all(fun is_true/1, [is_atom(Key) andalso is_binary(Value) || Key := Value <- Env]);
is_valid_env(_) ->
    false.

-spec is_node_type(term()) -> boolean().
is_node_type(Type) when is_binary(Type) ->
    lists:member(Type, [~"longnames", ~"shortnames"]);
is_node_type(_Type) ->
    false.

-spec is_true(boolean()) -> boolean().
is_true(true) -> true;
is_true(false) -> false.

%% --------------------------------------------------------------------
%% Parser functions
%% --------------------------------------------------------------------

-type predicate() :: fun((term()) -> boolean()).
-type value_validation() :: predicate() | map_template().
-type field_validation() :: value_validation() | {optional, value_validation()}.
-type map_template() :: #{atom() => field_validation()}.

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

-spec parse_map(map_template(), term()) -> ok.
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
