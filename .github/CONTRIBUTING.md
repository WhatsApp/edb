# Contributing to whatsapp/edb
We want to make contributing to this project as easy and transparent as
possible.

## Our Development Process

## Pull Requests
We actively welcome your pull requests.

1. Fork the repo and create your branch from `main`.
2. Add tests for your code using [Common Test](https://erlang.org/doc/apps/common_test/basics_chapter.html).
3. If you've changed APIs, update the documentation.
4. Ensure the test suite passes by running `rebar3 ct`.
5. Validate your code by running `rebar3 dialyzer xref`.
6. Format your code automatically by running `rebar3 fmt`.
6. If you haven't already, complete the Contributor License Agreement ("CLA").

## Contributor License Agreement ("CLA")
In order to accept your pull request, we need you to submit a CLA. You only need
to do this once to work on any of Meta's open source projects.

Complete your CLA here: <https://code.facebook.com/cla>

## Issues
We use GitHub issues to track public bugs. Please ensure your description is
clear and has sufficient instructions to be able to reproduce the issue.

Meta has a [bounty program](https://bugbounty.meta.com/) for the safe
disclosure of security bugs. In those cases, please go through the process
outlined on that page and do not file a public issue.

## Coding Style
Run `rebar3 fmt` to auto-format your code.

## License
By contributing to whatsapp/edb, you agree that your contributions will be
licensed under the LICENSE file in the root directory of this source tree.
