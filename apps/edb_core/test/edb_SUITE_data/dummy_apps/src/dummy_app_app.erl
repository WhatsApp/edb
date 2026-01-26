-module(dummy_app_app).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

start(_Type, [AppName]) ->
    dummy_app_sup:start_link(AppName).

stop(_State) ->
    ok.
