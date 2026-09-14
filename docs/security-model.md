# Why native packages ship pre-built artifacts

NostrHost's native package engine
([`package_engine.py`](https://github.com/imattau/nostrhost-yunohost/blob/nostrhost/src/nostrhost/package_engine.py),
[`native_providers.py`](https://github.com/imattau/nostrhost-yunohost/blob/nostrhost/src/nostrhost/native_providers.py))
validates and applies typed resources from `package.toml`. Two providers make
the "no arbitrary execution on the install target" boundary explicit:

- `RuntimeProvider` only verifies a requested language runtime is present at
  the right version; its docstring: "Installation is intentionally not
  hidden behind a provider... Runtime packages are selected by the host
  policy (usually an apt resource)."
- `HookProvider` only registers a restricted `python: module:function`
  reference; its docstring: "Register restricted Python hook references
  **without executing them**."

There is no `build` resource and no shell-script escape hatch — deliberately,
per NostrHost's package-authoring rules ("If a capability cannot be
expressed, propose a typed resource/provider or a narrowly scoped Python
hook with a declared contract. Do not add an unreviewed shell-script escape
hatch.").

For an app whose upstream ships source that needs `npm run build` (or
equivalent), that means the build **cannot** happen as part of installing
the package — it has to happen somewhere off the install target, before the
package is ever applied, producing a static artifact that `[source.main]`
then points at with a mandatory SHA-256.

`build.sh` / `build.yml` in this template are that off-host build step. They
run in CI (or locally), never on a NostrHost install target, and their only
output that matters to the package engine is a hash-pinned URL.
