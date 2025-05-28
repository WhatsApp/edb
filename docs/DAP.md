# IDE integration via Debugger Adapter Protocol (DAP)

`edb` supports the [Debug Adapter Protocol (DAP)](https://microsoft.github.io/debug-adapter-protocol/), which means it can be
used with VSCode, vim/neovim, emacs and [any other IDE that implements it](https://microsoft.github.io/debug-adapter-protocol/implementors/tools/).

This document describes how to use the DAP integration in an IDE-agnostic way. Refer to your IDE's documentation for specific details on how
to set it up.

## Starting the DAP Server

Your IDE will need to be able to start `edb` in DAP mode. For that, configure it with the following command:

```
$PATH_TO_EDB/edb dap
```

## Debug Configurations

The DAP specificatoin allows for two modes of operation:
  1. *Attaching* to a running program, or
  2. *Launching* a new node program


`edb` supports both. For each of this modes, your VSCode need to send a JSON request that `edb` can understand.

### Attaching to a node

A typical attach request looks like this:


```json
{
  "type": "edb",
  "request": "attach",
  "name": "Attach to mynode",
  "config": {
    "node": "mynode@localhost",
    "cookie": "mycookie",
    "cwd": "${workspaceFolder}"
  }
}
```


| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `node` | string | required | Name of the Erlang node to attach to |
| `cookie` | string | optional | Cookie for connecting to the Erlang node |
| `cwd` | string | required | Working directory for resolving relative source files |
| `stripSourcePrefix` | string | optional | Prefix to strip from source file paths |


The `stripSourcePrefix` option can be useful in some mono-repo settings, when paths
are relative to the mono-repo root, but the editor is started from a sub-directory.

### Launching a new node

A typical launch request looks like this:

```json
{
  "type": "edb",
  "request": "launch",
  "name": "Launch Erlang Application",
  "runInTerminal": {
    "kind": "integrated",
    "cwd": "${workspaceFolder}",
    "args": ["erl", "-name", "debuggee@localhost"]
  },
  "config": {
    "nameDomain": "longnames",
    "stripSourcePrefix": "${workspaceFolder}/",
    "timeout": 60
  }
}
```

For launching, `edb` currently only supports IDEs that can handle the
"run-in-terminal" capabality, in which `edb` can tell the IDE what command to use
to start the program to be debugged.

##### `runInTerminal` (required)

Options here follow those of the ["runInTerminal" reverse-request](https://microsoft.github.io/debug-adapter-protocol/specification#Reverse_Requests_RunInTerminal) in the
DAP specification

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `kind` | string | optional | Terminal kind: `"integrated"` or `"external"` |
| `title` | string | optional | Title for the terminal window |
| `cwd` | string | required | Working directory for the Erlang node |
| `args` | string[] | required | Command line arguments to start the Erlang node |
| `env` | object | optional | Environment variables to set for the Erlang node |
| `argsCanBeInterpretedByShell` | boolean | optional | Whether args can be interpreted by the shell |

##### `config` (required)

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `nameDomain` | string | required | Node name domain: `"shortnames"` or `"longnames"` |
| `nodeInitCodeInEnvVar` | string | optional | Environment variable to store node initialization code |
| `stripSourcePrefix` | string | optional | Prefix to strip from source file paths |
| `timeout` | number | optional | Timeout in seconds for the debugger to attach (default: 60) |


After launching, a node needs to register with the node running `edb`. This way,
`edb` can set initial breakpoints before the node starts executing, etc. Normally,
this will be handled via options in `ERL_AFLAGS` and `edb` will wait until the
given `config.timeout` expires. In some settings, relying on `ERL_AFLAGS` may not
be an option and `edb` can instead store the command the new node needs to execute in
the environment variable provided in `nodeInitCodeInEnvVar` and it is then the user's
responsibility to ensure that the launched node runs this command at an appropriate
phase (typically, by including this environment variable somewhere in the given `runInTerminal.args`)

## Important Notes

1. The Erlang node you're attaching to must be started with the `+D` flag to enable debugging support.
2. For the launch configuration, EDB will automatically add the `+D` flag to the `ERL_AFLAGS` environment variable.

## IDE-Specific Configuration Examples

### Visual Studio Code

The Erlang Language Platform extension comes with `edb` support out of the box.

### emacs

TBP

### newvim

TBP
