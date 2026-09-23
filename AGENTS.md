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

7. **Package it as a signed `.npk` and install/upgrade with
   [npack](https://github.com/imattau/npack).** NostrHost no longer installs
   a package by pointing the engine straight at `package.toml` on disk
   (`nostrhost app install --source` was retired); it installs a signed
   `.npk` instead. npack signs/transports the manifest declaration, not the
   payload bytes, so `[source.main]`'s own fetch from step 5 keeps working
   unchanged:

   ```sh
   nostrhost-package build-npk package.toml \
     --output my-app-0.1.0.npk \
     --publisher <npub-or-hex>
   nostrhost app install-npk ./my-app-0.1.0.npk --domain example.com
   ```

   No `--payload` flag needed. If `[app].version` isn't SemVer, pass
   `--version` explicitly. Optionally add `--repo 30617:<pubkey>:<identifier>`
   (NIP-34, not a plain URL — see
   [npack#16](https://github.com/imattau/npack/issues/16)) and `--commit
   <hex>` if this release should be eligible for CI-attestation trust
   policies. Any syntactically valid `--publisher` works for local
   iteration (the `.npk` never has to be published anywhere); for a real
   release, either attach it to this repo's GitHub Release the same way
   `[source.main]`'s tarball already is, or `npack publish` it to relays
   under a real publisher key.

8. **Shipping a later upstream version:** repeat steps 4–7 with the new
   ref (new build, new `.npk` — keep `--publisher` the same key across
   versions so an upgrade resolves as the same app). Nothing else changes
   unless upstream's build process itself changed (new build command, new
   output directory, new required env var) — in which case update step 2's
   env block first.

## Install-time domain/path

`[web].domain` is intentionally absent from `package.toml` — it's an
install-time parameter, not part of the package's signed content, supplied
on `install-npk`/`upgrade-npk` (step 7 above):

```sh
nostrhost app install-npk ./my-app-0.1.0.npk --domain example.com [--path /app/]
```

`nostrhost app upgrade-npk` defaults `--domain`/`--path` to whatever is
*currently installed* rather than re-reading `package.toml`'s own values,
so a routine upgrade never silently moves a live app back to a placeholder.
A deliberate move uses `nostrhost app change-url <id> --domain … --path …`.

## If the app returns a bare "nostrhost domain ..." stub after install

That means Caddy lost the route, not that the package is broken. Native app
web routes exist only in Caddy's admin-API-pushed runtime config, never on
disk — so **any** Caddy restart (a package upgrade that ships
`caddy.service` and gets restarted by debhelper, a manual `systemctl
restart caddy`, a crash-restart, a reboot) or **any** Caddy reload (`caddy
reload --config X` fully replaces the active config, same as a restart —
regenconf's `15-caddy` hook runs this on any base-Caddyfile change) drops
every installed native app back to the bare per-domain stub until
something replays its route.

`nostrhost-yunohost` `12.1.41.47`+ fixes the restart case
(`nostrhost-web-reconcile.service`, triggered by `caddy.service`'s own
`Wants=`) and `12.1.41.49`+ also fixes the reload case (`15-caddy`'s
`do_post_regen` triggers the same reconcile job after its `caddy reload`).
On an older core build, or if it's still happening after `12.1.41.49`,
recover with:

```sh
nostrhost app reconcile-routes --output-as json
```

which re-applies every installed native app's route (best-effort,
per-app — idempotent, safe to run any time, not just after an incident).

## Behavior note: build-time config vs. install-time config

A classic `_ynh` package (`scripts/install`) can inject an admin's
install-time answers as build env vars. This scriptless format can't — every
install of a given package *version* gets the same build output. Anything
env-dependent must be fixed in `build.yml`'s `BUILD_ENV` at build time. If an
app genuinely needs per-install configuration, NostrHost has two resources
for it, for two different moments:

- **Pre-install** (needed to plan resources correctly, before anything is
  applied — an API key, a tier selection): `[install_inputs.*]` in
  `package.toml`, supplied with `--set id=value` on
  `install-npk`/`upgrade-npk` (`--domain`/`--path` above are sugar for this
  same mechanism's built-in `web.domain`/`web.path` bind targets).
- **Post-install** (changeable later from the app's config panel):
  `package.toml`'s `[settings]` resource, rendered into a managed
  `[config]` file at apply time.

Neither is something to fake by baking a default into the build and calling
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
  install (`[install_inputs]`) versus per build versus after install
  (`[settings]`) — see the behavior note above.
