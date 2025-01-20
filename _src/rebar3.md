---
sidebar_position: 5
---

# Configure a rebar3 project

Before we can debug a [rebar3](https://rebar3.org/) project with EDB, we need to configure a few things:

1. Add `edb` as a dependency for the project
2. Ensure we build the code using the `beam_debug_info` option

Since we want to only use the debugger to debug test and we don't want to affect production, these changes can be limited to the `test` profile.

Open the `rebar.config` file for the project and ensure `edb` is part of the `deps` key for the `test` profile.
Also ensure the `beam_debug_info` option is included as part of `erl_opts`.

```
{profiles, [
    {test, [
        {deps, [
            {edb, {git, "https://github.com/WhatsApp/edb.git"}}
        ]},
        {erl_opts, [debug_info, beam_debug_info]}
    ]}
]}.
```
