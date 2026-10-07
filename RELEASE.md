# Cutting an `edb` release

Releases are versioned `X.Y.Z` (no `v` prefix).
Each release bundles two escripts built from two branches:

- `otp-28/edb`, built from the `otp-28.0` branch with OTP 28, and
- `otp-29/edb`, built from `main` with OTP 29,

plus the `edb` launcher (`scripts/edb`) that dispatches on the installed
OTP version (28 goes to the OTP 28 escript, 29 and later to the OTP 29
escript, anything older is a hard error).

## Process

1. Decide the version (e.g. `1.0.0`).
2. Tag both branches:
   ```
   $ git tag 1.0.0 origin/main
   $ git tag 1.0.0-otp28 origin/otp-28.0
   ```
3. Push both tags:
   ```
   $ git push origin 1.0.0 1.0.0-otp28
   ```
   Pushing the `-otp28` tag triggers nothing; pushing the main tag starts
   the `Release` workflow.
4. Watch the `Release` workflow run in the Actions tab. When it succeeds,
   the release appears on the Releases page with the `edb-<version>.tar.gz`
   asset attached and auto-generated notes.

The workflow fails fast if the `<version>-otp28` tag is missing, so the two
tags above are both required.

## What the workflow does

- `resolve`: derives `<version>-otp28` from the pushed tag and verifies
  both refs exist.
- `build-otp28` / `build-otp29`: check out each ref and run
  `rebar3 escriptize` under OTP 28.0 / 29.0 respectively.
- `assemble`: stages `edb`, `otp-28/edb` and `otp-29/edb` into
  `edb-<version>/`, and tars it up.
- `smoke`: on OTP 28 and 29 runners, checks the launcher selects the right
  escript and that the selected escript boots (it must print argparse
  `Usage:` text; a bytecode/OTP mismatch would crash the loader instead).
- `publish` (tag pushes only): creates the GitHub Release with the tarball.

## Dry runs (no tag push, no release created)

Run the `Release` workflow manually from the Actions tab
(`workflow_dispatch`) on any branch, with inputs `version` (e.g.
`0.0.0-dryrun1`), `main_ref` and `otp28_ref`. It runs everything except
`publish`; the tarball is left as a workflow artifact on the run for
download and inspection. The single thing this does not exercise is
`gh release create` itself; for a full end-to-end, push the branch plus
throwaway tags to a personal fork and check the fork's releases page.

## Re-cutting a version

`gh release create` refuses to overwrite an existing release. To re-cut,
delete the release (Releases page or `gh release delete <tag>`) and both
tags (`git push --delete origin <tag> && git tag -d <tag>`), then start over.
