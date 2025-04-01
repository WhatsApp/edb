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
-module(edb_server_process).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).
-compile({no_auto_import, [process_info/1, process_info/2]}).

-moduledoc false.

% Suspending processes
-export([try_suspend_process/1, try_resume_process/1]).

% Process info
-export([excluded_processes_info/2]).
-export([processes_info/2]).

%% ------------------------------------------------------------------
%% Macros
%% ------------------------------------------------------------------
-define(is_internal_pid(Pid), (node(Pid) =:= node())).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%% The original erlang:process_info_item/0 and erlang:proces_info_result_item/0
%% types are not exported
-type erlang_process_info_item() ::
    current_location
    | group_leader
    | message_queue_len
    | parent
    | registered_name.
-type erlang_process_info_result_item() :: {term(), term()}.

%% ------------------------------------------------------------------
%% Suspending processes
%% ------------------------------------------------------------------
-spec try_suspend_process(Pid :: pid()) -> boolean().
try_suspend_process(Pid) ->
    try
        erlang:suspend_process(Pid)
    catch
        error:badarg:ST ->
            case erlang:is_process_alive(Pid) of
                false -> false;
                true -> erlang:raise(error, badarg, ST)
            end
    end.

-spec try_resume_process(Pid :: pid()) -> boolean().
try_resume_process(Pid) ->
    try
        true = erlang:resume_process(Pid)
    catch
        error:bardarg:ST ->
            case erlang:is_process_alive(Pid) of
                false -> true;
                true -> erlang:raise(error, badarg, ST)
            end
    end.

%% ------------------------------------------------------------------
%% Process info
%% ------------------------------------------------------------------

-spec excluded_processes_info(#{Pid => Reasons}, Fields) -> #{Pid => Info} when
    Pid :: pid(),
    Reasons :: [edb:exclusion_reason()],
    Fields :: [edb:process_info_field()],
    Info :: edb:process_info().
excluded_processes_info(Procs, Fields) ->
    Fields0 = make_process_info_fields(Fields, running, [], #{}),
    #{
        Pid => Info
     || Pid := Reasons <- Procs,
        {ok, Info} <- [process_info(Pid, update_process_info_fields_exclusion_reasons(Reasons, Fields0))]
    }.

-spec processes_info(#{Pid => Status}, Fields) -> #{Pid => Info} when
    Pid :: pid(),
    Status :: raw_status(),
    Fields :: [edb:process_info_field()],
    Info :: edb:process_info().
processes_info(Procs, Fields) when is_map(Procs) ->
    Fields0 = make_process_info_fields(Fields, running, undefined, #{}),
    #{
        Pid => Info
     || Pid := Status <- Procs,
        {ok, Info} <- [process_info(Pid, update_process_info_fields_status(Status, Fields0))]
    }.

-spec process_info(Pid, Fields) -> {ok, Info} | undefined when
    Pid :: pid(),
    Fields :: process_info_fields(),
    Info :: edb:process_info().
process_info(Pid, Fields) ->
    Info0 = #{},
    {ok, Info1, ErlangProcessInfoFlags} = add_process_info_1(Info0, Fields),
    add_process_info_2(Pid, Info1, ErlangProcessInfoFlags, Fields).

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-type raw_status() :: running | paused | {breakpoint, edb:breakpoint_info()}.
-type process_info_fields() ::
    #{
        application => boolean() | {true, precomputed_group_leader_to_app_map()},
        current_bp => raw_status(),
        current_fun => boolean(),
        current_loc => boolean(),
        exclusion_reasons => [edb:exclusion_reason()],
        message_queue_len => boolean(),
        parent => boolean(),
        pid_string => boolean(),
        registered_name => boolean(),
        status => raw_status()
    }.

-type precomputed_group_leader_to_app_map() :: #{pid() => atom()}.

-spec make_process_info_fields(Fields, RawStatus, ExclusionReasons, Acc) -> Result when
    Fields :: [edb:process_info_field()],
    RawStatus :: raw_status(),
    ExclusionReasons :: undefined | [edb:exclusion_reason()],
    Acc :: process_info_fields(),
    Result :: process_info_fields().
make_process_info_fields([], _RawStatus, _ExclusionReasons, Acc) ->
    Acc;
make_process_info_fields([application | Rest], RawStatus, ExclusionReasons, Acc0) ->
    Acc1 = Acc0#{application => {true, group_leader_to_app()}},
    make_process_info_fields(Rest, RawStatus, ExclusionReasons, Acc1);
make_process_info_fields([current_bp | Rest], RawStatus, ExclusionReasons, Acc0) ->
    Acc1 = Acc0#{current_bp => RawStatus},
    make_process_info_fields(Rest, RawStatus, ExclusionReasons, Acc1);
make_process_info_fields([current_fun | Rest], RawStatus, ExclusionReasons, Acc0) ->
    Acc1 = Acc0#{current_fun => true},
    make_process_info_fields(Rest, RawStatus, ExclusionReasons, Acc1);
make_process_info_fields([current_loc | Rest], RawStatus, ExclusionReasons, Acc0) ->
    Acc1 = Acc0#{current_loc => true},
    make_process_info_fields(Rest, RawStatus, ExclusionReasons, Acc1);
make_process_info_fields([exclusion_reasons | Rest], RawStatus, ExclusionReasons, Acc0) ->
    Acc1 =
        case ExclusionReasons of
            undefined -> Acc0;
            Reasons -> Acc0#{exclusion_reasons => Reasons}
        end,
    make_process_info_fields(Rest, RawStatus, ExclusionReasons, Acc1);
make_process_info_fields([message_queue_len | Rest], RawStatus, ExclusionReasons, Acc0) ->
    Acc1 = Acc0#{message_queue_len => true},
    make_process_info_fields(Rest, RawStatus, ExclusionReasons, Acc1);
make_process_info_fields([parent | Rest], RawStatus, ExclusionReasons, Acc0) ->
    Acc1 = Acc0#{parent => true},
    make_process_info_fields(Rest, RawStatus, ExclusionReasons, Acc1);
make_process_info_fields([pid_string | Rest], RawStatus, ExclusionReasons, Acc0) ->
    Acc1 = Acc0#{pid_string => true},
    make_process_info_fields(Rest, RawStatus, ExclusionReasons, Acc1);
make_process_info_fields([registered_name | Rest], RawStatus, ExclusionReasons, Acc0) ->
    Acc1 = Acc0#{registered_name => true},
    make_process_info_fields(Rest, RawStatus, ExclusionReasons, Acc1);
make_process_info_fields([status | Rest], RawStatus, ExclusionReasons, Acc0) ->
    Acc1 = Acc0#{status => RawStatus},
    make_process_info_fields(Rest, RawStatus, ExclusionReasons, Acc1).

-spec update_process_info_fields_status(Status, Fields0) -> Fields1 when
    Status :: raw_status(),
    Fields0 :: process_info_fields(),
    Fields1 :: process_info_fields().
update_process_info_fields_status(Status, Fields0) ->
    Fields1 =
        case Fields0 of
            #{status := _} -> Fields0#{status => Status};
            _ -> Fields0
        end,
    case Fields1 of
        #{current_bp := _} -> Fields1#{current_bp => Status};
        _ -> Fields1
    end.
-spec update_process_info_fields_exclusion_reasons(ExclusionReasons, Fields0) -> Fields1 when
    ExclusionReasons :: [edb:exclusion_reason()],
    Fields0 :: process_info_fields(),
    Fields1 :: process_info_fields().
update_process_info_fields_exclusion_reasons(ExclusionReasons, Fields0) ->
    case Fields0 of
        #{exclusion_reasons := _} -> Fields0#{exclusion_reasons => ExclusionReasons};
        _ -> Fields0
    end.

-spec add_process_info_1(Info0, Fields) -> {ok, Info1, ErlangProcessInfoItems} when
    Fields :: process_info_fields(),
    ErlangProcessInfoItems :: [erlang_process_info_item()],
    Info0 :: edb:process_info(),
    Info1 :: edb:process_info().
add_process_info_1(Info0, #{status := S} = Fields0) ->
    Info1 =
        case S of
            running ->
                Info0#{status => running};
            paused ->
                Info0#{status => paused};
            {breakpoint, _} ->
                Info0#{status => breakpoint}
        end,
    Fields1 = maps:remove(status, Fields0),
    add_process_info_1(Info1, Fields1);
add_process_info_1(Info0, #{current_bp := S} = Fields0) ->
    Info1 =
        case S of
            running ->
                Info0;
            paused ->
                Info0;
            {breakpoint, #{line := Line}} ->
                Info0#{current_bp => {line, Line}}
        end,
    Fields1 = maps:remove(current_bp, Fields0),
    add_process_info_1(Info1, Fields1);
add_process_info_1(Info0, #{exclusion_reasons := Reasons} = Fields0) ->
    Info1 = Info0#{exclusion_reasons => Reasons},
    Fields1 = maps:remove(exclusion_reasons, Fields0),
    add_process_info_1(Info1, Fields1);
add_process_info_1(Info, Fields) ->
    ErlangProcessInfoItems = required_process_info_items(maps:keys(Fields), []),
    {ok, Info, ErlangProcessInfoItems}.

-spec required_process_info_items(FieldKeys, Acc) -> Items when
    FieldKeys :: [FieldKey],
    FieldKey ::
        application
        | current_fun
        | current_loc
        | message_queue_len
        | parent
        | pid_string
        | registered_name,
    Acc :: [erlang_process_info_item()],
    Items :: [erlang_process_info_item()].
required_process_info_items([], Acc) ->
    lists:uniq(Acc);
required_process_info_items([application | Rest], Acc) ->
    required_process_info_items(Rest, [group_leader | Acc]);
required_process_info_items([current_fun | Rest], Acc) ->
    required_process_info_items(Rest, [current_location | Acc]);
required_process_info_items([current_loc | Rest], Acc) ->
    required_process_info_items(Rest, [current_location | Acc]);
required_process_info_items([message_queue_len | Rest], Acc) ->
    required_process_info_items(Rest, [message_queue_len | Acc]);
required_process_info_items([parent | Rest], Acc) ->
    required_process_info_items(Rest, [parent | Acc]);
required_process_info_items([pid_string | Rest], Acc) ->
    required_process_info_items(Rest, Acc);
required_process_info_items([registered_name | Rest], Acc) ->
    required_process_info_items(Rest, [registered_name | Acc]).

-spec add_process_info_2(Pid, Info0, ErlangProcessInfoItems, Fields) -> {ok, Info1} | undefined when
    Pid :: pid(),
    Fields :: process_info_fields(),
    ErlangProcessInfoItems :: [erlang_process_info_item()],
    Info0 :: edb:process_info(),
    Info1 :: edb:process_info().
add_process_info_2(Pid, Info0, ErlangProcessInfoItems, Fields) ->
    MaybeRawInfo =
        case ErlangProcessInfoItems of
            [] -> [];
            _ -> erlang:process_info(Pid, ErlangProcessInfoItems)
        end,

    Info1 =
        case Fields of
            #{pid_string := true} ->
                PidStr = iolist_to_binary(io_lib:format(~"~p", [Pid])),
                Info0#{pid_string => PidStr};
            _ ->
                Info0
        end,

    case MaybeRawInfo of
        % Pid not alive
        undefined ->
            undefined;
        RawInfo ->
            Info2 = lists:foldl(
                fun(Info, Acc) -> fold_process_info(Info, Acc, Fields) end,
                Info1,
                RawInfo
            ),
            {ok, Info2}
    end.

-spec fold_process_info(ProcInfo, Acc, Fields) -> Acc when
    ProcInfo :: erlang_process_info_result_item(),
    Acc :: edb:process_info(),
    Fields :: process_info_fields().
fold_process_info(ProcInfo, Acc, Fields) ->
    WantsApp = maps:get(application, Fields, false),
    WantsFun = maps:get(current_fun, Fields, false),
    WantsLoc = maps:get(current_loc, Fields, false),
    WantsParent = maps:get(parent, Fields, false),
    WantsRegName = maps:get(registered_name, Fields, false),
    WantsMessageQueueLen = maps:get(message_queue_len, Fields, false),

    case ProcInfo of
        {current_location, {M, F, A, Loc}} when WantsFun; WantsLoc ->
            Acc1 =
                case WantsFun of
                    false ->
                        Acc;
                    true ->
                        (is_atom(M) andalso is_atom(F) andalso is_number(A)) orelse throw({invalid_mfa, {M, F, A}}),
                        Acc#{current_fun => {M, F, A}}
                end,
            case Loc of
                [{file, File}, {line, Line}] when WantsLoc, is_list(File), is_number(Line) ->
                    % eqwalizer:ignore We know File is a string
                    Acc1#{current_loc => {File, Line}};
                _ ->
                    Acc1
            end;
        {group_leader, GL} when is_pid(GL) ->
            MaybeApp =
                case WantsApp of
                    false ->
                        undefined;
                    true ->
                        group_leader_app(GL);
                    {true, Precomputed} when is_map(Precomputed) ->
                        case maps:find(GL, Precomputed) of
                            Found = {ok, _} -> Found;
                            error -> undefined
                        end
                end,
            case MaybeApp of
                undefined -> Acc;
                {ok, App} -> Acc#{application => App}
            end;
        {parent, ParentPid} when WantsParent ->
            case ParentPid of
                undefined ->
                    Acc;
                _ when is_pid(ParentPid), not ?is_internal_pid(ParentPid) ->
                    Acc#{parent => ParentPid};
                _ when is_pid(ParentPid) ->
                    case erlang:process_info(ParentPid, registered_name) of
                        undefined ->
                            Acc;
                        {registered_name, Name} when is_atom(Name) ->
                            Acc#{parent => Name};
                        _ ->
                            Acc#{parent => ParentPid}
                    end
            end;
        {registered_name, []} when WantsRegName ->
            Acc;
        {registered_name, N} when WantsRegName, is_atom(N) ->
            Acc#{registered_name => N};
        {message_queue_len, N} when WantsMessageQueueLen, is_number(N) ->
            Acc#{message_queue_len => N};
        _ ->
            Acc
    end.

-spec group_leader_app(GL :: pid()) -> undefined | {ok, atom()}.
group_leader_app(GL) ->
    case ets:match(ac_tab, {{application_master, '$1'}, GL}) of
        [[AppName]] -> {ok, AppName};
        _ -> undefined
    end.

-spec group_leader_to_app() -> #{pid() => atom()}.
group_leader_to_app() ->
    #{GL => App || [GL, App] <- ets:match(ac_tab, {{application_master, '$2'}, '$1'})}.
