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

%%% % @format

-module(edb_dap_test_support).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

%% Public API
-export([start_test_client/1]).
-export([start_session/3]).
-export([load_file_and_set_breakpoints/5, set_breakpoints/3]).
-export([ensure_process_in_bp/7]).
-export([get_stack_trace/2, get_scopes/2, get_variables/2]).
-export([get_top_frame/2]).

-export_type([client/0, peer/0, module_spec/0]).

% @fb-only
-include_lib("stdlib/include/assert.hrl").
-include_lib("common_test/include/ct.hrl").

%%--------------------------------------------------------------------
%% Public API
%%--------------------------------------------------------------------

-type client() :: pid().
-type peer() :: edb_test_support:peer().

-spec start_test_client(Config :: ct_suite:ct_config()) -> {ok, client()}.
start_test_client(Config) ->
    DataDir = ?config(data_dir, Config),
    Executable = filename:join([DataDir, "edb"]),
    Args = ["dap"],
    edb_dap_test_client:start_link(Executable, Args).

-spec start_session(Config, Node, Cookie) -> {ok, client(), Cwd :: binary()} when
    Config :: ct_suite:ct_config(),
    Node :: node(),
    Cookie :: atom() | no_cookie.
start_session(Config, Node, Cookie) ->
    {ok, Client} = start_test_client(Config),

    AdapterID = atom_to_binary(?MODULE),
    Response1 = edb_dap_test_client:initialize(Client, #{adapterID => AdapterID}),
    ?assertMatch(#{request_seq := 1, type := response, success := true}, Response1),

    PrivDir = ?config(priv_dir, Config),
    Cwd = unicode:characters_to_binary(PrivDir),
    LaunchCommand = #{
        cwd => Cwd,
        command => ~"dummy",
        arguments => []
    },
    Response2 = edb_dap_test_client:launch(Client, #{
        launchCommand => LaunchCommand, targetNode => #{name => Node, cookie => Cookie}
    }),
    ?assertMatch(#{request_seq := 2, type := response, success := true}, Response2),

    {ok, InitializedEvent} = edb_dap_test_client:wait_for_event(~"initialized", Client),
    ?assertMatch([#{event := ~"initialized"}], InitializedEvent),

    {ok, Client, Cwd}.

-type module_spec() :: {filename, file:name_all()} | {filepath, file:name_all()} | {source, binary() | string()}.
-spec load_file_and_set_breakpoints(Config, Peer, Client, ModuleSpec, Lines) -> {ok, Module, FilePath} when
    Config :: ct_suite:ct_config(),
    Peer :: peer(),
    Client :: client(),
    ModuleSpec :: module_spec(),
    Lines :: [pos_integer()],
    Module :: module(),
    FilePath :: binary().
load_file_and_set_breakpoints(Config, Peer, Client, {filename, FileName}, Lines) ->
    DataDir = ?config(data_dir, Config),
    PrivDir = ?config(priv_dir, Config),
    FilePath = filename:join(DataDir, FileName),
    FileCopyPath = filename:join(PrivDir, FileName),
    {ok, Contents} = file:read_file(FilePath),
    ok = file:write_file(FileCopyPath, Contents),
    load_file_and_set_breakpoints(Config, Peer, Client, {filepath, FileCopyPath}, Lines);
load_file_and_set_breakpoints(Config, Peer, Client, {filepath, FilePath0}, Lines) ->
    PrivDir = ?config(priv_dir, Config),
    {ok, Module} = edb_test_support:compile_and_load_file_in_peer(#{source => FilePath0, peer => Peer, ebin => PrivDir}),
    FilePath1 = unicode:characters_to_binary(FilePath0),
    ok = set_breakpoints(Client, FilePath1, Lines),
    {ok, Module, FilePath1};
load_file_and_set_breakpoints(Config, Peer, Client, {source, Source}, Lines) ->
    MatchModuleRegex = "-module\\(([^)]+)\\)\\.",
    case re:run(Source, MatchModuleRegex, [{capture, all_but_first, list}]) of
        {match, [ModuleName]} ->
            PrivDir = ?config(priv_dir, Config),
            FilePath = filename:join(PrivDir, ModuleName ++ ".erl"),
            file:write_file(FilePath, Source),
            load_file_and_set_breakpoints(Config, Peer, Client, {filepath, FilePath}, Lines);
        nomatch ->
            error(couldnt_parse_module_name)
    end.

-spec set_breakpoints(Client, FilePath, Lines) -> ok when
    Client :: client(),
    FilePath :: binary(),
    Lines :: [pos_integer()].
set_breakpoints(Client, FilePath, Lines) ->
    SetBpsResponse = edb_dap_test_client:set_breakpoints(Client, #{
        source => #{path => FilePath},
        breakpoints => [#{line => Line} || Line <- Lines]
    }),
    ExpectedBpsSet = [#{line => Line, verified => true} || Line <- Lines],
    ?assertMatch(
        #{
            type := response,
            success := true,
            body := #{breakpoints := ExpectedBpsSet}
        },
        SetBpsResponse
    ),
    ok.

-spec ensure_process_in_bp(Config, Client, Peer, ModSpec, Fun, Args, {line, Line}) -> {ok, ThreadId, StackFrames} when
    Config :: ct_suite:ct_config(),
    Client :: client(),
    Peer :: peer(),
    ModSpec :: module_spec(),
    Fun :: atom(),
    Args :: [term()],
    Line :: pos_integer(),
    ThreadId :: integer(),
    StackFrames :: [edb_dap:stack_frame()].
ensure_process_in_bp(Config, Client, Peer, ModSpec, Fun, Args, {line, Line}) ->
    {ok, Module, ModFilePath} = load_file_and_set_breakpoints(Config, Peer, Client, ModSpec, [Line]),
    erlang:spawn(fun() -> peer:call(Peer, Module, Fun, Args) end),
    {ok, [StoppedEvent]} = edb_dap_test_client:wait_for_event(<<"stopped">>, Client),
    ThreadId =
        case StoppedEvent of
            #{
                event := <<"stopped">>,
                body := #{
                    reason := <<"breakpoint">>,
                    preserveFocusHint := false,
                    threadId := ThreadId_,
                    allThreadsStopped := true
                }
            } when is_integer(ThreadId_) ->
                ThreadId_;
            UnexpectedStopped ->
                error({unexpected_stopped_event, UnexpectedStopped})
        end,
    case edb_dap_test_client:stack_trace(Client, #{threadId => ThreadId}) of
        #{
            type := response,
            success := true,
            body := #{stackFrames := StackFrames = [#{line := Line, source := #{path := ModFilePath}} | _]}
        } ->
            {ok, ThreadId, StackFrames};
        UnexpectedStackTrace ->
            error({unexpected_stack_trace, UnexpectedStackTrace})
    end.

-spec get_stack_trace(Client, ThreadId) -> Frames when
    Client :: client(),
    ThreadId :: integer(),
    Frames :: [edb_dap:stack_frame()].
get_stack_trace(Client, ThreadId) ->
    case edb_dap_test_client:stack_trace(Client, #{threadId => ThreadId}) of
        #{type := response, success := true, body := #{stackFrames := StackFrames}} ->
            StackFrames
    end.

-spec get_scopes(Client, FrameId) -> #{ScopeName => Scope} when
    Client :: client(),
    FrameId :: edb_dap:stack_frame_id(),
    ScopeName :: binary(),
    Scope :: edb_dap:scope().
get_scopes(Client, FrameId) ->
    case edb_dap_test_client:scopes(Client, #{frameId => FrameId}) of
        #{
            command := <<"scopes">>,
            type := response,
            success := true,
            body := #{scopes := Scopes}
        } ->
            #{ScopeName => Scope || Scope = #{name := ScopeName} <- Scopes}
    end.

-spec get_variables(Client, Scope) -> #{VarName => VarInfo} when
    Client :: client(),
    Scope :: edb_dap:scope(),
    VarName :: binary(),
    VarInfo :: edb_dap:variable().
get_variables(Client, Scope) ->
    #{variablesReference := VarRef} = Scope,
    case edb_dap_test_client:variables(Client, #{variablesReference => VarRef}) of
        #{
            command := <<"variables">>,
            type := response,
            success := true,
            body := #{variables := Vars}
        } ->
            #{VarName => Var || Var = #{name := VarName} <- Vars}
    end.

-spec get_top_frame(Client, ThreadId) -> TopFrame when
    Client :: client(),
    ThreadId :: integer(),
    TopFrame :: #{name := binary(), line := pos_integer(), vars := #{binary() => binary()}}.
get_top_frame(Client, ThreadId) ->
    [TopFrame | _] = get_stack_trace(Client, ThreadId),
    #{id := FrameId, name := Name, line := Line} = TopFrame,
    #{~"Locals" := LocalsScope} = get_scopes(Client, FrameId),
    Locals = get_variables(Client, LocalsScope),
    #{
        name => Name,
        line => Line,
        vars => #{Var => Val || Var := #{value := Val} <- Locals}
    }.
