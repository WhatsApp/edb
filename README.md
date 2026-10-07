# edb

A modern step-debugger for Erlang. When a process hits a breakpoint, `edb` freezes the whole node so you can inspect every process running inside it. It is IDE agnostic and works with any IDE that [implements the Debugger Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/implementors/tools/).

It requires OTP 29 or later. For more technical details, see our [paper](https://dl.acm.org/doi/pdf/10.1145/3759161.3763047) in the Erlang 2025 Workshop.

## Getting Started

The quickest path to debugging an Erlang project with `edb` is from VS Code, using any extension that ships with a prebuilt `edb`, but most IDEs are supported.

### 1. Configure your IDE

If using VSCode, install the [Erlang Language Platform](https://marketplace.visualstudio.com/items?itemName=erlang-language-platform.erlang-language-platform) extension from the VS Code marketplace. It ships with a prebuilt `edb` and provides code-lenses to debug Common Test cases. For other IDEs see [below](#using-edb-from-other-ides).

### 2. Configure your rebar3 project

`edb` needs three compile options: `debug_info`, `beam_debug_info`, and `beam_debug_stack`. The first two add the symbol information needed to display variable names on a paused process. `beam_debug_stack` additionally preserves the values of variables that are no longer live, which is more useful for debugging but increases stack usage. In modules where the increased stack usage is problematic, it can be disabled by adding `-compile(no_beam_debug_stack).`

Since the debugger is a development-only tool, restrict the options to the `test` profile in your `rebar.config`:

```
{profiles, [
    {test, [
        {erl_opts, [debug_info, beam_debug_info, beam_debug_stack]}
    ]}
]}.
```

### 3. Add a launch configuration

Create `.vscode/launch.json` in your project. The example below covers the two common entry points: launching a `rebar3 shell` under the debugger, or attaching to an already-running node.

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "erlang-edb",
      "request": "launch",
      "name": "Launch rebar3 shell",
      "runInTerminal": {
        "kind": "integrated",
        "title": "rebar3 shell",
        "cwd": "${workspaceFolder}",
        "args": [
          "sh",
          "-c",
          "exec $0 \"$@\" --eval=\"$EDB_DAP_DEBUGGEE_INIT\"",
          "rebar3",
          "as",
          "test",
          "shell"
        ]
      },
      "config": {
        "nameDomain": "shortnames",
        "nodeInitCodeInEnvVar": "EDB_DAP_DEBUGGEE_INIT",
        "timeout": 300
      },
    },
    {
      "name": "Attach to node devel@localhost",
      "type": "erlang-edb",
      "request": "attach",
      "config": {
        "node": "devel@localhost",
        "cookie": "my-cookie",
        "cwd": "${workspaceFolder}"
      }
    }
  ]
}
```

Set a breakpoint, pick a configuration from the **Run and Debug** view, and press F5.

## Using edb from other IDEs

`edb` speaks DAP, so any DAP-compatible IDE can drive it. For non-VSCode setups, build `edb` from source (see [below](#building-from-source)) and follow the [DAP guide](docs/DAP.md):

* **Emacs**: pick a DAP client such as [dape](https://github.com/svaante/dape) or [dap-mode](https://github.com/emacs-lsp/dap-mode).
* **vim/neovim**: pick a DAP client such as [vimspector](https://github.com/puremourning/vimspector) or [nvim-dap](https://github.com/mfussenegger/nvim-dap).
* **IntelliJ**: set up the [lsp4j](https://github.com/redhat-developer/lsp4ij) plugin.
* **zed**: uses its native DAP support.

## Installing from a release

Prebuilt releases are published on the [Releases page](https://github.com/WhatsApp/edb/releases). Each release is a single portable tarball (Linux and macOS; Windows is not supported yet) containing an `edb` escript for OTP 28 and one for OTP 29 and later, plus an `edb` launcher that picks the right one based on the OTP version installed on your machine.

Requirements: Erlang/OTP 28 or later, with `erl` on your `PATH`.

```
$ tar -xzf edb-1.0.0.tar.gz
$ cd edb-1.0.0
$ EDB_DISPATCH_DRYRUN=1 ./edb
./otp-28/edb
```

The last command prints which bundled escript matches your installed OTP version. To start a debug server, run `./edb dap` (see the [DAP guide](docs/DAP.md)).

The launcher resolves its bundled escripts relative to itself, so keep `edb`, `otp-28/` and `otp-29/` together; you can put the extracted directory on your `PATH` or symlink `edb` from a directory already on it. IDE integrations can point at the extracted `edb` directly.

## Building from source

A version of `rebar3` built with Erlang/OTP 26 or higher is required. You can find instructions on how to build `rebar3` from source [here](https://rebar3.org/docs/getting-started/#installing-from-source).

```
$ rebar3 escriptize
```

The produced `edb` escript will be available in:

```
_build/default/bin/edb
```

## Troubleshooting

### DAP Logs

When starting `edb` as a DAP debugger, it logs useful information that can help you understand whether `edb` is communicating correctly with a client (typically, the IDE).

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
