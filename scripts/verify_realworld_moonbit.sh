#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

github_root="$(cd "$repo_root/../.." && pwd)"
packages=(
  "mizchi/ripple"
  "mizchi/semver"
  "mizchi/tempfile"
)

checked=0

package_checkout_exists() {
  local package_name="$1"
  [ -d "$github_root/$package_name" ] || [ -d "$github_root/${package_name}.mbt" ]
}

verify_package() {
  local package_name="$1"
  local safe_name="${package_name//\//__}"
  local out="_build/realworld-moonbit/$safe_name"

  if ! package_checkout_exists "$package_name"; then
    echo "skip $package_name: checkout not found under $github_root" >&2
    return
  fi

  rm -rf "$out"
  moon run src -- --input "$package_name" --out "$out" >/dev/null

  [ -f "$out/package.json" ]
  [ -f "$out/index.d.ts" ]
  [ -f "$out/index.js" ]
  [ -f "$out/index.js.map" ]
  [ -f "$out/AUTOLINK_DIAGNOSTICS.md" ]
  [ ! -f "$out/moon.pkg.json" ]
  [ ! -f "$out/AUTOLINK_FACADE.mbt" ]
  grep -F '"type": "module"' "$out/package.json" >/dev/null
  node --input-type=module -e "await import('./$out/index.js')"

  checked=$((checked + 1))
}

for package_name in "${packages[@]}"; do
  verify_package "$package_name"
done

if [ "$checked" -eq 0 ]; then
  echo "skip real-world MoonBit probe: no target checkouts found" >&2
fi
