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
%% @doc edb public API
%% @end
%%%-------------------------------------------------------------------
%% % @format
-module(edb_app).

%% erlfmt:ignore
% @fb-only: 
-compile(warn_missing_spec_all).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()}.
start(_StartType, _StartArgs) ->
    {ok, _Sup} = edb_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    ok.

%% internal functions
