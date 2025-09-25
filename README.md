# edb

The next-generation debugger for Erlang.

## Prerequisites

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

## Get EDB

You can either download a pre-built version of the EDB debugger or build it from source.

## Download

You can visit the [Releases](https://github.com/WhatsApp/edb/releases) page for EDB and download a pre-built version of EDB.

You can also download an EDB version for a specific commit by visiting the [Commits History page](https://github.com/WhatsApp/edb/commits/main/), click on the "green tick" next to a given commit, click on "details" for the CI job, check the "Summary". You will find the pre-built versions among the "artifacts" for the commit.

## Build from source

A pre-built version of EDB for your OS/architecture may not be available. In that case you can build one from source. Remember to check the [Prerequisites](#prerequisites) sections for details.

    $ git clone https://github.com/WhatsApp/edb.git
    $ cd edb
    $ rebar3 escriptize

The produced `edb` escript will be available in:

    _build/default/bin/edb

## Usage

### Start the DAP adapter for `edb`

    $ _build/default/bin/edb dap

This is the command that you tipically want your IDE (VS Code, Emacs) to trigger.

## Configure a rebar3 project

Before we can debug a [rebar3](https://rebar3.org/) project with EDB, we need to ensure that we build the code using the `beam_debug_info` and
`beam_debug_stack` option. The former adds debug symbol information needed to be able display variable names on a paused process; the latter
preserves the values of variables that are no longer live, which is more useful for debugging, but increases the stack usage. In modules
where the increased stack usage is problematic, it can be disabled by adding `-compile(no_beam_debug_stack).`

Since we want to only use the debugger to debug test and we don't want to affect production, these changes can be limited to the `test` profile.

Open the `rebar.config` file for the project and ensure one if these options is included as part of `erl_opts`.

```
{profiles, [
    {test, [
        {erl_opts, [beam_debug_info, beam_debug_stack]}
    ]}
]}.
```

## Troubleshooting

### DAP Logs

When started EDB as a DAP debugger, EDB logs useful information that can help you understanding whether EDB is communicating correctly with a client (tipically, the IDE).

To find the location of the EDB DAP logs on your machine, open an Erlang shell and run:

```
$ erl

Erlang/OTP [...]

Eshell [...] (press Ctrl+G to abort, type help(). for help)
1> filename:basedir(user_log, "edb").
```

That will return the path where you will find a `edb.log` file.

## License

EDB is Apache 2.0 licensed, as found in the [LICENSE.md](./LICENSE.md) file.

## References

* [Terms of Use](https://opensource.fb.com/legal/terms)
* [Privacy Policy](https://opensource.fb.com/legal/privacy)

## Copyright

Copyright © Meta Platforms, Inc
