#!/usr/bin/env bash
# Work around the bleeding-edge MoonBit toolchain (CI installs `latest`, the
# only stable URL on cli.moonbitlang.com) hard-erroring on
# moonbitlang/async's deprecated in-struct `fn new(..)` constructor
# signatures. The dependency's toplevel `Type::new` implementations already
# exist, so the in-struct signatures are redundant.
#
# We patch the *cached* dependency zip (so the fix propagates to the
# top-level build AND every scaffolded fixture, which all extract from the
# shared global registry cache) and sync the registry index checksum so moon
# accepts the patched zip instead of re-downloading the canonical one.
#
# Remove this once moonbitlang/async ships a release migrated to the new
# constructor syntax, or the MoonBit toolchain becomes pinnable.
set -euo pipefail

moon_home="${MOON_HOME:-$HOME/.moon}"
cache="$moon_home/registry/cache/moonbitlang/async"
idx="$moon_home/registry/index/user/moonbitlang/async.index"

# Ensure the async zip is present in the global cache.
moon install >/dev/null 2>&1 || true

if [ ! -d "$cache" ]; then
  echo "moonbitlang/async not cached at $cache; nothing to patch"
  exit 0
fi

patched_any=0
for z in "$cache"/*.zip; do
  [ -f "$z" ] || continue
  ver="$(basename "$z" .zip)"
  tmp="$(mktemp -d)"
  unzip -q "$z" -d "$tmp/ex"
  # Drop deprecated single-line in-struct `fn new(..) -> T` declarations.
  find "$tmp/ex" -name '*.mbt' ! -name '*.mbti' -print0 \
    | xargs -0 -r sed -i -E '/^[[:space:]]+fn(\[[^]]*\])? new\(.*\) -> /d'
  (cd "$tmp/ex" && zip -qr "$tmp/patched.zip" .)
  cp "$tmp/patched.zip" "$z"
  newsha="$(sha256sum "$z" | cut -d' ' -f1)"
  if [ -f "$idx" ]; then
    # Sync the checksum on this version's index line so moon trusts the
    # patched zip rather than re-fetching the canonical one.
    sed -i -E "/\"version\": ?\"${ver}\"/ s/(\"checksum\": ?\")[a-f0-9]+/\1${newsha}/" "$idx"
  fi
  rm -rf "$tmp"
  patched_any=1
  echo "patched cached moonbitlang/async@${ver} (checksum -> ${newsha})"
done

if [ "$patched_any" = "0" ]; then
  echo "no moonbitlang/async zip found in $cache"
  exit 0
fi

# Remove any already-extracted (unpatched) copies so they re-extract from the
# patched cache on the next build.
find . -type d -path '*/.mooncakes/moonbitlang/async' -exec rm -rf {} + 2>/dev/null || true
