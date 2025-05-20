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

-module(edb_expr).
-moduledoc """
Support for creating dynamic Erlang expressions that can be executed on
the context of a process stack-frame.
""".

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

%% Public API
-export([entrypoint/1]).
-export([compile_expr/2]).
-export([compile_guard/2]).

%% -------------------------------------------------------------------
%% Types
%% -------------------------------------------------------------------
-type compiled_expr() :: #{
    module := module(),
    entrypoint := atom(),
    code := binary()
}.
-export_type([compiled_expr/0]).

-type compile_opts() :: #{
    free_vars := [binary()],
    start_line => pos_integer(),
    start_col => pos_integer()
}.
-export_type([compile_opts/0]).

-type source_code() :: binary().
-type generated_source_code() :: #{
    header := io_lib:chars(),
    body := source_code(),
    body_start := {Line :: pos_integer(), Column :: pos_integer()},
    footer := io_lib:chars()
}.
-export_type([source_code/0]).

-type compile_error() :: erl_scan:error_info() | erl_parse:error_info() | erl_lint:error_info().
-export_type([compile_error/0]).

%% -------------------------------------------------------------------
%% Public API
%% -------------------------------------------------------------------

-doc """
Returns the function to call in order to evaluate a compiled expression.
""".
-spec entrypoint(CompiledExpr) -> Entrypoint when
    CompiledExpr :: compiled_expr(),
    Entrypoint :: fun((Vars :: edb:stack_frame_vars()) -> dynamic()).
entrypoint(#{module := Module, entrypoint := Entrypoint}) ->
    fun Module:Entrypoint/1.

-doc """
Takes an Erlang expression `Expr`, that can refer to any free-variable referred to
in the `free_vars` field of `Opts`, and compiles.

Any error at compile or run-time, will refer to locations relative to
`start_line` and `start_col` (both defaulting to 1 if missing).
""".
-spec compile_expr(Expr, Opts) -> {ok, compiled_expr()} | {error, compile_error()} when
    Expr :: source_code(),
    Opts :: compile_opts().
compile_expr(Expr, Opts = #{free_vars := FreeVars}) ->
    Module = module_name(expr, FreeVars, Expr),
    case code:get_object_code(Module) of
        {Module, Code, _} ->
            {exports, [{Entrypoint, 1}]} = Module:module_info(exports),
            {ok, #{module => Module, entrypoint => Entrypoint, code => Code}};
        error ->
            Entrypoint = Module,

            StartLine = maps:get(start_line, Opts, 1),
            StartCol = maps:get(start_col, Opts, 1),

            VarsMatch = lists:join(~",", [io_lib:format("~p := {value, ~s}", [V, V]) || V <- FreeVars]),
            ModuleSource = #{
                header => io_lib:format(
                    ~"""
                    -module(~s).
                    -export([~s/1]).
                    ~s(#{vars := #{~s}}) ->
                    """,
                    [Module, Entrypoint, Entrypoint, VarsMatch]
                ),
                body_start => {StartLine, StartCol},
                body => Expr,
                footer => [io_lib:format("""
                ;
                ~s(#{vars := Vars}) when map_size(Vars) =:= ~p ->
                    Unavailable = maps:filter(fun(_, {value, _}) -> false; (_, _) -> true end, Vars),
                    erlang:raise(error, {unavailable_values, Unavailable}, []).
                """, [Entrypoint, length(FreeVars)])]
            },
            compile(ModuleSource)
    end.

-spec compile_guard(GuardExpr, Opts) -> {ok, compiled_expr()} | {error, compile_error()} when
    GuardExpr :: source_code(),
    Opts :: compile_opts().
compile_guard(GuardExpr, Opts = #{free_vars := FreeVars}) ->
    Module = module_name(guard, FreeVars, GuardExpr),
    case code:get_object_code(Module) of
        {Module, Code, _} ->
            {exports, [{Entrypoint, 1}]} = Module:module_info(exports),
            {ok, #{module => Module, entrypoint => Entrypoint, code => Code}};
        error ->
            Entrypoint = Module,

            StartLine = maps:get(start_line, Opts, 1),
            StartCol = maps:get(start_col, Opts, 1),

            VarsMatch = lists:join(~",", [io_lib:format("~p := {value, ~s}", [V, V]) || V <- FreeVars]),
            ModuleSource = #{
                header => io_lib:format(
                    ~"""
                    -module(~s).
                    -export([~s/1]).
                    ~s(#{vars := #{~s}}) when
                    """,
                    [Module, Entrypoint, Entrypoint, VarsMatch]
                ),
                body_start => {StartLine, StartCol},
                body => GuardExpr,
                footer => io_lib:format(
                    ~"""
                       -> true;
                    ~s(#{vars := Vars}) when map_size(Vars) =:= ~p ->
                        Unavailable = maps:filter(fun(_, {value, _}) -> false; (_, _) -> true end, Vars),
                        case map_size(Unavailable) of
                            0 -> false;
                            _ -> erlang:raise(error, {unavailable_values, Unavailable}, [])
                        end.
                    """,
                    [Entrypoint, length(FreeVars)]
                )
            },
            compile(ModuleSource)
    end.

%% -------------------------------------------------------------------
%% Helpers
%% -------------------------------------------------------------------

-doc """
Generates a content-addressable module name based on the
expression type,free variables, and expression source code.
""".
-spec module_name(Type, FreeVars, Source) -> module() when
    Type :: expr | guard,
    FreeVars :: [binary()],
    Source :: source_code().
module_name(Type, FreeVars, Source) ->
    TypeBin = atom_to_binary(Type),
    FreeVarsBin = iolist_to_binary(lists:join(~",", FreeVars)),
    Input = <<TypeBin/binary, ":", FreeVarsBin/binary, ":", Source/binary>>,
    Hash = crypto:hash(sha256, Input),
    ModuleName = io_lib:format("~s_~.16b", [?MODULE, crypto:bytes_to_integer(Hash)]),
    binary_to_atom(iolist_to_binary(ModuleName), utf8).

-spec compile(Source) -> {ok, compiled_expr()} | {error, compile_error()} when
    Source :: generated_source_code().
compile(#{header := Header, body_start := BodyStartLoc, body := Body, footer := Footer}) ->
    maybe
        {ok, BodyTokens, BodyEndLoc} ?= erl_scan:string(binary_to_string(Body), BodyStartLoc),
        {ok, FooterTokens, FooterEndLoc} ?= erl_scan:string(lists:flatten(Footer), BodyEndLoc),
        {ok, HeaderTokens, _} ?= erl_scan:string(lists:flatten(Header), FooterEndLoc),
        Tokens = HeaderTokens ++ strip_trailing_dot(BodyTokens) ++ FooterTokens,
        {ok, Forms} ?= parse_forms(Tokens, [], []),
        case compile:noenv_forms(Forms, [binary, deterministic, no_docs, no_lint, return_errors]) of
            {ok, Module, Code} when is_atom(Module), is_binary(Code) ->
                BeamFilename = atom_to_list(Module) ++ ".beam",
                {module, Module} = code:load_binary(Module, BeamFilename, Code),
                Exports = Module:module_info(exports),
                [Entrypoint] = [F || {F, 1} <- Exports, F /= module_info],
                edb_server_eval:stash_object_code(Module, BeamFilename, Code),
                {ok, #{module => Module, entrypoint => Entrypoint, code => Code}};
            {error, [{_Filename, [CompileErrorInfo | _]}], _Warns} ->
                {error, CompileErrorInfo}
        end
    else
        {error, ScanErrorInfo, _ErrorLoc = {_, _}} ->
            % erl_scan error
            {error, ScanErrorInfo};
        ParseError = {error, _} ->
            ParseError
    end.

-spec strip_trailing_dot(Tokens) -> Tokens when
    Tokens :: erl_scan:tokens().
strip_trailing_dot([]) -> [];
strip_trailing_dot([{dot, _}]) -> [];
strip_trailing_dot([Tok | Tokens]) -> [Tok | strip_trailing_dot(Tokens)].

-spec parse_forms(Tokens, AccForm, AccForms) -> {ok, Forms} | {error, erl_parse:error_info()} when
    Tokens :: erl_scan:tokens(),
    AccForm :: erl_scan:tokens(),
    AccForms :: [erl_parse:abstract_form()],
    Forms :: [erl_parse:abstract_form()].
parse_forms([], [], AccForms) ->
    {ok, lists:reverse(AccForms)};
parse_forms([Tok = {dot, _} | Toks], AccForm, AccForms) ->
    FormToks = lists:reverse([Tok | AccForm]),
    case erl_parse:parse_form(FormToks) of
        {ok, Form} ->
            parse_forms(Toks, [], [Form | AccForms]);
        Err = {error, _} ->
            Err
    end;
parse_forms([Tok | Toks], AccForm, AccForms) ->
    parse_forms(Toks, [Tok | AccForm], AccForms).

-spec binary_to_string(binary()) -> string().
binary_to_string(B) ->
    case unicode:characters_to_list(B, utf8) of
        S when is_list(S) -> S
    end.
