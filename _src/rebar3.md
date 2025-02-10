---
sidebar_position: 5
---

# Configure a rebar3 project

Before we can debug a [rebar3](https://rebar3.org/) project with EDB, we need to ensure that we build the code using the `beam_debug_info` option.

Since we want to only use the debugger to debug test and we don't want to affect production, these changes can be limited to the `test` profile.

Open the `rebar.config` file for the project and ensure the `beam_debug_info` option is included as part of `erl_opts`.

```
{profiles, [
    {test, [
        {erl_opts, [debug_info, beam_debug_info]}
    ]}
]}.
```
