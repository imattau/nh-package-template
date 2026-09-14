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

## 6. Shipping a new upstream version later

Repeat steps 4-5 with the new upstream tag. Nothing else in the repo needs
to change unless upstream's build process itself changed (new build
command, new output directory, new required env var).

## Install-time domain/path

`[web].domain` is deliberately absent from `package.toml`: it's an
install-time parameter (which host this goes on), not part of the package's
own signed content, so it's supplied at install time instead of hardcoded
into the manifest:

```sh
nostrhost app install <id> --source . --domain example.com
# path defaults to package.toml's [web].path; override it too if needed:
nostrhost app install <id> --source . --domain example.com --path /app/
```

`nostrhost app upgrade` defaults `--domain`/`--path` to whatever is
*currently installed*, not to `package.toml`'s own values, so a routine
upgrade never silently moves a live app. To deliberately move an already
-installed app, use `nostrhost app change-url <id> --domain … --path …`
instead of passing `--domain`/`--path` on an upgrade.

(This requires a `nostrhost-yunohost` build that includes the
`--domain`/`--path` install/upgrade flags — commit `f82a4d5e3` or later on
the `nostrhost` branch. An older build has no way to supply a domain at
all, which was the actual gap this fixed.)

## Behavior note: build-time config vs. install-time config

A `_ynh` package that runs `npm run build` at install time can inject
install-time admin answers as build env vars (see e.g. `armada_ynh`'s
`VITE_APP_RELAYS` etc., set from a YunoHost install question). A `_nh`
package built from this template can't do that — anything env-dependent is
fixed at `build.yml` time via `BUILD_ENV`, the same for every install of
this package version. If an app needs genuinely per-install configuration,
that belongs in NostrHost's `[settings]` resource (rendered into a managed
`[config]` file at apply time), not baked into the build.
