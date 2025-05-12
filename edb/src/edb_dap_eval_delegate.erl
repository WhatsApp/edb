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

-export([eval/1]).

% -----------------------------------------------------------------------------
% Types
% -----------------------------------------------------------------------------
-opaque callback(Result) :: fun((Vars :: edb:stack_frame_vars()) -> Result).
-export_type([callback/1]).

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
