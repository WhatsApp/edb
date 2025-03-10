edb
=====

The next-generation debugger for Erlang, designed to provide advanced debugging capabilities and improve developer productivity.

Prerequisites
-------------

edb currently requires a modified version of Erlang/OTP which, for convenience, is checked in as a git submodule, until all require changes will make it upstream.

You can build and install the modified version of Erlang/OTP by doing:
```
$ git submodule update --init
$ pushd otp
$ ./configure --prefix $(pwd)/../otp-bin
$ make -j$(nproc)
$ make -j$(nproc) install
$ popd
```
**Note:** on Mac you may need to provide a custom installation path for OpenSSl. Just replace the above configuration step with:
```
$ ./configure --prefix $(pwd)/../otp-bin --with-ssl=$(brew --prefix openssl)
```
Then simply add the installation dir to your'$PATH':
```
$ export PATH=$(pwd)/otp-bin/bin:$PATH

```
Verify the Erland installation:
```
$ which erl # Should point to the newly built version of Erlang/OTP

```
You will also need a version of rebar3 built with Erlang/OTP 26 or higher. You can find instructions on how to build rebar3 from source [here](https://rebar3.org/docs/getting-started/#installing-from-source).




Download
--------
You can either download a pre-built version of the EDB debugger or build it from source.

You can visit the [Releases](https://github.com/WhatsApp/edb/releases) page for EDB and download a pre-built version of EDB.

You can also download an EDB version for a specific commit by visiting the [Commits History page](https://github.com/WhatsApp/edb/commits/main/), click on the "green tick" next to a given commit, click on "details" for the CI job, check the "Summary". You will find the pre-built versions among the "artifacts" for the commit.


Usage
-----

**Start the DAP adapter for 'edb'**
```
$ _build/default/bin/edb dap

```
This is the command that you tipically want your IDE (VS Code, Emacs) to trigger.

Contributing
------------

We welcome contributions from the community! Please see our [Contribution Guidelines](https://github.com/WhatsApp/edb/blob/10e839183fc719ead600525c94f1089587bba69a/.github/CONTRIBUTING.md) for more information on how to get involved.

License
-------

EDB is Apache 2.0 licensed, as found in the [LICENSE.md](./LICENSE.md) file.
