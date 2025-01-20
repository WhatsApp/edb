---
sidebar_position: 9
---

# Troubleshooting

## DAP Logs

When started EDB as a DAP debugger, EDB logs useful information that can help you understanding whether EDB is communicating correctly with a client (tipically, the IDE).

To find the location of the EDB DAP logs on your machine, open an Erlang shell and run:

```
$ erl

Erlang/OTP [...]

Eshell [...] (press Ctrl+G to abort, type help(). for help)
1> filename:basedir(user_log, "edb").
```

That will return the path where you will find a `edb.log` file.
