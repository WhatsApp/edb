---
sidebar_position: 3
---

# Get EDB

You can either download a pre-built version of the EDB debugger or build it from source.

## Download

You can visit the [Releases](https://github.com/WhatsApp/edb/releases) page for EDB and download a pre-built version of EDB.

You can also download an EDB version for a specific commit by visiting the [Commits History page](https://github.com/WhatsApp/edb/commits/main/), click on the "green tick" next to a given commit, click on "details" for the CI job, check the "Summary". You will find the pre-built versions among the "artifacts" for the commit.

## Build from source

A pre-built version of EDB for your OS/architecture may not be available. In that case you can build one from source. Remember to check the [Prerequisites](./prerequisites.md) sections for details.

    $ git clone https://github.com/WhatsApp/edb.git
    $ cd edb
    $ rebar3 escriptize

The produced `edb` escript will be available in:

    _build/default/bin/edb
