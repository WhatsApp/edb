-module(dummy_app_sup).
-behaviour(supervisor).

%% Public
-export([start_link/1]).

%% Internal
-export([init/1]).

-define(CHILD_MOD, archive_script_dict).

start_link(AppName) ->
   SupName = list_to_atom(atom_to_list(AppName) ++ "_sup"),
   supervisor:start_link({local, SupName}, ?MODULE, [AppName]).

init([AppName]) ->
    ChildSpecs = [
        {dummy_app,
            {dummy_app, start_link, [AppName]},
            permanent, timer:seconds(5), worker, [dummy_app]
        }
    ],
    {ok, {{one_for_one, 5, 10}, ChildSpecs}}.
