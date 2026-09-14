#!/usr/bin/env bash
# Build the pinned upstream artifact this package points at.
#
# Runs ONLY off the install target (locally or in CI, see
# .github/workflows/build.yml) — native NostrHost packages never execute a
# build on the host they install to (see docs/security-model.md). The output
# is a single tarball plus its SHA-256, which then get copied into
# package.toml's [source.main].
#
# Required environment:
#   UPSTREAM_REPO      git URL of the upstream project
#   UPSTREAM_REF       pinned tag or commit to build (never a branch)
#   PACKAGE_ID         matches package.toml's [app].id, used to name the artifact
#
# Optional environment (defaults shown):
#   PACKAGE_MANAGER    npm
#   INSTALL_ARGS       "ci --ignore-scripts"
#   BUILD_ARGS         "run build"
#   BUILD_ENV          space-separated KEY=VALUE pairs exported for the build
#                       command only (e.g. Vite VITE_* config)
#   OUTPUT_DIR         "dist"   (relative to the checked-out repo)
#   OUT                "."      (where to write the artifact + its sha256)
set -euo pipefail

: "${UPSTREAM_REPO:?set UPSTREAM_REPO}"
: "${UPSTREAM_REF:?set UPSTREAM_REF}"
: "${PACKAGE_ID:?set PACKAGE_ID}"

PACKAGE_MANAGER="${PACKAGE_MANAGER:-npm}"
INSTALL_ARGS="${INSTALL_ARGS:-ci --ignore-scripts}"
BUILD_ARGS="${BUILD_ARGS:-run build}"
BUILD_ENV="${BUILD_ENV:-}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
OUT="${OUT:-.}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> Cloning ${UPSTREAM_REPO}@${UPSTREAM_REF}"
# UPSTREAM_REF may be a tag or a bare commit hash (some upstreams don't tag
# releases). `--branch` only accepts a ref name, not an arbitrary commit, so
# try the fast path first and fall back to a full clone + checkout.
if ! git clone --quiet --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" "$workdir/src" 2>/dev/null; then
    git clone --quiet "$UPSTREAM_REPO" "$workdir/src"
    git -C "$workdir/src" checkout --quiet "$UPSTREAM_REF"
fi

pushd "$workdir/src" >/dev/null

echo "==> Installing dependencies (${PACKAGE_MANAGER} ${INSTALL_ARGS})"
# shellcheck disable=SC2086
"$PACKAGE_MANAGER" $INSTALL_ARGS

echo "==> Building (${PACKAGE_MANAGER} ${BUILD_ARGS})"
# shellcheck disable=SC2086
env $BUILD_ENV "$PACKAGE_MANAGER" $BUILD_ARGS

if [ ! -d "$OUTPUT_DIR" ] || [ -z "$(ls -A "$OUTPUT_DIR")" ]; then
    echo "build.sh: build did not produce non-empty output at ${OUTPUT_DIR}" >&2
    exit 1
fi

popd >/dev/null

version="${UPSTREAM_REF#v}"
artifact="${PACKAGE_ID}-v${version}.tar.gz"

echo "==> Packaging ${artifact}"
tar -C "$workdir/src/$OUTPUT_DIR" -czf "$OUT/$artifact" .

sha256="$(sha256sum "$OUT/$artifact" | cut -d' ' -f1)"
echo "==> Built $OUT/$artifact"
echo "    sha256: $sha256"

# Machine-readable summary for the calling workflow.
{
    echo "artifact=$artifact"
    echo "sha256=$sha256"
    echo "version=$version"
} > "$OUT/build-result.env"
