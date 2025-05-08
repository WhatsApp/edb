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
-module(edb_server_stack_frames).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-moduledoc false.

-export([raw_stack_frames/1, raw_user_stack_frames/1]).
-export([user_frames_only/1, without_bottom_terminator_frame/1]).
-export([stack_frame_vars/5]).
-export([has_exception_handler/1]).

-spec raw_stack_frames(Pid) -> RawStackFrames when
    Pid :: pid(),
    RawStackFrames :: [erl_debugger:stack_frame()] | not_paused.
raw_stack_frames(Pid) ->
    % get immediate values, as they are free to transfer
    MaxTermSize = 1,
    case erl_debugger:stack_frames(Pid, MaxTermSize) of
        running ->
            not_paused;
        RawFrames when is_list(RawFrames) ->
            RawFrames
    end.

-spec raw_user_stack_frames(Pid) -> RawStackFrames when
    Pid :: pid(),
    RawStackFrames :: [erl_debugger:stack_frame()] | not_paused.
raw_user_stack_frames(Pid) ->
    case raw_stack_frames(Pid) of
        not_paused -> not_paused;
        RawFrames -> user_frames_only(RawFrames)
    end.

-doc """
Remove frames that are introduced due to handling of breakpoints, etc.
""".
-spec user_frames_only(RawFrames) -> RawFrames when RawFrames :: [erl_debugger:stack_frame()].
user_frames_only(RawFrames) ->
    lists:nthtail(non_user_frames_count(RawFrames, 0), RawFrames).

-spec non_user_frames_count(RawFrames, Count) -> Count when
    RawFrames :: [erl_debugger:stack_frame()],
    Count :: non_neg_integer().
non_user_frames_count([], _Count) ->
    % We've scanned all frames and didn't find a `<breakpoint>' frame, so they are all user frames
    0;
non_user_frames_count([{_FrameNo, '<breakpoint>', _} | _RawFrames], Count) ->
    Count + 1;
non_user_frames_count([_ | RawFrames], Count) ->
    non_user_frames_count(RawFrames, Count + 1).

-doc """
The "bottom" frame a terminator like `<terminate process normally>`, usually not useful to the user
""".
-spec without_bottom_terminator_frame(RawFrames) -> RawFrames when RawFrames :: [erl_debugger:stack_frame()].
without_bottom_terminator_frame(RawFrames) ->
    without_bottom_terminator_frame(RawFrames, []).

-spec without_bottom_terminator_frame(RawFrames, Acc) -> RawFrames when
    Acc :: RawFrames,
    RawFrames :: [erl_debugger:stack_frame()].
without_bottom_terminator_frame([{_FrameNo, Terminator, #{slots := []}}], Acc) when is_atom(Terminator) ->
    lists:reverse(Acc);
without_bottom_terminator_frame([RawFrame | RawFrames], Acc) ->
    without_bottom_terminator_frame(RawFrames, [RawFrame | Acc]).

-spec stack_frame_vars(Pid, FrameId, MaxTermSize, RawFrames, Opts) ->
    undefined | {ok, Result}
when
    Pid :: pid(),
    FrameId :: edb:frame_id(),
    MaxTermSize :: pos_integer(),
    RawFrames :: [erl_debugger:stack_frame()],
    Opts :: #{resolve_local_vars := boolean()},
    Result :: edb:stack_frame_vars().
stack_frame_vars(Pid, FrameId, MaxTermSize, RawFrames, Opts) ->
    case lookup_raw_frame(FrameId, RawFrames) of
        undefined ->
            undefined;
        {{FrameId, FrameFun, #{slots := FrameSlots}}, XRegsLocation} ->
            YRegs = #{yregs => stack_frame_y_regs(Pid, {FrameId, FrameSlots}, MaxTermSize)},

            XRegs =
                case XRegsLocation of
                    undefined ->
                        % Inner frame, X registers are not available
                        #{};
                    top_frame ->
                        % We are on the top-frame, so the process didn't hit a breakpoint,
                        % we can read the X registers directly from the process
                        case erl_debugger:xregs_count(Pid) of
                            running ->
                                error({running, Pid});
                            XRegsCount when is_integer(XRegsCount) ->
                                #{
                                    xregs => [
                                        xreg_value(Pid, XRegNo, MaxTermSize)
                                     || XRegNo <- lists:seq(0, XRegsCount - 1)
                                    ]
                                }
                        end;
                    {BpFrameId, _, #{slots := BpFrameSlots}} ->
                        % We are on the top-frame, but for a process that hit a breakpoint. We
                        % are given the "breakpoint frame" were all live X regs were saved.
                        % So we can retrieve them from this frame (as Y regs).
                        #{xregs => stack_frame_y_regs(Pid, {BpFrameId, BpFrameSlots}, MaxTermSize)}
                end,

            ResolveLocalVars = maps:get(resolve_local_vars, Opts),
            LocalVars =
                case FrameFun of
                    #{function := {M, _F, _A}, line := Line} when ResolveLocalVars, is_atom(M), is_integer(Line) ->
                        case edb_server_code:get_debug_info(M, Line) of
                            {error, _} ->
                                #{};
                            {ok, VarsDebugInfo} ->
                                #{
                                    vars => maps:map(
                                        fun
                                            (_, {x, N}) -> lists:nth(N + 1, maps:get(xregs, XRegs));
                                            (_, {y, N}) -> lists:nth(N + 1, maps:get(yregs, YRegs));
                                            (_, V = {value, _}) -> V
                                        end,
                                        VarsDebugInfo
                                    )
                                }
                        end;
                    _ ->
                        #{}
                end,
            {ok, maps:merge(maps:merge(XRegs, YRegs), LocalVars)}
    end.

%% Stack helpers

-spec has_breakpoint_frame([RawFrame]) -> boolean() when
    RawFrame :: erl_debugger:stack_frame().
has_breakpoint_frame([]) -> false;
has_breakpoint_frame([{_, '<breakpoint>', _} | _]) -> true;
has_breakpoint_frame([_ | MoreFrames]) -> has_breakpoint_frame(MoreFrames).

-spec lookup_raw_frame(FrameId :: pos_integer(), [RawFrame]) ->
    undefined | {RawFrame, ExtraInfo}
when
    RawFrame :: erl_debugger:stack_frame(),
    ExtraInfo :: undefined | top_frame | RawFrame.
lookup_raw_frame(FrameId, [TopFrame = {FrameId, _, _} | MoreFrames]) ->
    avoiding_frame_leaks({TopFrame, top_frame}, MoreFrames);
lookup_raw_frame(FrameId, RawFrames) ->
    lookup_raw_frame_1(FrameId, undefined, RawFrames).

-spec lookup_raw_frame_1(FrameId :: pos_integer(), OptBpFrame, [RawFrame]) ->
    undefined | {RawFrame, ExtraInfo}
when
    OptBpFrame :: undefined | top_frame | RawFrame,
    RawFrame :: erl_debugger:stack_frame(),
    ExtraInfo :: undefined | top_frame | RawFrame.
lookup_raw_frame_1(FrameId, undefined, Frames = [FoundFrame = {FrameId, _, _} | _]) ->
    avoiding_frame_leaks({FoundFrame, undefined}, Frames);
lookup_raw_frame_1(FrameId, BpFrame, [FoundFrame = {FrameId, _, _} | _]) ->
    {FoundFrame, BpFrame};
lookup_raw_frame_1(FrameId, undefined, [BpFrame = {_, '<breakpoint>', _} | Rest]) ->
    lookup_raw_frame_1(FrameId, BpFrame, Rest);
lookup_raw_frame_1(FrameId, _, [_ | Rest]) ->
    lookup_raw_frame_1(FrameId, undefined, Rest);
lookup_raw_frame_1(_FrameId, _OptBpFrame, []) ->
    undefined.

-spec avoiding_frame_leaks(FrameFound, RemainingRawFrames) -> undefined | FrameFound when
    RemainingRawFrames :: [erl_debugger:stack_frame()].
avoiding_frame_leaks(FrameFound, RemainingRawFrames) ->
    case has_breakpoint_frame(RemainingRawFrames) of
        false ->
            FrameFound;
        true ->
            % Avoid leaking private stack-frames (that is, those
            % that happened after the breakpoint was hit)
            undefined
    end.

-spec stack_frame_y_regs(Pid, {FrameId, FrameSlots}, MaxTermSize) -> [edb:value()] when
    Pid :: pid(),
    FrameId :: edb:frame_id(),
    FrameSlots :: [erl_debugger:stack_frame_slot()],
    MaxTermSize :: non_neg_integer().
stack_frame_y_regs(Pid, {FrameId, FrameSlots}, MaxTermSize) ->
    % There can't be any Y-regs after a catch handler, so make sure to ignore those slots
    YRegSlots = lists:takewhile(
        fun(Slot) -> not is_catch_slot(Slot) end,
        FrameSlots
    ),
    [
        assert_is_value(stack_frame_slot_content(Slot, MaxTermSize, {Pid, FrameId}))
     || Slot <- lists:enumerate(0, YRegSlots)
    ].

-spec stack_frame_slot_content(Slot, MaxSize, SourceFrame) -> Result when
    Slot :: {SlotNo :: pos_integer(), erl_debugger:stack_frame_slot()},
    MaxSize :: pos_integer(),
    SourceFrame :: {pid(), edb:frame_id()},
    Result :: edb:catch_handler() | edb:value().
stack_frame_slot_content({_SlotNo, {value, Val}}, _MaxSize, _SourceFrame) ->
    {value, Val};
stack_frame_slot_content({_SlotNo, {too_large, Size}}, MaxSize, _SourceFrame) when Size > MaxSize, is_number(Size) ->
    {too_large, Size, MaxSize};
stack_frame_slot_content({SlotNo, {too_large, _Size}}, MaxSize, {Pid, FrameId}) ->
    % We know this will match since:
    %  1. it can't be a `catch` since we got too_large, and
    %  2. it won't be too_large since we know MaxSize >= Size
    {value, _Val} = erl_debugger:peek_stack_frame_slot(Pid, FrameId, SlotNo, MaxSize);
stack_frame_slot_content({_SlotNo, {'catch', #{function := MFA, line := Line}}}, _MaxSize, _SourceFrame) ->
    {'catch', {MFA, {line, Line}}}.

-spec is_catch_slot(erl_debugger:stack_frame_slot()) -> boolean().
is_catch_slot({'catch', _}) -> true;
is_catch_slot(_) -> false.

-spec assert_is_value(edb:value() | edb:catch_handler()) -> edb:value().
assert_is_value(V = {value, _}) -> V;
assert_is_value(V = {too_large, _, _}) -> V.

-spec has_exception_handler(Frame) -> boolean() when
    Frame :: erl_debugger:stack_frame().
has_exception_handler({_, _, #{slots := Slots}}) ->
    lists:any(
        fun
            ({'catch', _}) -> true;
            (_) -> false
        end,
        Slots
    ).

%% X-register helpers

-spec xreg_value(Pid, XRegNo, MaxTermSize) -> Result when
    Pid :: pid(),
    XRegNo :: non_neg_integer(),
    MaxTermSize :: non_neg_integer(),
    Result :: edb:value().
xreg_value(Pid, XRegNo, MaxTermSize) ->
    case erl_debugger:peek_xreg(Pid, XRegNo, MaxTermSize) of
        {value, Val} ->
            {value, Val};
        {too_large, Size} ->
            {too_large, Size, MaxTermSize}
    end.
