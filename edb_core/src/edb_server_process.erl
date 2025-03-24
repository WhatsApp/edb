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
-compile({no_auto_import, [process_info/1]}).

-moduledoc false.

% Suspending processes
-export([try_suspend_process/1, try_resume_process/1]).

% Process info
-export([excluded_process_info/2, excluded_processes_info/1]).
-export([process_info/2, processes_info/1]).
-export([basic_process_info/2]).
-export_type([basic_process_info_fields/0]).

%% ------------------------------------------------------------------
%% Macros
%% ------------------------------------------------------------------
-define(is_internal_pid(Pid), (node(Pid) =:= node())).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
-type basic_process_info() :: #{
    application => atom(),
    current_fun => mfa(),
    current_loc => {File :: string(), Line :: pos_integer()},
    parent => atom() | pid(),
    registered_name => atom(),
    message_queue_len => non_neg_integer()
}.

%% The original erlang:proces_info_result_item/0 type is not exported
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

-spec excluded_process_info(Pid, Reasons) -> {ok, Info} | undefined when
    Pid :: pid(),
    Reasons :: [edb:exclusion_reason()],
    Info :: edb:excluded_process_info().
excluded_process_info(Pid, Reasons) ->
    case excluded_processes_info(#{Pid => Reasons}) of
        #{Pid := Info} ->
            {ok, Info};
        #{} ->
            undefined
    end.

-spec excluded_processes_info(#{Pid => Reasons}) -> #{Pid => Info} when
    Pid :: pid(),
    Reasons :: [edb:exclusion_reason()],
    Info :: edb:excluded_process_info().
excluded_processes_info(Procs) ->
    Fields = #{
        application => {true, group_leader_to_app()},
        current_fun => true,
        current_loc => false,
        parent => true,
        registered_name => true,
        message_queue_len => true
    },
    #{Pid => Info || Pid := Reasons <- Procs, {ok, Info} <- [excluded_process_info(Pid, Reasons, Fields)]}.

-spec excluded_process_info(Pid, Reasons, Fields) -> {ok, Info} | undefined when
    Pid :: pid(),
    Reasons :: [edb:exclusion_reason()],
    Fields :: basic_process_info_fields(),
    Info :: edb:excluded_process_info().
excluded_process_info(Pid, Reasons, Fields) ->
    case basic_process_info(Pid, Fields) of
        undefined ->
            undefined;
        {ok, Info0} ->
            Info1 = Info0#{reason => Reasons},
            {ok, Info1}
    end.

-spec process_info(Pid, Status) -> {ok, Info} | undefined when
    Pid :: pid(),
    Status :: running | paused | {breakpoint, edb:breakpoint_info()},
    Info :: edb:process_info().
process_info(Pid, Status) ->
    case processes_info(#{Pid => Status}) of
        #{Pid := Info} ->
            {ok, Info};
        #{} ->
            undefined
    end.

-spec processes_info(#{Pid => Status}) -> #{Pid => Info} when
    Pid :: pid(),
    Status :: running | paused | {breakpoint, edb:breakpoint_info()},
    Info :: edb:process_info().
processes_info(Procs) when is_map(Procs) ->
    Fields = #{
        application => {true, group_leader_to_app()},
        current_fun => true,
        current_loc => true,
        parent => true,
        registered_name => true,
        message_queue_len => true
    },
    #{Pid => Info || Pid := Status <- Procs, {ok, Info} <- [process_info(Pid, Status, Fields)]}.

-spec process_info(Pid, Status, Fields) -> {ok, Info} | undefined when
    Pid :: pid(),
    Status :: running | paused | {breakpoint, edb:breakpoint_info()},
    Fields :: basic_process_info_fields(),
    Info :: edb:process_info().
process_info(Pid, Status, Fields) ->
    case basic_process_info(Pid, Fields) of
        undefined ->
            undefined;
        {ok, Info0} ->
            Info1 =
                case Status of
                    running ->
                        Info0#{status => running};
                    paused ->
                        Info0#{status => paused};
                    {breakpoint, #{line := Line}} ->
                        Info0#{status => breakpoint, current_bp => {line, Line}}
                end,
            {ok, Info1}
    end.

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-type basic_process_info_fields() ::
    #{
        application := boolean() | {true, precomputed_group_leader_to_app_map()},
        current_fun := boolean(),
        current_loc := boolean(),
        parent := boolean(),
        registered_name := boolean(),
        message_queue_len := boolean()
    }.

-type precomputed_group_leader_to_app_map() :: #{pid() => atom()}.

-spec basic_process_info(pid(), Fields) -> {ok, Info} | undefined when
    Fields :: basic_process_info_fields(),
    Info :: basic_process_info().
basic_process_info(Pid, Fields) ->
    MaybeRawInfo = erlang:process_info(
        Pid,
        [current_location, group_leader, parent, registered_name, message_queue_len]
    ),

    case MaybeRawInfo of
        % Pid not alive
        undefined -> undefined;
        RawInfo -> {ok, basic_process_info_1(RawInfo, Fields)}
    end.

-spec basic_process_info_1(RawProcessInfo, Fields) -> basic_process_info() when
    RawProcessInfo :: [erlang_process_info_result_item()],
    Fields :: basic_process_info_fields().
basic_process_info_1(RawProcessInfo, Fields) ->
    lists:foldl(
        fun(Info, Acc) -> fold_process_info(Info, Acc, Fields) end,
        #{},
        RawProcessInfo
    ).

-spec fold_process_info(ProcInfo, Acc, Fields) -> Acc when
    ProcInfo :: erlang_process_info_result_item(),
    Acc :: basic_process_info(),
    Fields :: basic_process_info_fields().
fold_process_info(ProcInfo, Acc, Fields) ->
    #{
        application := WantsApp,
        current_fun := WantsFun,
        current_loc := WantsLoc,
        parent := WantsParent,
        registered_name := WantsRegName,
        message_queue_len := WantsMessageQueueLen
    } = Fields,

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
