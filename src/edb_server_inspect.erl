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
-module(edb_server_inspect).

%% erlfmt:ignore
% @fb-only: 
-compile(warn_missing_spec_all).

-moduledoc false.

% erlint-ignore dialyzer_override
-dialyzer({nowarn_function, [get_debug_info/2]}).
-ignore_xref([{code, get_debug_info, 1}]).

-export([get_top_frame_id/1]).
-export([format_stack_frames/1]).
-export([stack_frame_vars/5]).

%% Inspecting stack frames

-spec get_top_frame_id(RawFrames) -> edb:frame_id() when
    RawFrames :: [erl_debugger:stack_frame()].
get_top_frame_id([{_, '<breakpoint>', _}, {FrameId, _, _} | _]) ->
    FrameId;
get_top_frame_id([{CandidateId, _, _} | OtherFrames]) ->
    get_top_frame_id_1(CandidateId, OtherFrames).

-spec get_top_frame_id_1(CandidateId, OtherRawFrames) -> edb:frame_id() when
    CandidateId :: edb:frame_id(),
    OtherRawFrames :: [erl_debugger:stack_frame()].
get_top_frame_id_1(CandidateId, []) ->
    CandidateId;
get_top_frame_id_1(_, [{_, '<breakpoint>', _}, {FrameId, _, _} | _]) ->
    FrameId;
get_top_frame_id_1(CandidateId, [_ | OtherRawFrames]) ->
    get_top_frame_id_1(CandidateId, OtherRawFrames).

-spec format_stack_frames(RawFrames) -> FormattedFrames when
    RawFrames :: [erl_debugger:stack_frame()],
    FormattedFrames :: [edb:stack_frame()].
format_stack_frames(RawFrames) ->
    format_stack_frames_1(RawFrames, []).

-spec format_stack_frames_1([RawFrame], Acc) -> Acc when
    RawFrame :: erl_debugger:stack_frame(),
    Acc :: [edb:stack_frame()].
format_stack_frames_1([{_FrameNo, Terminator, #{slots := []}}], Acc) when is_atom(Terminator) ->
    % Stuff like '<terminate process normally>' are not useful to the user
    lists:reverse(Acc);
format_stack_frames_1([{_FrameNo, '<breakpoint>', _} | Rest], _Acc) ->
    % Everything after the breakpoint frame are implementation details
    % of the debugger that we hide from the user
    format_stack_frames_1(Rest, []);
format_stack_frames_1([{FrameNo, 'unknown function', _} | RawFrames], Acc) ->
    FormattedFrame = #{
        id => FrameNo,
        mfa => unknown,
        source => undefined,
        line => undefined
    },
    format_stack_frames_1(RawFrames, [FormattedFrame | Acc]);
format_stack_frames_1([{FrameNo, #{function := MFA = {M, _, _}, line := Line}, _FrameInfo} | RawFrames], Acc) ->
    FormattedFrame = #{
        id => FrameNo,
        mfa => MFA,
        % TODO(T204197553) take md5 sum into account once it is available in the raw frame
        source => module_source(M),
        line => Line
    },
    format_stack_frames_1(RawFrames, [FormattedFrame | Acc]).

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
                        case get_debug_info(M, Line) of
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
stack_frame_slot_content({_SlotNo, {'catch', {MFA, Line}}}, _MaxSize, _SourceFrame) ->
    {'catch', {MFA, {line, Line}}}.

-spec is_catch_slot(erl_debugger:stack_frame_slot()) -> boolean().
is_catch_slot({'catch', _}) -> true;
is_catch_slot(_) -> false.

-spec assert_is_value(edb:value() | edb:catch_handler()) -> edb:value().
assert_is_value(V = {value, _}) -> V;
assert_is_value(V = {too_large, _, _}) -> V.

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

%% Debug-info helpers

-type var_debug_info() ::
    {x, non_neg_integer()} | {y, non_neg_integer()} | {value, term()}.

-spec get_debug_info(Module, Line) -> {ok, Result} | {error, Reason} when
    Module :: module(),
    Line :: pos_integer(),
    Reason :: not_found | no_debug_info | line_not_found,
    Result :: #{binary() => var_debug_info()}.
get_debug_info(Module, Line) when is_atom(Module) ->
    try
        % elp:ignore W0017 function available only on patched version of OTP
        code:get_debug_info(Module)
    of
        none ->
            {error, no_debug_info};
        DebugInfo when is_list(DebugInfo) ->
            case lists:keyfind(Line, 1, DebugInfo) of
                false ->
                    {error, line_not_found};
                {Line, {_NumSlots, VarValues}} ->
                    {ok,
                        #{
                            Var => assert_is_var_debug_info(Val)
                         || {Var, Val} <- VarValues, is_binary(Var)
                        }}
            end
    catch
        _:badarg ->
            {error, not_found}
    end.

-spec assert_is_var_debug_info(term()) -> var_debug_info().
assert_is_var_debug_info(X = {x, N}) when is_integer(N) -> X;
assert_is_var_debug_info(Y = {y, N}) when is_integer(N) -> Y;
assert_is_var_debug_info(V = {value, _}) -> V.

-spec module_source(Module :: module()) -> undefined | file:filename().
module_source(Module) ->
    try Module:module_info(compile) of
        CompileInfo when is_list(CompileInfo) ->
            case proplists:get_value(source, CompileInfo, undefined) of
                undefined ->
                    guess_module_source(Module);
                SourcePath ->
                    case filename:pathtype(SourcePath) of
                        relative ->
                            SourcePath;
                        _ ->
                            case filelib:is_regular(SourcePath) of
                                true ->
                                    SourcePath;
                                false ->
                                    case guess_module_source(Module) of
                                        undefined ->
                                            % We did our best, but this is the best we have
                                            SourcePath;
                                        GuessedSourcePath ->
                                            GuessedSourcePath
                                    end
                            end
                    end
            end
    catch
        _:_ ->
            undefined
    end.

-spec guess_module_source(Module :: module()) -> undefined | file:filename().
guess_module_source(Module) ->
    BeamName = atom_to_list(Module) ++ ".beam",
    case edb_server_call_proc:code_where_is_file(BeamName) of
        {call_error, _} ->
            undefined;
        {call_ok, non_existing} ->
            undefined;
        {call_ok, BeamPath} ->
            case filelib:find_source(BeamPath) of
                {ok, SourcePath} when is_list(SourcePath) ->
                    % eqwalizer:ignore incompatible_types -- file:name() vs file:filename() hell
                    SourcePath;
                _ ->
                    undefined
            end
    end.
