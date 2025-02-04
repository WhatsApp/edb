-module(test_pause).
-export([go/2]).

-spec go(Controller :: pid(), X :: integer()) -> ok.
go(Controller, X) when is_integer(X) ->
    Ref = erlang:make_ref(),
    Controller ! {self(), Ref, X},
    receive
        {continue, Ref} -> go(Controller, X+1)
    end.
