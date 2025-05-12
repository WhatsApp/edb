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
%%%---------------------------------------------------------------------------------
%%% % @format

-module(edb_dap_eval_delegate).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-moduledoc """
This module handles all the calls to edb:eval/1, and all callbacks
are defined here. Because of that, this module will end up being
transferred to the debuggee node, so the callbacks can be executed.

It is very important that this has no dependencies on anything other
than kernel, stdlib and edb_core, as those are the only apps that can
be assumed to be running on the debuggee.
""".

% Running
-export([eval/1]).

% Callbacks
-export([scopes_callback/1]).

% -----------------------------------------------------------------------------
% Types
% -----------------------------------------------------------------------------
-opaque callback(Result) :: fun((Vars :: edb:stack_frame_vars()) -> Result).
-export_type([callback/1]).

-type scope() :: #{
    type := process | locals | registers,
    variables := [variable()]
}.
-type variable() :: #{
    name := binary(),
    value := edb:value(),
    value_rep := binary()
}.
-export_type([scope/0, variable/0]).

% -----------------------------------------------------------------------------
% Running
% -----------------------------------------------------------------------------

-spec eval(Opts) ->
    not_paused | undefined | {ok, Result} | {eval_error, edb:eval_error()}
when
    Opts :: #{
        context := {pid(), edb:frame_id()},
        max_term_size => non_neg_integer(),
        timeout => timeout(),
        function := callback(Result)
    }.
eval(Opts0) ->
    Defaults = #{
        max_term_size => 1_000_000,
        timeout => 5_000
    },
    Opts1 = maps:merge(Defaults, Opts0),
    % eqwalizer:fixme spec of maps:merge() loses info
    edb:eval(Opts1).

% -----------------------------------------------------------------------------
% Callbacks for the "scopes" request
% -----------------------------------------------------------------------------

-spec scopes_callback(Pid) -> callback([scope()]) when
    Pid :: pid().
scopes_callback(Pid) ->
    fun(StackFrameVars) ->
        Scopes0 = [process_scope(Pid)],
        Scopes1 =
            case StackFrameVars of
                #{vars := Vars} ->
                    [locals_scope(Vars) | Scopes0];
                _ ->
                    [registers_scope(StackFrameVars) | Scopes0]
            end,
        Scopes1
    end.

-spec locals_scope(Vars) -> scope() when
    Vars :: #{Name :: binary() => edb:value()}.
locals_scope(Vars) ->
    #{
        type => locals,
        variables => [
            #{
                name => Name,
                value => Value,
                value_rep => value_rep(Value)
            }
         || Name := Value <- Vars
        ]
    }.

-spec registers_scope(StackFrameVars) -> scope() when
    StackFrameVars :: edb:stack_frame_vars().
registers_scope(StackFrameVars) ->
    RegSources = [
        {~"X", maps:get(xregs, StackFrameVars, [])},
        {~"Y", maps:get(yregs, StackFrameVars, [])}
    ],
    #{
        type => registers,
        variables => [
            #{
                name => format("~s~p", [Prefix, RegIdx]),
                value => RegValue,
                value_rep => value_rep(RegValue)
            }
         || {Prefix, Regs} <- RegSources,
            {RegIdx, RegValue} <- lists:enumerate(0, Regs)
        ]
    }.

-spec process_scope(Pid) -> scope() when Pid :: pid().
process_scope(Pid) ->
    MessagesVar =
        case erlang:process_info(Pid, messages) of
            {messages, Messages} ->
                [
                    #{
                        name => ~"Messages in queue",
                        value => {value, Messages},
                        value_rep => format("~p", [length(Messages)])
                    }
                ];
            _ ->
                []
        end,
    #{type => process, variables => MessagesVar}.

% -----------------------------------------------------------------------------
% Helpers
% -----------------------------------------------------------------------------

-spec value_rep(Val) -> binary() when
    Val :: edb:value().
value_rep({value, Value}) ->
    format("~p", [Value]);
value_rep({too_large, Size, Max}) ->
    format("Too Large (~p vs ~p)", [Size, Max]).

-spec format(Format, Args) -> binary() when
    Format :: io:format(),
    Args :: [term()].
format(Format, Args) ->
    case io_lib:format(Format, Args) of
        Chars when is_list(Chars) ->
            String = lists:flatten(Chars),
            case unicode:characters_to_binary(String) of
                Binary when is_binary(Binary) -> Binary
            end
    end.
