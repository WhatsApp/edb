# edb

A modern step-debugger for Erlang, that freezes the whole node when a process hits a breakpoint,
allowing for the inspection of every process running inside it. It is IDE agnostic and can be used from any IDE that
[implements the Debugger Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/implementors/tools/).

It requires OTP 28 or later. For more technical details, see our [paper](https://dl.acm.org/doi/pdf/10.1145/3759161.3763047) in
the Erlang 2025 Workshop.

> [!IMPORTANT]
> `edb` requires new debugging extensions exposed by OTP, so the development of both go hand in hand.
> The `main` branch of `edb` currently expects some extensions that have not yet been merged. If you
> are expecting to use `edb` on OTP 28.0 or 28.1, please use the `otp-28.0` branch of `edb` instead.

## Set it up

Instructions differ depending on the IDE.

### VSCode

On VSCode you need a debugging extension for Erlang that includes `edb`. Then see [this guide](https://code.visualstudio.com/docs/debugtest/debugging)
and the `edb` [DAP guide](docs/DAP.md).

* The [Erlang Language Platform](https://marketplace.visualstudio.com/items?itemName=erlang-language-platform.erlang-language-platform) extension
  provides a prebuilt version of `edb` and code-lenses to debug Common-Test testcases.

### Emacs

* Build `edb` from source (see [below](#building-from-source))
* Pick an emacs DAP client, such as [dape](https://github.com/svaante/dape) or [dap-mode](https://github.com/emacs-lsp/dap-mode)
* See the `edb` [DAP guide](docs/DAP.md)

### vim/neovim

* Build `edb` from source (see [below](#building-from-source))
* Pick a DAP client, such as [vimspector](https://github.com/puremourning/vimspector) or [nvim-dap](https://github.com/mfussenegger/nvim-dap)
* See the `edb` [DAP guide](docs/DAP.md)


### IntelliJ

* Build `edb` from source (see [below](#building-from-source))
* Setup the [lsp4j](https://github.com/redhat-developer/lsp4ij) plugin
* See the `edb` [DAP guide](docs/DAP.md)

### zed

* Build `edb` from source (see [below](#building-from-source))
* zed has native DAP support
* See the `edb` [DAP guide](docs/DAP.md)

## Configure a rebar3 project

Before we can debug a [rebar3](https://rebar3.org/) project with `edb`, we need to ensure that we build the code using the `debug_info` option, but also `beam_debug_info` and
`beam_debug_stack` options. The former adds debug symbol information needed to be able display variable names on a paused process; the latter
preserves the values of variables that are no longer live, which is more useful for debugging, but increases the stack usage. In modules
where the increased stack usage is problematic, it can be disabled by adding `-compile(no_beam_debug_stack).`

Since we want to only use the debugger during development and we don't want to affect production, these changes can be limited to the `test` profile.

Open the `rebar.config` file for the project and ensure one of these options is included as part of `erl_opts`.

```
{profiles, [
    {test, [
        {erl_opts, [debug_info, beam_debug_info, beam_debug_stack]}
    ]}
]}.
```

## Building from source
`edb` requires debugging extensions available since OTP 28.0, and more extensions are in the process of being
added. Because the `main` branch of `edb` always assumes that these additional extensions are present, if you
are building from source and targetting OTP 28.0 or 28.1, use the `otp-28.0` branch of `edb` instead.

Moreover, a version of `rebar3` built with Erlang/OTP 26 or higher is required. You can find instructions on how to build `rebar3`
from source [here](https://rebar3.org/docs/getting-started/#installing-from-source).

### Building the custom version of OTP
For convenience, a patched version of Erlang/OTP is checked in
as a git submodule.

You can build and install the modified version of Erlang/OTP by doing:

```
$ git submodule update --init
$ pushd otp
$ ./configure --prefix $(pwd)/../otp-bin
$ make -j$(nproc)
$ make -j$(nproc) install
$ popd
```

**Note:** on Mac you may need to provide a custom installation path
for OpenSSl. Just replace the above configuration step with:

```
$ ./configure --prefix $(pwd)/../otp-bin --with-ssl=$(brew --prefix openssl)
```

Then simply add the installation dir to your `$PATH`:

```
$ export PATH=$(pwd)/otp-bin/bin:$PATH
```

Verify the Erlang installation:

```
$ which erl # Should point to the newly built version of Erlang/OTP
```

### Building edb itself

```
$ rebar3 escriptize
```

The produced `edb` escript will be available in:

```
_build/default/bin/edb
```


## Troubleshooting

### DAP Logs

When starting `edb` as a DAP debugger, it logs useful information that can help you understanding whether `edb` is communicating correctly with a client (tipically, the IDE).

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
