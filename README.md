# NostrHost native (`_nh`) package template

Template repository for packaging a build-from-source static app (Vite,
webpack, etc.) as a scriptless native NostrHost package — the `_nh`
convention, e.g. [`opencode-web_nh`](https://github.com/imattau/nostrhost/tree/main/packages/opencode-web_nh),
as opposed to YunoHost's classic `_ynh` convention (`manifest.toml` +
imperative `scripts/install|upgrade|...`).

## Why this shape

NostrHost's native package engine is deliberately scriptless: it plans and
applies typed resources (`source`, `directories`, `web`, `permissions`,
`health`, `backup`, ...) from `package.toml`, and never executes an
arbitrary build command on the install target — see
[docs/security-model.md](docs/security-model.md). So a `_nh` package for an
app that needs `npm run build` can't do that build at install time the way
a `_ynh` package's `scripts/install` does; it has to point `[source.main]`
at an **already-built, SHA-256-pinned artifact**.

This repo is the reusable shape for producing and maintaining that artifact:

| File | Purpose |
|---|---|
| [`package.toml`](package.toml) | The native manifest. `[source.main]` points at this repo's own GitHub Release asset. |
| [`build.sh`](build.sh) | Clones the pinned upstream ref, builds it with a pinned toolchain, tars the output, prints its SHA-256. |
| [`.github/workflows/build.yml`](.github/workflows/build.yml) | Manual (`workflow_dispatch`) — runs `build.sh` and publishes the tarball as a GitHub Release asset. |
| [`.github/workflows/security.yml`](.github/workflows/security.yml) | Validates `package.toml` against the native schema, verifies the pinned artifact's hash, and runs the same static scans (Gitleaks, Trivy, actionlint, ShellCheck) as [nostr-yunohost](https://github.com/imattau/nostr-yunohost)'s `_ynh`-oriented `static-security.yml`. |
| [`AGENTS.md`](AGENTS.md) | The same walkthrough as `docs/new-package.md`, written for a coding agent working in a repo built from this template — leads with the hard execution boundary, ends with an explicit "don't" list. |

## Using this template for a new app

An AI coding agent working in a repo built from this template should read
[`AGENTS.md`](AGENTS.md) first. For a human, see
[docs/new-package.md](docs/new-package.md) for the full checklist. Short version:

1. Use this repo as a GitHub template (or copy it) into `<app>_nh`.
2. Fill in every `TODO` in `package.toml` and `.github/workflows/build.yml`
   (upstream repo URL, package id, path, build env vars). Leave
   `[web].domain` unset — it's supplied at install time (`nostrhost app
   install <id> --source . --domain <domain>`), not hardcoded here; see
   `docs/new-package.md`'s "Install-time domain/path".
3. Run `build.yml` with the pinned upstream tag you want to package.
4. Copy the printed release URL + SHA-256 into `package.toml`'s
   `[source.main]`, bump `[app].version` to match, commit, open a PR.
5. `security.yml` runs on the PR and must pass before merging.
6. To ship a new upstream version later: repeat from step 3 with the new tag.

## What this does *not* do

This template does not publish to the [nostr-yunohost](https://github.com/imattau/nostr-yunohost)
catalog — that publisher (`nostr-ynh publish`) only reads classic `manifest.toml`
`_ynh` packages today. A `_nh` package built from this template is installed
by pointing NostrHost's native package engine directly at this repo's
`package.toml` (`nostrhost package plan` / `nostrhost package reconcile`),
not through the Nostr-signed `_ynh` catalog.
