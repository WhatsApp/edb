-module(test_stackframes). %01
-export([choose/2, ping/1, pong/0, hang/3, forty_two/0]). %02

choose(N, K) when N =:= K -> %04
    N div K; %05 (convoluted way to say 1, to have N and K "alive")
choose(N, K) when N > K -> %06
    ChooseNminus1K = choose(N-1, K), %07
    N * ChooseNminus1K. %08

ping(Proc) -> %10
    FinalSeq = ping(Proc, 0), %11
    {ok, FinalSeq}. %12

ping(Proc, Seq) -> %14
    Proc ! {ping, self(), Seq},  %15
    receive  %16
        {pong, Proc, Seq} -> %17
            ping(Proc, Seq + 1);  %18
        {stop, Proc, Seq} -> %19
            Seq %20
    end.  %21

pong() -> %23
    receive %24
        {ping, Proc, Seq} -> %25
            Proc ! {pong, self(), Seq}, %26
            pong() %27
    end. %28

hang(X, Y, Z) -> %30
    hang(X, Y, Z). %31

forty_two() -> %33
    0 + forty_two(1337). %34 (force a non-tail call)

forty_two(X) -> %36
    Six = 6, %37
    FortyTwo = Six * 7, %38
    _KeepXAlive = X + X, %39 (force X to be alive)
    FortyTwo. %40
