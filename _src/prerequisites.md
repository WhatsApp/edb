---
sidebar_position: 2
---

# Prerequisites

`edb` currently requires a modified version of Erlang/OTP which, for convenience,
is checked in as a git submodule, until all require changes will make it upstream.

You can build and install the modified version of Erlang/OTP by doing:

    $ git submodule update --init
    $ pushd otp
    $ ./configure --prefix $(pwd)/../otp-bin
    $ make -j$(nproc)
    $ make -j$(nproc) install
    $ popd

**Note:** on Mac you may need to provide a custom installation path
for OpenSSl. Just replace the above configuration step with:

    $ ./configure --prefix $(pwd)/../otp-bin --with-ssl=$(brew --prefix openssl)

Then simply add the installation dir to your `$PATH`:

    $ export PATH=$(pwd)/otp-bin/bin:$PATH

Verify the Erlang installation:

    $ which erl # Should point to the newly built version of Erlang/OTP

You will also need a version of `rebar3` built with Erlang/OTP 26 or higher.
You can find instructions on how to build `rebar3` from source [here](https://rebar3.org/docs/getting-started/#installing-from-source).
