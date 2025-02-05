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
%% @doc Sample Erlang program for testing EDB
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(factorial).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-export([fact/1]).

-spec fact(non_neg_integer()) -> non_neg_integer().
fact(0) ->
    1;
fact(N) when N > 0 ->
    N * fact(N - 1).
