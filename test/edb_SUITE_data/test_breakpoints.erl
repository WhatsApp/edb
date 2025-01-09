-module(test_breakpoints). %1
-export([go/1, do_stuff_and_wait/1]). %2
%3
-spec go(Controller :: pid()) -> ok. %4
go(Controller) -> %5
    sync(Controller, ?LINE), %6
    sync(Controller, ?LINE), %7
    sync(Controller, ?LINE), %8
    sync(Controller, ?LINE), %9
    ok. %10
%11
-spec do_stuff_and_wait(Controller :: pid()) -> ok. %12
do_stuff_and_wait(Controller) -> %13
    sync(Controller, ?LINE), %14
    receive _ -> ok end. %15

-spec sync(Controller :: pid(), Line :: pos_integer()) -> ok.
sync(Controller, Line) ->
    Me = self(),
    Controller ! {sync, Me, Line},
    ok.
