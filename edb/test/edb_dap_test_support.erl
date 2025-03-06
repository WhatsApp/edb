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
-typing([eqwalizer]).

%% Public API
-export([start_test_client/1]).
-export([start_session/4]).
-export([set_breakpoints/3]).
-export([ensure_process_in_bp/6]).
-export([get_stack_trace/2, get_scopes/2, get_variables/2]).
-export([get_top_frame/2]).

-export_type([client/0, peer/0]).

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

-spec start_session(Config, Node, Cookie, Cwd) -> {ok, client()} when
    Config :: ct_suite:ct_config(),
    Node :: node(),
    Cookie :: atom() | no_cookie,
    Cwd :: binary().
start_session(Config, Node, Cookie, Cwd) ->
    {ok, Client} = start_test_client(Config),

    AdapterID = atom_to_binary(?MODULE),
    Response1 = edb_dap_test_client:initialize(Client, #{adapterID => AdapterID}),
    ?assertMatch(#{request_seq := 1, type := response, success := true}, Response1),

    LaunchCommand = #{
        cwd => Cwd,
        command => ~"dummy",
        arguments => []
    },
    Response2 = edb_dap_test_client:launch(Client, #{
        config => #{
            launchCommand => LaunchCommand,
            targetNode => #{name => Node, cookie => Cookie}
        }
    }),
    ?assertMatch(#{request_seq := 2, type := response, success := true}, Response2),

    {ok, InitializedEvent} = edb_dap_test_client:wait_for_event(~"initialized", Client),
    ?assertMatch([#{event := ~"initialized"}], InitializedEvent),

    {ok, Client}.

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

-spec ensure_process_in_bp(Client, Peer, ModFilePath, Fun, Args, {line, Line}) ->
    {ok, ThreadId, StackFrames}
when
    Client :: client(),
    Peer :: peer(),
    ModFilePath :: binary(),
    Fun :: atom(),
    Args :: [term()],
    Line :: pos_integer(),
    ThreadId :: integer(),
    StackFrames :: [edb_dap_request_stack_trace:stack_frame()].
ensure_process_in_bp(Client, Peer, ModFilePath, Fun, Args, {line, Line}) ->
    ok = set_breakpoints(Client, ModFilePath, [Line]),
    Module = binary_to_atom(edb_test_support:file_name_all_to_binary(filename:basename(ModFilePath, ".erl"))),
    erlang:spawn(fun() -> peer:call(Peer, Module, Fun, Args) end),
    {ok, [StoppedEvent]} = edb_dap_test_client:wait_for_event(~"stopped", Client),
    ThreadId =
        case StoppedEvent of
            #{
                event := ~"stopped",
                body := #{
                    reason := ~"breakpoint",
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
    Frames :: [edb_dap_request_stack_trace:stack_frame()].
get_stack_trace(Client, ThreadId) ->
    case edb_dap_test_client:stack_trace(Client, #{threadId => ThreadId}) of
        #{type := response, success := true, body := #{stackFrames := StackFrames}} ->
            StackFrames
    end.

-spec get_scopes(Client, FrameId) -> #{ScopeName => Scope} when
    Client :: client(),
    FrameId :: number(),
    ScopeName :: binary(),
    Scope :: edb_dap_request_scopes:scope().
get_scopes(Client, FrameId) ->
    case edb_dap_test_client:scopes(Client, #{frameId => FrameId}) of
        #{
            command := ~"scopes",
            type := response,
            success := true,
            body := #{scopes := Scopes}
        } ->
            #{ScopeName => Scope || Scope = #{name := ScopeName} <- Scopes}
    end.

-spec get_variables(Client, Scope) -> #{VarName => VarInfo} when
    Client :: client(),
    Scope :: edb_dap_request_scopes:scope(),
    VarName :: binary(),
    VarInfo :: edb_dap_request_variables:variable().
get_variables(Client, Scope) ->
    #{variablesReference := VarRef} = Scope,
    case edb_dap_test_client:variables(Client, #{variablesReference => VarRef}) of
        #{
            command := ~"variables",
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
