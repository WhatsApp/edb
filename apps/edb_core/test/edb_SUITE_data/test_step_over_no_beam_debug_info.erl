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
%%
-module(test_step_over_no_beam_debug_info).

-compile([warn_missing_spec_all]).

-export([loop_starter/1]).

-spec loop() -> no_return().
loop() -> loop().

-spec loop_starter(Parent :: pid()) -> no_return().
loop_starter(Parent) ->
    Parent ! {started_loop, self()},
    loop().
