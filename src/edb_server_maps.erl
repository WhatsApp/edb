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

-module(edb_server_maps).
-compile(warn_missing_spec_all).

%% erlfmt:ignore
% @fb-only: 

%% Public API
-export([add/3, add/4, add/5]).

-spec add(Key, Value, Map) -> Map when
    Map :: #{Key => Value}.
add(Key, Value, Map) ->
    maps:put(Key, Value, Map).

-spec add(Key1, Key2, Value, Map) -> Map when
    Map :: #{Key1 => #{Key2 => Value}}.
add(Key1, Key2, Value, Map) ->
    maps:update_with(
        Key1,
        fun(Map1) -> add(Key2, Value, Map1) end,
        #{Key2 => Value},
        Map
    ).

-spec add(Key1, Key2, Key3, Value, Map) -> Map when
    Map :: #{Key1 => #{Key2 => #{Key3 => Value}}}.
add(Key1, Key2, Key3, Value, Map) ->
    maps:update_with(
        Key1,
        fun(Map1) -> add(Key2, Key3, Value, Map1) end,
        #{Key2 => #{Key3 => Value}},
        Map
    ).
