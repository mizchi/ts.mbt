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

known_skip_reason() {
  local package_name="$1"
  case "$package_name" in
    "mizchi/tui")
      echo "local checkout has an unresolved MoonBit module import for mizchi/crater/layout/node"
      ;;
  esac
}

verify_package() {
  local package_name="$1"
  local safe_name="${package_name//\//__}"
  local out="_build/realworld-moonbit/$safe_name"

  local skip_reason
  skip_reason="$(known_skip_reason "$package_name")"
  if [ -n "$skip_reason" ]; then
    echo "skip $package_name: $skip_reason" >&2
    return
  fi

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
  verify_runtime_smoke "$package_name" "$out"
  verify_typescript_declarations "$out"
  verify_runtime_declaration_exports "$out"
  verify_package_consumer "$package_name" "$out"

  checked=$((checked + 1))
}

verify_runtime_smoke() {
  local package_name="$1"
  local out="$2"

  case "$package_name" in
    "mizchi/js")
      node --input-type=module - "$out" <<'EOF'
import path from "node:path";
import { pathToFileURL } from "node:url";

const out = process.argv[2];
const mod = await import(pathToFileURL(path.resolve(out, "index.js")).href);
const value = mod.undefined_();
const valueType = mod.typeof_(value);
if (valueType !== "undefined") {
  throw new Error(`expected typeof undefined to be undefined, got ${valueType}`);
}
const object = mod.new_object();
if (object === null || typeof object !== "object" || Array.isArray(object)) {
  throw new Error("expected new_object to return a plain object-like value");
}
EOF
      ;;
    "mizchi/jsonschema")
      node --input-type=module - "$out" <<'EOF'
import path from "node:path";
import { pathToFileURL } from "node:url";

const out = process.argv[2];
const mod = await import(pathToFileURL(path.resolve(out, "index.js")).href);

const builder = mod.builder_new();
const stringSchema = mod.builder_string(builder, 2, 8, ["id", "name"]);
const integerSchema = mod.builder_integer(builder, 1, 10, undefined, undefined);
const arraySchema = mod.builder_array(
  builder,
  stringSchema,
  undefined,
  undefined,
  undefined,
  undefined,
  1,
  3,
);
const objectSchema = mod.builder_object(
  builder,
  new Map([
    ["name", stringSchema],
    ["age", integerSchema],
    ["tags", arraySchema],
  ]),
  ["name"],
  undefined,
  false,
);

for (const [name, value] of [
  ["stringSchema", stringSchema],
  ["integerSchema", integerSchema],
  ["arraySchema", arraySchema],
  ["objectSchema", objectSchema],
]) {
  if (value === null || typeof value !== "object") {
    throw new Error(`${name} did not return a schema object`);
  }
}

const refs = mod.collect_refs({ "$ref": "#/$defs/User" });
if (refs === null || typeof refs !== "object") {
  throw new Error("collect_refs did not return a set-like object");
}

const emitted = mod.emit_json_schema(builder);
if (emitted === null || typeof emitted !== "object") {
  throw new Error("emit_json_schema did not return a JSON-like value");
}
EOF
      ;;
    "mizchi/jwt.mbt")
      node --input-type=module - "$out" <<'EOF'
import path from "node:path";
import { pathToFileURL } from "node:url";

const out = process.argv[2];
const mod = await import(pathToFileURL(path.resolve(out, "index.js")).href);
const encoded = mod.base64url_encode(new Uint8Array([104, 105]));
if (encoded !== "aGk") {
  throw new Error(`unexpected base64url encoding: ${encoded}`);
}
const decoded = mod.base64url_decode(encoded)?._0;
if (!(decoded instanceof Uint8Array) || decoded.length !== 2 || decoded[0] !== 104 || decoded[1] !== 105) {
  throw new Error("base64url_decode did not roundtrip bytes");
}
const hash = mod.sha256(new Uint8Array([1, 2, 3]));
if (!(hash instanceof Uint8Array) || hash.length !== 32) {
  throw new Error("sha256 did not return a 32-byte Uint8Array");
}
EOF
      ;;
    "mizchi/markdown")
      node --input-type=module - "$out" <<'EOF'
import path from "node:path";
import { pathToFileURL } from "node:url";

const out = process.argv[2];
const mod = await import(pathToFileURL(path.resolve(out, "index.js")).href);
const html = mod.md_to_html("# Hello\n\nworld");
if (!html.includes("<h1>Hello</h1>") || !html.includes("<p>world</p>")) {
  throw new Error(`unexpected markdown output: ${html}`);
}
EOF
      ;;
    "mizchi/pixelmatch")
      node --input-type=module - "$out" <<'EOF'
import path from "node:path";
import { pathToFileURL } from "node:url";

const out = process.argv[2];
const mod = await import(pathToFileURL(path.resolve(out, "index.js")).href);
const red = mod.color_rgb(255, 0, 0);
const img1 = mod.image_new(1, 1);
const img2 = mod.image_new(1, 1);
mod.image_set_pixel(img1, 0, 0, red);
mod.image_set_pixel(img2, 0, 0, red);
const diff = mod.pixelmatch_simple(img1, img2, 0.1);
if (diff !== 0) {
  throw new Error(`expected identical images to have zero diff, got ${diff}`);
}
EOF
      ;;
    "mizchi/ripple")
      node --input-type=module - "$out" <<'EOF'
import path from "node:path";
import { pathToFileURL } from "node:url";

const out = process.argv[2];
const mod = await import(pathToFileURL(path.resolve(out, "index.js")).href);
const db = mod.database_new();
const rev = mod.database_current_revision(db);
const next = mod.revision_next(rev);
if (!mod.revision_is_after(next, rev)) {
  throw new Error("expected next revision to be after current revision");
}
EOF
      ;;
    "mizchi/semver")
      node --input-type=module - "$out" <<'EOF'
import path from "node:path";
import { pathToFileURL } from "node:url";

const out = process.argv[2];
const mod = await import(pathToFileURL(path.resolve(out, "index.js")).href);
const semver = mod.sem_ver_new(1, 2, 3);
const rendered = mod.sem_ver_to_string(semver);
const incremented = mod.inc("1.2.3", "patch");
if (rendered !== "1.2.3" || incremented !== "1.2.4") {
  throw new Error(`unexpected semver outputs: ${rendered}, ${incremented}`);
}
EOF
      ;;
    "mizchi/syntree")
      node --input-type=module - "$out" <<'EOF'
import path from "node:path";
import { pathToFileURL } from "node:url";

const out = process.argv[2];
const mod = await import(pathToFileURL(path.resolve(out, "index.js")).href);
const escaped = mod.escape_html("<a&>");
const languages = mod.supported_languages();
if (escaped !== "&lt;a&amp;&gt;" || !Array.isArray(languages) || languages.length === 0) {
  throw new Error("syntree smoke outputs were not usable");
}
EOF
      ;;
    "mizchi/tempfile")
      node --input-type=module - "$out" <<'EOF'
import path from "node:path";
import { pathToFileURL } from "node:url";

const out = process.argv[2];
const mod = await import(pathToFileURL(path.resolve(out, "index.js")).href);
const fileResult = mod.tempfile();
const file = fileResult?._0;
if (file === null || typeof file !== "object") {
  throw new Error("tempfile did not return a file object");
}
mod.named_temp_file_write_string(file, "hello");
const text = mod.named_temp_file_read_string(file)?._0;
mod.named_temp_file_cleanup(file);
if (text !== "hello") {
  throw new Error(`tempfile roundtrip failed: ${text}`);
}
EOF
      ;;
    "mizchi/vfs")
      node --input-type=module - "$out" <<'EOF'
import path from "node:path";
import { pathToFileURL } from "node:url";

const out = process.argv[2];
const mod = await import(pathToFileURL(path.resolve(out, "index.js")).href);
const file = mod.snapshot_file("a.txt", new Uint8Array([65, 66]));
const snapshot = mod.snapshot(["a.txt"], [file]);
if (file === null || typeof file !== "object" || snapshot === null || typeof snapshot !== "object") {
  throw new Error("vfs snapshot constructors did not return objects");
}
EOF
      ;;
  esac
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

verify_runtime_declaration_exports() {
  local out="$1"

  node --input-type=module - "$out" <<'EOF'
import fs from "node:fs";
import path from "node:path";

const out = path.resolve(process.argv[2]);
const rootJs = fs.readFileSync(path.join(out, "index.js"), "utf8");
const rootExports = new Set([...rootJs.matchAll(/\bas\s+([A-Za-z_$][\w$]*)/g)].map((match) => match[1]));

function walk(dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith("_")) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, acc);
    } else if (entry.isFile() && entry.name === "index.d.ts") {
      acc.push(full);
    }
  }
  return acc;
}

function readSubpathRuntimeMap(jsFile) {
  if (!fs.existsSync(jsFile)) return null;
  const source = fs.readFileSync(jsFile, "utf8");
  const map = new Map();
  const exportRe = /export\s+const\s+([A-Za-z_$][\w$]*)\s*=\s*__tsmbtRoot\.([A-Za-z_$][\w$]*)\s*;/g;
  for (const match of source.matchAll(exportRe)) {
    map.set(match[1], match[2]);
  }
  return map;
}

const missing = [];
for (const dtsFile of walk(out)) {
  const relative = path.relative(out, dtsFile);
  const source = fs.readFileSync(dtsFile, "utf8");
  const functions = [...source.matchAll(/^export function ([A-Za-z_$][\w$]*)/gm)].map((match) => match[1]);
  if (functions.length === 0) continue;

  if (relative === "index.d.ts") {
    for (const name of functions) {
      if (!rootExports.has(name)) {
        missing.push(`${relative}:${name}->${name}`);
      }
    }
    continue;
  }

  const jsFile = path.join(path.dirname(dtsFile), "index.js");
  const runtimeMap = readSubpathRuntimeMap(jsFile);
  if (runtimeMap === null) continue;
  for (const name of functions) {
    const runtimeName = runtimeMap.get(name);
    if (runtimeName === undefined || !rootExports.has(runtimeName)) {
      missing.push(`${relative}:${name}->${runtimeName ?? "<missing reexport>"}`);
    }
  }
}

if (missing.length > 0) {
  throw new Error(`runtime declaration exports missing:\n${missing.join("\n")}`);
}
EOF
}

verify_package_consumer() {
  local package_name="$1"
  local out="$2"

  case "$package_name" in
    "mizchi/js" | "mizchi/jsonschema" | "mizchi/jwt.mbt" | "mizchi/semver") ;;
    *) return ;;
  esac

  local consumer_dir="$out/_consumer"
  rm -rf "$consumer_dir"
  mkdir -p "$consumer_dir"

  node --input-type=module - "$package_name" "$out" "$consumer_dir" <<'EOF'
import fs from "node:fs";
import path from "node:path";

const packageName = process.argv[2];
const out = path.resolve(process.argv[3]);
const consumerDir = path.resolve(process.argv[4]);
const pkg = JSON.parse(fs.readFileSync(path.join(out, "package.json"), "utf8"));
const linkPath = path.join(consumerDir, "node_modules", ...pkg.name.split("/"));

fs.mkdirSync(path.dirname(linkPath), { recursive: true });
fs.symlinkSync(out, linkPath, "dir");
fs.writeFileSync(path.join(consumerDir, "package.json"), JSON.stringify({ type: "module" }, null, 2));

function writeStub(spec, source) {
  const file = path.join(consumerDir, "stubs", ...spec.split("/"), "index.d.ts");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, source);
  return path.relative(consumerDir, file);
}

const paths = {
  "moonbitlang/core/set": [writeStub("moonbitlang/core/set", "export interface Set<T = unknown> {}\n")],
  "moonbitlang/core/json": [writeStub("moonbitlang/core/json", "export interface JsonDecodeError {}\nexport interface ParseError {}\nexport interface FromJson {}\n")],
  "moonbitlang/core/bigint": [writeStub("moonbitlang/core/bigint", "export type BigInt = bigint;\n")],
};

let runtimeSource = "";
let typeSource = "";
switch (packageName) {
  case "mizchi/js":
    runtimeSource = `
import { undefined_, typeof_ } from "@mizchi/js";
import { log, new_object, typeof_ as coreTypeof, undefined_ as coreUndefined } from "@mizchi/js/core";

if (typeof_(undefined_()) !== "undefined") throw new Error("@mizchi/js root import failed");
if (typeof log !== "function") throw new Error("@mizchi/js/core log export failed");
if (coreTypeof(coreUndefined()) !== "undefined") throw new Error("@mizchi/js/core undefined export failed");
if (coreTypeof(new_object()) !== "object") throw new Error("@mizchi/js/core subpath import failed");
`;
    typeSource = `
import { undefined_, typeof_ } from "@mizchi/js";
import { log, new_object, typeof_ as coreTypeof, undefined_ as coreUndefined } from "@mizchi/js/core";

const valueType: string = typeof_(undefined_());
const logger: typeof log = log;
const subpathValueType: string = coreTypeof(coreUndefined());
const objectType: string = coreTypeof(new_object());
void logger;
void valueType;
void subpathValueType;
void objectType;
`;
    break;
  case "mizchi/jsonschema":
    runtimeSource = `
import { builder_new, builder_string } from "@mizchi/jsonschema";

const builder = builder_new();
const schema = builder_string(builder, 1, 10, ["name"]);
if (schema === null || typeof schema !== "object") throw new Error("@mizchi/jsonschema package import failed");
`;
    typeSource = `
import { builder_new, builder_string } from "@mizchi/jsonschema";

const builder = builder_new();
const schema = builder_string(builder, 1, 10, ["name"]);
void schema;
`;
    break;
  case "mizchi/jwt.mbt":
    runtimeSource = `
import { base64url_encode, base64url_decode } from "@mizchi/jwt.mbt";

const encoded = base64url_encode(new Uint8Array([104, 105]));
const decoded = base64url_decode(encoded)?._0;
if (!(decoded instanceof Uint8Array) || decoded[0] !== 104 || decoded[1] !== 105) {
  throw new Error("@mizchi/jwt.mbt package import failed");
}
`;
    typeSource = `
import { base64url_encode, base64url_decode } from "@mizchi/jwt.mbt";

const encoded: string = base64url_encode(new Uint8Array([104, 105]));
const decoded = base64url_decode(encoded);
void decoded;
`;
    break;
  case "mizchi/semver":
    runtimeSource = `
import { sem_ver_new, sem_ver_to_string } from "@mizchi/semver";

if (sem_ver_to_string(sem_ver_new(1, 2, 3)) !== "1.2.3") {
  throw new Error("@mizchi/semver package import failed");
}
`;
    typeSource = `
import { sem_ver_new, sem_ver_to_string } from "@mizchi/semver";

const rendered: string = sem_ver_to_string(sem_ver_new(1, 2, 3));
void rendered;
`;
    break;
  default:
    throw new Error(`missing consumer smoke for ${packageName}`);
}

fs.writeFileSync(path.join(consumerDir, "runtime.mjs"), runtimeSource);
fs.writeFileSync(path.join(consumerDir, "types.ts"), typeSource);
fs.writeFileSync(path.join(consumerDir, "tsconfig.json"), JSON.stringify({
  compilerOptions: {
    strict: true,
    noEmit: true,
    module: "esnext",
    moduleResolution: "bundler",
    target: "es2022",
    baseUrl: ".",
    lib: ["es2022", "dom"],
    paths,
  },
  files: ["types.ts"],
}, null, 2));
EOF

  node "$consumer_dir/runtime.mjs"
  pnpm exec tsc -p "$consumer_dir/tsconfig.json" --pretty false
}

for package_name in "${packages[@]}"; do
  verify_package "$package_name"
done

if [ "$checked" -eq 0 ]; then
  echo "skip real-world MoonBit probe: no target checkouts found" >&2
fi
