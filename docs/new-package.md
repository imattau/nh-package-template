# Turning this template into a real `_nh` package

## 1. Create the repo

Use this repo as a GitHub template, or copy its files, into a new repo named
`<app>_nh` (matching the `_nh` / `_ynh` naming convention — e.g. `ditto_nh`).

## 2. Fill in `package.toml`

Replace every `TODO`:

- `[app].id` / `[app].version`
- `[source.main]` — leave the URL/sha256 as placeholders for now; step 4 fills
  these in for real once a build exists.
- `[directories.install].path`, `[web].path`, `[web].file_root`,
  `[permissions.main]`, `[health].path` — all keyed off the app id; keep them
  consistent.
- `[backup].paths` — only add paths if the app writes runtime data outside
  the install dir (most static SPAs don't).

Leave `[web]` with **no `domain` key** — see "Install-time domain/path"
below for why that's deliberate, not an oversight.

Validate the shape before touching CI:

```sh
git clone --branch nostrhost https://github.com/imattau/nostrhost-yunohost .nostrhost-yunohost
python -m pip install "typer==0.7.0" "click==8.1.7" "pydantic==1.10.14" "PyYAML==6.0.2"
PYTHONPATH=.nostrhost-yunohost/src python -m nostrhost.package_authoring validate package.toml --json
```

## 3. Fill in `build.yml` and check `build.sh`'s defaults

In `.github/workflows/build.yml`, set:

- `UPSTREAM_REPO` — the upstream project's git URL
- `PACKAGE_ID` — matches `package.toml`'s `[app].id`
- `NODE_VERSION` — match what upstream's CI/package.json engines field expects
- `OUTPUT_DIR` — upstream's build output directory (`dist` for most Vite apps)
- `BUILD_ENV` — any build-time env vars upstream's build needs (e.g. Vite
  `VITE_*` config). These get baked into the artifact — see the note below
  about behavior that changes versus a `_ynh` package.

If upstream doesn't use `npm`, or uses non-default install/build commands,
also pass `PACKAGE_MANAGER`, `INSTALL_ARGS`, `BUILD_ARGS` through as
`build.sh` env (add them next to `BUILD_ENV` in `build.yml`'s env block).

## 4. Run the build

Actions tab → "Build and publish artifact" → Run workflow, with the pinned
upstream tag you want to package as `upstream_ref` (a real tag/commit, never
a branch). This produces a GitHub Release with the tarball attached and
prints the SHA-256 in the job summary.

## 5. Wire the artifact into `package.toml`

Copy the release asset URL and the printed SHA-256 into `[source.main]`.
Bump `[app].version` to match. Commit, push, open a PR — `security.yml` runs
automatically and must pass (schema validation, plan, artifact hash
re-verification, Gitleaks, Trivy, actionlint, ShellCheck).

## 6. Package and install/upgrade with npack

NostrHost no longer installs a native package by pointing the engine
straight at a `package.toml` on disk — that path (`nostrhost app install
--source`) was retired in favor of [npack](https://github.com/imattau/npack)
distribution, which this template already fits naturally: npack signs and
transports the *manifest declaration*, not the payload bytes, so
`[source.main]`'s own URL+SHA-256 fetch (step 5) keeps working unchanged at
install time — nothing about this template's build/release shape needs to
change for npack.

Wrap the manifest into a signed `.npk` (this is npack's own binary, not
part of this repo — `cargo install` it or grab a release from
[imattau/npack](https://github.com/imattau/npack)):

```sh
nostrhost-package build-npk package.toml \
  --output my-app-0.1.0.npk \
  --publisher <npub-or-hex>
```

No `--payload` is needed — `[source.main]` does the real fetch at apply
time, the same as it always has. If `[app].version` doesn't parse as
SemVer, pass `--version` explicitly (npack requires SemVer for the release
version even though `package.toml`'s own version string can carry other
conventions). Add `--repo 30617:<pubkey>:<identifier>` (a
[NIP-34](https://github.com/nostr-protocol/nips/blob/master/34.md)
repository address — **not** a plain URL, see
[npack#16](https://github.com/imattau/npack/issues/16)) and `--commit
<hex>` if you want this release to be eligible for CI-attestation trust
policies later; both are optional and have no effect on installation
otherwise.

For local iteration, any syntactically valid `--publisher` works and the
`.npk` never needs to be published anywhere — install it straight from
disk:

```sh
nostrhost app install-npk ./my-app-0.1.0.npk --domain example.com
# path defaults to package.toml's [web].path; override it too if needed:
nostrhost app install-npk ./my-app-0.1.0.npk --domain example.com --path /app/
```

For a real distributed release, either attach the `.npk` to this repo's
GitHub Release the same way `[source.main]`'s tarball already is (and have
installers download + `install-npk` it locally, no Nostr publishing
required), or `npack publish` it to relays under a real publisher key so it
resolves as `<publisher>/<name>[@version]` — see npack's own
[Publishing a release](https://github.com/imattau/npack/blob/master/docs/using-npack.md#publishing-a-release)
docs.

## 7. Shipping a new upstream version later

Repeat steps 4-6 with the new upstream tag: new build, new `.npk`
(`--publisher` should stay the same key across versions so an upgrade
resolves as the same app). Nothing else in the repo needs to change unless
upstream's build process itself changed (new build command, new output
directory, new required env var).

## Install-time domain/path

`[web].domain` is deliberately absent from `package.toml`: it's an
install-time parameter (which host this goes on), not part of the package's
own signed content, so it's supplied at install time instead of hardcoded
into the manifest — see step 6 above for the full `install-npk` command.

`nostrhost app upgrade-npk` defaults `--domain`/`--path` to whatever is
*currently installed*, not to `package.toml`'s own values, so a routine
upgrade never silently moves a live app:

```sh
nostrhost app upgrade-npk ./my-app-0.2.0.npk
```

To deliberately move an already-installed app, use `nostrhost app
change-url <id> --domain … --path …` instead of passing `--domain`/`--path`
on an upgrade.

## Behavior note: build-time config vs. install-time config

A `_ynh` package that runs `npm run build` at install time can inject
install-time admin answers as build env vars (see e.g. `armada_ynh`'s
`VITE_APP_RELAYS` etc., set from a YunoHost install question). A `_nh`
package built from this template can't do that — anything env-dependent is
fixed at `build.yml` time via `BUILD_ENV`, the same for every install of
this package version. If an app needs genuinely per-install configuration,
NostrHost has two resources for it, for two different moments:

- **Pre-install** (a value needed to plan the resources correctly, before
  anything is applied — an API key, a tier selection): `[install_inputs.*]`,
  declared in `package.toml` and supplied with `--set id=value` on
  `install-npk`/`upgrade-npk` (`--domain`/`--path` are sugar for the built-in
  `web.domain`/`web.path` bind targets of this same mechanism).
- **Post-install** (a value the admin can change later from the app's
  config panel): `[settings]`, rendered into a managed `[config]` file at
  apply time.

Neither is something to fake by baking a default into the build and calling
it done.
