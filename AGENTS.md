# Agent guidance for this repo

This is a native NostrHost (`_nh`) package repo, scaffolded from
[imattau/nh-package-template](https://github.com/imattau/nh-package-template).
Read this before editing `package.toml` or the workflows.

## The one hard rule

**Never add anything that executes a command on the NostrHost install
target.** No `scripts/install`, no shell snippet in a `[hooks]` entry, no
`postinst`-style trick. `package.toml` is validated and applied by a
declarative resource engine, and two of its providers make this boundary
explicit in their own source:

- `RuntimeProvider` only checks a runtime version is present — it does not
  install or run anything.
- `HookProvider` only registers a `python: module:function` reference — its
  docstring says "without executing them."

If an app needs `npm run build` (or equivalent) to produce its static
output, that build has to happen **before** the package is ever applied —
in this repo's own CI, or locally — never as part of install. See
[docs/security-model.md](docs/security-model.md) for the full reasoning and
source citations.

Concretely: `package.toml`'s `[source.main]` must point at an **already
built** artifact (this repo's own GitHub Release asset, produced by
`build.sh`), never at the upstream project's own source tarball.

## Authoring loop

1. **Fill in `package.toml`.** Replace every `TODO`: `[app].id`/`version`,
   `[directories.install].path`, `[web].path`/`file_root`,
   `[permissions.main]`, `[health].path`. Keep them consistent (same app id
   threaded through every path). Leave `[source.main]`'s url/sha256 as
   placeholders until step 4 — they get real values only after a real build.
   Do **not** add a `[web].domain` key — see "Install-time domain/path"
   below.

2. **Fill in `.github/workflows/build.yml`'s `env:` block:**
   `UPSTREAM_REPO` (git URL), `PACKAGE_ID` (matches `[app].id`),
   `NODE_VERSION`, `OUTPUT_DIR` (upstream's build output dir, usually
   `dist`), and `BUILD_ENV` (space-separated `KEY=VALUE` build-time env
   upstream's build needs, e.g. Vite `VITE_*` config — see the "behavior
   note" below). If upstream doesn't use plain `npm ci`/`npm run build`,
   also pass `PACKAGE_MANAGER`/`INSTALL_ARGS`/`BUILD_ARGS` through as env
   next to `BUILD_ENV`.

3. **Validate before touching CI.** From this repo's root:

   ```sh
   git clone --branch nostrhost https://github.com/imattau/nostrhost-yunohost .nostrhost-yunohost
   python -m pip install "typer==0.7.0" "click==8.1.7" "pydantic==1.10.14" "PyYAML==6.0.2"
   PYTHONPATH=.nostrhost-yunohost/src python -m nostrhost.package_authoring validate package.toml --json
   PYTHONPATH=.nostrhost-yunohost/src python -m nostrhost.package_authoring plan package.toml --json
   ```

   `validate` checks TOML syntax and typed-resource rules; `plan` additionally
   produces the deterministic operation list the package engine would apply.
   Fix every diagnostic before moving on — don't hand-wave a "should be fine."

4. **Run the build.** Actions tab → "Build and publish artifact" → Run
   workflow, with `upstream_ref` set to a **pinned tag or commit** (never a
   branch — some upstreams, e.g. Armada, don't tag releases and pin a bare
   commit hash instead; `build.sh` handles both). This publishes a GitHub
   Release with the tarball attached and prints its SHA-256 in the job
   summary.

5. **Wire the real artifact into `package.toml`.** Copy the release asset
   URL and the printed SHA-256 into `[source.main]`. Bump `[app].version` to
   match. Commit, push, open a PR.

6. **`security.yml` runs on the PR and must pass.** It re-runs
   `validate`/`plan`, re-fetches the URL in `[source.main]` and confirms it
   still hashes to the declared `sha256`, and runs Gitleaks, Trivy,
   actionlint, and ShellCheck (on `build.sh`). A failure here is a real
   defect, not noise to route around — don't add `continue-on-error` or
   weaken a check to make it pass.

7. **Shipping a later upstream version:** repeat steps 4–5 with the new
   ref. Nothing else changes unless upstream's build process itself changed
   (new build command, new output directory, new required env var) — in
   which case update step 2's env block first.

## Install-time domain/path

`[web].domain` is intentionally absent from `package.toml` — it's an
install-time parameter, not part of the package's signed content:

```sh
nostrhost app install <id> --source . --domain example.com [--path /app/]
```

`nostrhost app upgrade` defaults `--domain`/`--path` to whatever is
*currently installed* rather than re-reading `package.toml`'s own values,
so a routine upgrade never silently moves a live app back to a placeholder.
A deliberate move uses `nostrhost app change-url <id> --domain … --path …`.
This needs a `nostrhost-yunohost` build at commit `f82a4d5e3` or later on
the `nostrhost` branch — an older CLI has no `--domain`/`--path` flags at
all.

## Behavior note: build-time config vs. install-time config

A classic `_ynh` package (`scripts/install`) can inject an admin's
install-time answers as build env vars. This scriptless format can't — every
install of a given package *version* gets the same build output. Anything
env-dependent must be fixed in `build.yml`'s `BUILD_ENV` at build time. If an
app genuinely needs per-install configuration, that's `package.toml`'s
`[settings]` resource (rendered into a managed `[config]` file at apply
time) — not something to fake by baking a default into the build and calling
it done.

## Don't

- Don't invent a SHA-256, a URL, or a version number. If you don't have a
  real build to hash, leave the placeholder and say so.
- Don't add `[hooks]` as a way to sneak in imperative behavior — see "the
  one hard rule" above.
- Don't skip `security.yml`'s hash-verification step or point `[source.main]`
  at a mutable URL (a branch tarball, a "latest" redirect, etc.).
- Don't hardcode a `[web].domain` in `package.toml` — it's supplied via
  `--domain` at install time (see "Install-time domain/path" above), not a
  manifest field.
- Don't copy other `_ynh`-style install-time settings (admin questions
  beyond domain/path) into `package.toml` as `[settings]` fields without
  checking whether the underlying value is actually meant to vary per
  install versus per build — see the behavior note above.
