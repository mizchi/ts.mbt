#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

github_root="$(cd "$repo_root/../.." && pwd)"
packages=(
  "mizchi/ast_printer"
  "mizchi/js"
  "mizchi/jsonschema"
  "mizchi/markdown"
  "mizchi/nom"
  "mizchi/pixelmatch"
  "mizchi/ripple"
  "mizchi/semver"
  "mizchi/syntree"
  "mizchi/tempfile"
  "mizchi/tui"
  "mizchi/vfs"
  "mizchi/jwt.mbt"
)

checked=0

package_checkout_exists() {
  local package_name="$1"
  if [ -d "$github_root/$package_name" ] || [ -d "$github_root/${package_name}.mbt" ]; then
    return 0
  fi
  local owner="${package_name%%/*}"
  if [ "$owner" = "$package_name" ] || [ ! -d "$github_root/$owner" ]; then
    return 1
  fi
  local moon_mod
  for moon_mod in "$github_root/$owner"/*/moon.mod.json; do
    [ -f "$moon_mod" ] || continue
    if grep -F "\"name\": \"$package_name\"" "$moon_mod" >/dev/null; then
      return 0
    fi
  done
  return 1
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
  verify_typescript_declarations "$out"

  checked=$((checked + 1))
}

verify_typescript_declarations() {
  local out="$1"
  local typecheck_dir="$out/_typecheck"

  rm -rf "$typecheck_dir"
  mkdir -p "$typecheck_dir"

  node --input-type=module - "$out" "$typecheck_dir" <<'EOF'
import fs from "node:fs";
import path from "node:path";

const out = process.argv[2];
const typecheckDir = process.argv[3];

function walk(dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "_typecheck") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, acc);
    } else if (entry.isFile() && entry.name.endsWith(".d.ts")) {
      acc.push(full);
    }
  }
  return acc;
}

const declarationFiles = walk(out);
const imports = new Map();

for (const file of declarationFiles) {
  const source = fs.readFileSync(file, "utf8");
  const importRe = /import\s+type\s+\*\s+as\s+([A-Za-z_$][\w$]*)\s+from\s+"([^"]+)";/g;
  for (const match of source.matchAll(importRe)) {
    const [, alias, spec] = match;
    if (spec.startsWith(".")) continue;
    const names = imports.get(spec) ?? new Set();
    const escaped = alias.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const usageRe = new RegExp(`\\b${escaped}\\.([A-Za-z_$][\\w$]*)`, "g");
    for (const usage of source.matchAll(usageRe)) {
      names.add(usage[1]);
    }
    imports.set(spec, names);
  }
}

const paths = {};
for (const [spec, names] of imports) {
  const stubPath = path.join(typecheckDir, "stubs", ...spec.split("/"), "index.d.ts");
  fs.mkdirSync(path.dirname(stubPath), { recursive: true });
  const body = [...names].sort().map((name) => {
    return `export interface ${name}<T0 = unknown, T1 = unknown, T2 = unknown, T3 = unknown> {}\n`;
  }).join("");
  fs.writeFileSync(stubPath, body || "export {};\n");
  paths[spec] = [path.relative(typecheckDir, stubPath)];
}

const config = {
  compilerOptions: {
    strict: true,
    noEmit: true,
    module: "esnext",
    moduleResolution: "bundler",
    target: "es2020",
    baseUrl: ".",
    lib: ["es2020"],
    paths,
  },
  files: declarationFiles.map((file) => path.relative(typecheckDir, file)),
};

fs.writeFileSync(path.join(typecheckDir, "tsconfig.json"), JSON.stringify(config, null, 2));
EOF

  pnpm exec tsc -p "$typecheck_dir/tsconfig.json" --pretty false
}

for package_name in "${packages[@]}"; do
  verify_package "$package_name"
done

if [ "$checked" -eq 0 ]; then
  echo "skip real-world MoonBit probe: no target checkouts found" >&2
fi
