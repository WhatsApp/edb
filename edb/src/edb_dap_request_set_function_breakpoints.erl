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

%%% % @format

-module(edb_dap_request_set_function_breakpoints).

-moduledoc """
Handles Debug Adapter Protocol (DAP) setFunctionBreakpoints requests for the Erlang debugger.

The module follows the Microsoft Debug Adapter Protocol specification for
setFunctionBreakpoints requests: https://microsoft.github.io/debug-adapter-protocol/specification#Requests_SetFunctionBreakpoints
""".

%% erlfmt:ignore
% @fb-only[end= ]: -oncall("whatsapp_server_devx").
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_SetBreakpoints
-type arguments() :: #{
    %% The function names of the breakpoints.
    breakpoints := [function_breakpoint()]
}.
-type response() :: #{breakpoints := [breakpoint()]}.

-type function_breakpoint() :: #{
    %% The name of the function.
    %% Accepted formats:
    %% - {M, F, A}
    %% - fun M:F/A
    %% - M:F/A
    name := binary(),

    %% An expression for conditional breakpoints.
    %% It is only honored by a debug adapter if the corresponding capability
    %% `supportsConditionalBreakpoints` is true.
    condition => binary(),

    %% An expression that controls how many hits of the breakpoint are ignored.
    %% The debug adapter is expected to interpret the expression as needed.
    %% The attribute is only honored by a debug adapter if the corresponding
    %% capability `supportsHitConditionalBreakpoints` is true.
    hitCondition => binary()
}.

-type breakpoint() :: edb_dap_request_set_breakpoints:breakpoint().

-export_type([arguments/0, response/0]).
-export_type([breakpoint/0, function_breakpoint/0]).

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        breakpoints => edb_dap_parse:list(edb_dap_parse:template(function_breakpoint_template()))
    }.

-spec function_breakpoint_template() -> edb_dap_parse:template().
function_breakpoint_template() ->
    #{
        name => edb_dap_parse:binary(),
        condition => {optional, edb_dap_parse:binary()},
        hitCondition => {optional, edb_dap_parse:binary()}
    }.

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()} | {error, Reason :: binary()}.
parse_arguments(Args) ->
    Template = arguments_template(),
    edb_dap_parse:parse(Template, Args, reject_unknown).

-spec handle(State, Args) -> edb_dap_request:reaction(response()) when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(#{state := configuring}, Args) ->
    set_function_breakpoints(Args);
handle(#{state := attached}, Args) ->
    set_function_breakpoints(Args);
handle(_UnexpectedState, _) ->
    edb_dap_request:unexpected_request().

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-spec set_function_breakpoints(Args) -> edb_dap_request:reaction(response()) when
    Args :: arguments().
set_function_breakpoints(Args) ->
    #{breakpoints := BreakpointsReq} = Args,
    ParsedNames = lists:enumerate([parse_function_name(N) || #{name := N} <- BreakpointsReq]),
    IndexedMFAs = [{Idx, MFA} || {Idx, {ok, MFA}} <- ParsedNames],
    IndexedInvalidNames = [
        {Idx, #{verified => false, message => invalid_name_error(Name), reason => failed}}
     || {Idx, {invalid, Name}} <- ParsedNames
    ],

    RawResults = edb:set_function_breakpoints([MFA || {_, MFA} <- IndexedMFAs]),
    IndexedResults = lists:zipwith(
        fun
            ({Idx, MFA}, {MFA, ok}) ->
                {Idx, #{verified => true}};
            ({Idx, MFA}, {MFA, {error, Reason}}) ->
                Message = format_function_breakpoint_error(Reason),
                {Idx, #{verified => false, message => Message, reason => failed}}
        end,
        IndexedMFAs,
        RawResults
    ),

    % Ensure order of results matches order of requests
    BreakpointsResponse = [Result || {_Idx, Result} <- lists:sort(IndexedResults ++ IndexedInvalidNames)],
    #{response => edb_dap_request:success(#{breakpoints => BreakpointsResponse})}.

-spec parse_function_name(Name) -> {ok, mfa()} | {invalid, Name} when
    Name :: binary().
parse_function_name(Name) ->
    case unicode:characters_to_list(Name) of
        EncodingError when not is_list(EncodingError) -> {invalid, Name};
        NameStr ->
            case parse_function_name(NameStr, false) of
                OkResult = {ok, _} -> OkResult;
                error -> {invalid, Name}
            end
    end.

-spec parse_function_name(Name, IsRetry) -> {ok, mfa()} | error when
    Name :: string(),
    IsRetry :: boolean().
parse_function_name(Name, IsRetry) ->
    case erl_scan:string(Name) of
        {error, _, _} ->
            error;
        {ok, [], _} ->
            error;
        {ok, Tokens0, _} ->
            Tokens1 =
                case lists:last(Tokens0) of
                    {dot, _} -> Tokens0;
                    _ -> Tokens0 ++ [{dot, 1}]
                end,
            case erl_parse:parse_term(Tokens1) of
                {error, _} when not IsRetry ->
                    % If the name is `foo:bar/1`, let's try again prefixing `fun `
                    parse_function_name("fun " ++ Name, true);
                {error, _} ->
                    error;
                {ok, Fun} when is_function(Fun) ->
                    case maps:from_list(erlang:fun_info(Fun)) of
                        #{type := external, env := [], module := M, name := F, arity := A} ->
                            parse_mfa({M, F, A});
                        _ ->
                            error
                    end;
                {ok, Term} ->
                    parse_mfa(Term)
            end
    end.

-spec parse_mfa(term()) -> {ok, mfa()} | error.
parse_mfa({M, F, A}) when is_atom(M), is_atom(F), is_integer(A), A >= 0 ->
    {ok, {M, F, A}};
parse_mfa(_) ->
    error.

-spec invalid_name_error(Name) -> binary() when
    Name :: binary().
invalid_name_error(_Name) ->
    ~"Not a valid function name. Valid formats: `M:F/A`; `fun M:F/A`; {M, F, A}".

-spec format_function_breakpoint_error(Error) -> binary() when
    Error :: edb:add_function_breakpoint_error().
format_function_breakpoint_error(no_abstract_code) ->
    ~"Module is not compiled with the +debug_info option; required for function breakpoints";
format_function_breakpoint_error({badkey, _MFA = {_, _, _}}) ->
    ~"The function does not exist or the module was not found";
format_function_breakpoint_error(CommonError) ->
    edb_dap_request_set_breakpoints:format_breakpoint_error(CommonError).
