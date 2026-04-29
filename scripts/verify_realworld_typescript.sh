#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

node_modules_root="${TSMBT_REALWORLD_TYPESCRIPT_NODE_MODULES:-/Users/mz/ghq/github.com/mizchi/npm_typed.mbt/node_modules}"
if [ ! -d "$node_modules_root" ]; then
  echo "Skipping real-world TypeScript probe: node_modules not found at $node_modules_root" >&2
  echo "Set TSMBT_REALWORLD_TYPESCRIPT_NODE_MODULES to a node_modules directory to enable it." >&2
  exit 0
fi

log_root="_build/realworld-typescript/logs"
metrics_file="_build/realworld-typescript/METRICS.md"

run_logged() {
  local log_file="$1"
  shift

  mkdir -p "$(dirname "$log_file")"
  if ! "$@" > "$log_file" 2>&1; then
    cat "$log_file" >&2
    exit 1
  fi
}

count_lines_matching() {
  local pattern="$1"
  local file="$2"

  if [ ! -f "$file" ]; then
    printf '0\n'
    return
  fi
  grep -E -c "$pattern" "$file" || true
}

count_decl_jsvalue_refs() {
  local file="$1"

  if [ ! -f "$file" ]; then
    printf '0\n'
    return
  fi
  awk '
    /JSValue/ && $0 !~ /Complex or unsupported/ { count += 1 }
    END { print count + 0 }
  ' "$file"
}

init_metrics() {
  mkdir -p "$(dirname "$metrics_file")"
  cat > "$metrics_file" <<EOF
# Real-World TypeScript Bridge Metrics

node_modules: \`$node_modules_root\`

| package | bridge lines | declared types | declared functions | structs | external types | JSValue refs | JSValue functions | unsupported exports |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
EOF
}

append_metrics() {
  local package_spec="$1"
  local out="$2"
  local decl="$out/bridge.mbti"
  local impl="$out/bridge.mbt"
  local bridge_lines
  local declared_types
  local declared_functions
  local structs
  local external_types
  local jsvalue_refs
  local jsvalue_functions
  local unsupported_exports

  bridge_lines="$(wc -l < "$impl")"
  declared_types="$(count_lines_matching '^declare pub type ' "$decl")"
  declared_functions="$(count_lines_matching '^declare pub fn ' "$decl")"
  structs="$(count_lines_matching '^pub struct ' "$impl")"
  external_types="$(count_lines_matching '^#external$' "$impl")"
  jsvalue_refs="$(count_decl_jsvalue_refs "$decl")"
  jsvalue_functions="$(count_lines_matching '^declare pub fn .*JSValue' "$decl")"
  unsupported_exports="$(count_lines_matching '^/// Unsupported export ' "$decl")"

  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$package_spec" \
    "$bridge_lines" \
    "$declared_types" \
    "$declared_functions" \
    "$structs" \
    "$external_types" \
    "$jsvalue_refs" \
    "$jsvalue_functions" \
    "$unsupported_exports" >> "$metrics_file"

  assert_metric_budget "$package_spec" "$jsvalue_functions" "$unsupported_exports"
}

jsvalue_function_budget() {
  local package_spec="$1"

  case "$package_spec" in
    clsx) printf '0\n' ;;
    chalk) printf '3\n' ;;
    dotenv) printf '1\n' ;;
    ignore) printf '0\n' ;;
    hono) printf '0\n' ;;
    zod) printf '130\n' ;;
    date-fns) printf '10\n' ;;
    *) printf '999999\n' ;;
  esac
}

assert_metric_budget() {
  local package_spec="$1"
  local jsvalue_functions="$2"
  local unsupported_exports="$3"
  local jsvalue_budget

  jsvalue_budget="$(jsvalue_function_budget "$package_spec")"
  if [ "$unsupported_exports" -ne 0 ]; then
    echo "Unsupported exports regressed for $package_spec: $unsupported_exports" >&2
    exit 1
  fi
  if [ "$jsvalue_functions" -gt "$jsvalue_budget" ]; then
    echo "JSValue function budget exceeded for $package_spec: $jsvalue_functions > $jsvalue_budget" >&2
    exit 1
  fi
}

write_js_any_stub() {
  local root="$1"

  mkdir -p "$root/_stubs/mizchi_js/core"

  cat > "$root/_stubs/mizchi_js/moon.mod.json" <<'EOF'
{
  "name": "mizchi/js",
  "version": "0.0.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/_stubs/mizchi_js/core/moon.pkg.json" <<'EOF'
{}
EOF

  cat > "$root/_stubs/mizchi_js/core/core.mbt" <<'EOF'
///|
#external
pub type Any
EOF
}

write_probe_moon_mod() {
  local out="$1"
  local module_name="$2"

  write_js_any_stub "$out"

  cat > "$out/moon.mod.json" <<EOF
{
  "name": "realworld_typescript/$module_name",
  "version": "0.0.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF
}

write_bridge_test() {
  local out="$1"
  local module_name="$2"

  case "$module_name" in
    clsx)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world clsx bridge smoke" {
  assert_eq(clsx([]), "")
}
EOF
      ;;
    chalk)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world chalk bridge smoke" {
  let names = get_color_names()
  if names.length() == 0 {
    abort("expected chalk color names")
  }
}
EOF
      ;;
    dotenv)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world dotenv bridge smoke" {
  let _ = config(None)
  let _ = configDotenv(None)
}
EOF
      ;;
    ignore)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world ignore bridge smoke" {
  assert_true(isPathValid("src/index.ts"))
}
EOF
      ;;
    hono)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_hono_options() -> HonoOptions =
  #| () => ({ strict: true })

test "real-world hono bridge smoke" {
  let _ = new_hono(realworld_hono_options())
}
EOF
      ;;
    zod)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world zod bridge smoke" {
  let _ = string(None)
  let _ = number(None)
  let _ = boolean(None)
}
EOF
      ;;
    date_fns)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world date-fns bridge smoke" {
  assert_eq(daysToWeeks(14.0), 2.0)
  assert_eq(weeksToDays(2.0), 14.0)
  assert_eq(hoursToMinutes(2.0), 120.0)
  assert_true(isExists(2020.0, 1.0, 29.0))
}
EOF
      ;;
    *)
      echo "No bridge smoke test configured for $module_name" >&2
      exit 1
      ;;
  esac
}

write_build_smoke_main() {
  local out="$1"
  local module_name="$2"
  local smoke_pkg="__tsmbt_build_smoke__"
  local smoke_dir="$out/$smoke_pkg"

  rm -rf "$smoke_dir" "$out/_build/js/debug/build"
  mkdir -p "$smoke_dir"

  cat > "$smoke_dir/moon.pkg.json" <<EOF
{
  "is-main": true,
  "import": [
    { "path": "realworld_typescript/$module_name", "alias": "sut" }
  ]
}
EOF

  case "$module_name" in
    clsx)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.clsx([]) != "" {
    abort("unexpected clsx output")
  }
}
EOF
      ;;
    chalk)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.get_color_names().length() == 0 {
    abort("expected chalk color names")
  }
}
EOF
      ;;
    dotenv)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let _ = @sut.config(None)
  let _ = @sut.configDotenv(None)
}
EOF
      ;;
    ignore)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if !@sut.isPathValid("src/index.ts") {
    abort("expected ignore path to be valid")
  }
}
EOF
      ;;
    hono)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_hono_options() -> @sut.HonoOptions =
  #| () => ({ strict: true })

fn main {
  let _ = @sut.new_hono(realworld_hono_options())
}
EOF
      ;;
    zod)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let _ = @sut.string(None)
  let _ = @sut.number(None)
  let _ = @sut.boolean(None)
}
EOF
      ;;
    date_fns)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.daysToWeeks(14.0) != 2.0 {
    abort("unexpected daysToWeeks output")
  }
  if @sut.weeksToDays(2.0) != 14.0 {
    abort("unexpected weeksToDays output")
  }
  if @sut.hoursToMinutes(2.0) != 120.0 {
    abort("unexpected hoursToMinutes output")
  }
  if !@sut.isExists(2020.0, 1.0, 29.0) {
    abort("expected leap day to exist")
  }
}
EOF
      ;;
    *)
      echo "No build smoke configured for $module_name" >&2
      exit 1
      ;;
  esac
}

run_build_smoke() {
  local out="$1"
  local module_name="$2"
  local smoke_pkg="__tsmbt_build_smoke__"

  write_build_smoke_main "$out" "$module_name"
  run_logged "$log_root/${module_name}_build_smoke.log" \
    moon -C "$out" build --target js "$smoke_pkg"

  local built_js
  built_js="$(find "$out/_build/js/debug/build" -type f -name '*.js' | head -n 1)"
  if [ -z "$built_js" ]; then
    echo "moon build --target js did not emit a runnable JS file for $module_name" >&2
    exit 1
  fi

  printf '{ "type": "module" }\n' > "$(dirname "$built_js")/package.json"
  run_logged "$log_root/${module_name}_node_smoke.log" node "$built_js"
}

verify_package() {
  local package_spec="$1"
  local module_name="$2"
  local root="_build/realworld-typescript"
  local project="$root/project"
  local out="$project/dist/$module_name"

  if [ ! -e "$node_modules_root/$package_spec" ]; then
    echo "Missing package '$package_spec' in $node_modules_root" >&2
    exit 1
  fi

  echo "== $package_spec"

  rm -rf "$out"
  mkdir -p "$project"
  if [ ! -e "$project/node_modules" ]; then
    ln -s "$node_modules_root" "$project/node_modules"
  fi

  (
    cd "$project"
    run_logged "$repo_root/$log_root/${module_name}_generate.log" \
      moon run "$repo_root/src" -- \
      --input "$package_spec" \
      --out "dist/$module_name" \
      --direction ts-to-mbt
  )

  write_probe_moon_mod "$out" "$module_name"
  write_bridge_test "$out" "$module_name"

  run_logged "$log_root/${module_name}_check.log" \
    moon -C "$out" check --target js
  run_logged "$log_root/${module_name}_test.log" \
    moon -C "$out" test --target js
  run_build_smoke "$out" "$module_name"

  if [ -f "$out/SCAFFOLD_DIAGNOSTICS.md" ]; then
    echo "Unexpected scaffold diagnostics for $package_spec" >&2
    cat "$out/SCAFFOLD_DIAGNOSTICS.md" >&2
    exit 1
  fi

  printf "real-world checked %s lines=%s\n" \
    "$package_spec" \
    "$(wc -l < "$out/bridge.mbt")"
  append_metrics "$package_spec" "$out"
}

rm -rf _build/realworld-typescript
init_metrics

while IFS='|' read -r package_spec module_name; do
  verify_package "$package_spec" "$module_name"
done <<'EOF'
clsx|clsx
chalk|chalk
dotenv|dotenv
ignore|ignore
hono|hono
zod|zod
date-fns|date_fns
EOF

echo "metrics written to $metrics_file"
