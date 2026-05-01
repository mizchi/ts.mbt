#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
source "$repo_root/scripts/warning_guard.sh"

node_modules_root="${TSMBT_REALWORLD_TYPESCRIPT_NODE_MODULES:-/Users/mz/ghq/github.com/mizchi/npm_typed.mbt/node_modules}"
if [ ! -d "$node_modules_root" ]; then
  echo "Skipping real-world TypeScript probe: node_modules not found at $node_modules_root" >&2
  echo "Set TSMBT_REALWORLD_TYPESCRIPT_NODE_MODULES to a node_modules directory to enable it." >&2
  exit 0
fi

corpus_file="${TSMBT_REALWORLD_TYPESCRIPT_CORPUS:-corpus/realworld-typescript.tsv}"
if [ ! -f "$corpus_file" ]; then
  echo "Missing real-world TypeScript corpus config: $corpus_file" >&2
  exit 1
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

record_file_manifest() {
  local root="$1"
  local manifest="$2"
  shift 2

  mkdir -p "$(dirname "$manifest")"
  : > "$manifest"

  local file
  local digest
  for file in "$@"; do
    if [ ! -f "$root/$file" ]; then
      echo "Generated glue file missing: $root/$file" >&2
      exit 1
    fi
    digest="$(shasum -a 256 "$root/$file" | awk '{ print $1 }')"
    printf '%s  %s\n' "$digest" "$file" >> "$manifest"
  done
}

assert_file_manifest_unchanged() {
  local root="$1"
  local manifest="$2"
  local label="$3"
  shift 3
  local after="$manifest.after"

  record_file_manifest "$root" "$after" "$@"
  if ! cmp -s "$manifest" "$after"; then
    echo "Generated glue was modified after CLI generation for $label" >&2
    diff -u "$manifest" "$after" >&2 || true
    exit 1
  fi
}

generated_moonbit_source_files() {
  local root="$1"
  local file

  for file in bridge.mbt types.mbt converters.mbt externs.mbt guards.mbt; do
    if [ -f "$root/$file" ]; then
      printf '%s\n' "$file"
    fi
  done
}

generated_glue_files() {
  local root="$1"

  generated_moonbit_source_files "$root"
  printf '%s\n' bridge.mbti bridge.js moon.pkg.json
}

record_generated_glue_manifest() {
  local root="$1"
  local manifest="$2"
  local files=""
  local file

  while IFS= read -r file; do
    files="$files $file"
  done < <(generated_glue_files "$root")

  record_file_manifest "$root" "$manifest" $files
}

assert_generated_glue_manifest_unchanged() {
  local root="$1"
  local manifest="$2"
  local label="$3"
  local files=""
  local file

  while IFS= read -r file; do
    files="$files $file"
  done < <(generated_glue_files "$root")

  assert_file_manifest_unchanged "$root" "$manifest" "$label" $files
}

sum_generated_moonbit_lines() {
  local root="$1"
  local total=0
  local file

  while IFS= read -r file; do
    total=$((total + $(wc -l < "$root/$file")))
  done < <(generated_moonbit_source_files "$root")

  printf '%s\n' "$total"
}

count_matching_generated_moonbit_sources() {
  local pattern="$1"
  local root="$2"
  local total=0
  local file
  local count

  while IFS= read -r file; do
    count="$(count_lines_matching "$pattern" "$root/$file")"
    total=$((total + count))
  done < <(generated_moonbit_source_files "$root")

  printf '%s\n' "$total"
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

jsvalue_cause_counts() {
  local file="$1"
  local surface_total=0
  local unknown_any=0
  local overload_fallback=0
  local conditional_mapped_fallback=0
  local callback_function_fallback=0
  local tuple_array_fallback=0
  local namespace_value_fallback=0
  local line

  if [ ! -f "$file" ]; then
    printf '0|0|0|0|0|0|0\n'
    return
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" != *JSValue* ]]; then
      continue
    fi
    if [[ "$line" == "/// Complex or unsupported TypeScript types are widened to JSValue." ]]; then
      continue
    fi
    if [[ "$line" == "declare pub type JSValue" ]]; then
      continue
    fi

    surface_total=$((surface_total + 1))
    if [[ "$line" =~ Array\[JSValue\] || "$line" =~ JSValue\] ]]; then
      tuple_array_fallback=$((tuple_array_fallback + 1))
    elif [[ "$line" =~ (Unsupported\ export|namespace|Namespace|default|Default|get_|constants|Constants|meta|Meta|rest|Rest|runtime|Runtime|build|Build) ]]; then
      namespace_value_fallback=$((namespace_value_fallback + 1))
    elif [[ "$line" =~ \<call\> ]]; then
      overload_fallback=$((overload_fallback + 1))
    elif [[ "$line" =~ (callback|Callback|listener|Listener|handler|Handler|dispatch|Dispatch|reducer|Reducer|action|Action|func|Func|function|Function|component|Component|render|Render|propsAreEqual|Promise|NoParamCallback) ]]; then
      callback_function_fallback=$((callback_function_fallback + 1))
    elif [[ "$line" =~ (props|Props|children|Children|Ref|Element|ReactNode|LibraryManaged|Intrinsic|JSX|Partial|Readonly|Record|Exclude|Extract|NonNullable|ReturnType|Parameters|DOMAttributes|Key|source|self) ]]; then
      conditional_mapped_fallback=$((conditional_mapped_fallback + 1))
    elif [[ "$line" =~ ^declare\ pub\ fn ]]; then
      overload_fallback=$((overload_fallback + 1))
    else
      unknown_any=$((unknown_any + 1))
    fi
  done < "$file"

  printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "$surface_total" \
    "$unknown_any" \
    "$overload_fallback" \
    "$conditional_mapped_fallback" \
    "$callback_function_fallback" \
    "$tuple_array_fallback" \
    "$namespace_value_fallback"
}

init_metrics() {
  mkdir -p "$(dirname "$metrics_file")"
  cat > "$metrics_file" <<EOF
# Real-World TypeScript Bridge Metrics

node_modules: \`$node_modules_root\`
corpus: \`$corpus_file\`

| package | bridge lines | declared types | declared functions | structs | external types | JSValue refs | JSValue functions | JSValue surface | unknown/any | overload | conditional/mapped | callback/function | tuple/array | namespace/value | unsupported exports | generated glue unchanged |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
EOF
}

append_metrics() {
  local package_spec="$1"
  local out="$2"
  local decl="$out/bridge.mbti"
  local bridge_lines
  local declared_types
  local declared_functions
  local structs
  local external_types
  local jsvalue_refs
  local jsvalue_functions
  local jsvalue_surface
  local jsvalue_unknown_any
  local jsvalue_overload
  local jsvalue_conditional_mapped
  local jsvalue_callback_function
  local jsvalue_tuple_array
  local jsvalue_namespace_value
  local unsupported_exports

  bridge_lines="$(sum_generated_moonbit_lines "$out")"
  declared_types="$(count_lines_matching '^declare pub type ' "$decl")"
  declared_functions="$(count_lines_matching '^declare pub fn ' "$decl")"
  structs="$(count_matching_generated_moonbit_sources '^pub(\(all\))? struct ' "$out")"
  external_types="$(count_matching_generated_moonbit_sources '^#external$' "$out")"
  jsvalue_refs="$(count_decl_jsvalue_refs "$decl")"
  jsvalue_functions="$(count_lines_matching '^declare pub fn .*JSValue' "$decl")"
  IFS='|' read -r \
    jsvalue_surface \
    jsvalue_unknown_any \
    jsvalue_overload \
    jsvalue_conditional_mapped \
    jsvalue_callback_function \
    jsvalue_tuple_array \
    jsvalue_namespace_value < <(jsvalue_cause_counts "$decl")
  unsupported_exports="$(count_lines_matching '^/// Unsupported export ' "$decl")"

  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | yes |\n' \
    "$package_spec" \
    "$bridge_lines" \
    "$declared_types" \
    "$declared_functions" \
    "$structs" \
    "$external_types" \
    "$jsvalue_refs" \
    "$jsvalue_functions" \
    "$jsvalue_surface" \
    "$jsvalue_unknown_any" \
    "$jsvalue_overload" \
    "$jsvalue_conditional_mapped" \
    "$jsvalue_callback_function" \
    "$jsvalue_tuple_array" \
    "$jsvalue_namespace_value" \
    "$unsupported_exports" >> "$metrics_file"

  if [ "${TSMBT_REALWORLD_TYPESCRIPT_SKIP_BUDGETS:-false}" != "true" ]; then
    assert_metric_budget \
      "$package_spec" \
      "$jsvalue_functions" \
      "$unsupported_exports" \
      "$jsvalue_surface" \
      "$jsvalue_unknown_any" \
      "$jsvalue_overload" \
      "$jsvalue_conditional_mapped" \
      "$jsvalue_callback_function" \
      "$jsvalue_tuple_array" \
      "$jsvalue_namespace_value"
  fi
}

jsvalue_function_budget() {
  local package_spec="$1"

  case "$package_spec" in
    clsx) printf '0\n' ;;
    chalk) printf '4\n' ;;
    dotenv) printf '1\n' ;;
    ignore) printf '1\n' ;;
    hono) printf '36\n' ;;
    zod) printf '239\n' ;;
    date-fns) printf '18\n' ;;
    node:sqlite) printf '0\n' ;;
    node:fs) printf '2\n' ;;
    node:path) printf '0\n' ;;
    node:crypto) printf '0\n' ;;
    colorette) printf '1\n' ;;
    magic-string) printf '9\n' ;;
    source-map) printf '9\n' ;;
    valibot) printf '92\n' ;;
    immer) printf '16\n' ;;
    execa) printf '1\n' ;;
    preact) printf '10\n' ;;
    node:os) printf '0\n' ;;
    node:url) printf '0\n' ;;
    node:querystring) printf '0\n' ;;
    node:assert) printf '24\n' ;;
    node:util) printf '13\n' ;;
    node:buffer) printf '0\n' ;;
    *) printf '0\n' ;;
  esac
}

unsupported_export_budget() {
  local package_spec="$1"

  case "$package_spec" in
    zod) printf '1\n' ;;
    node:sqlite) printf '0\n' ;;
    node:fs) printf '0\n' ;;
    *) printf '0\n' ;;
  esac
}

jsvalue_cause_budget() {
  local package_spec="$1"

  case "$package_spec" in
    clsx) printf '0|0|0|0|0|0|0\n' ;;
    chalk) printf '5|0|0|0|0|2|3\n' ;;
    dotenv) printf '2|1|1|0|0|0|0\n' ;;
    ignore) printf '2|1|0|1|0|0|0\n' ;;
    hono) printf '55|10|6|23|3|4|9\n' ;;
    zod) printf '433|163|93|111|26|21|19\n' ;;
    date-fns) printf '22|4|7|1|0|8|2\n' ;;
    colorette) printf '1|0|1|0|0|0|0\n' ;;
    magic-string) printf '12|3|0|2|0|0|7\n' ;;
    source-map) printf '14|2|0|5|4|2|1\n' ;;
    valibot) printf '659|539|28|27|19|31|15\n' ;;
    immer) printf '20|1|7|2|2|2|6\n' ;;
    execa) printf '1|0|0|0|1|0|0\n' ;;
    preact) printf '1319|1246|1|21|34|1|16\n' ;;
    node:sqlite) printf '3|3|0|0|0|0|0\n' ;;
    node:fs) printf '11|4|0|0|0|7|0\n' ;;
    node:path) printf '0|0|0|0|0|0|0\n' ;;
    node:crypto) printf '0|0|0|0|0|0|0\n' ;;
    node:os) printf '0|0|0|0|0|0|0\n' ;;
    node:url) printf '0|0|0|0|0|0|0\n' ;;
    node:querystring) printf '0|0|0|0|0|0|0\n' ;;
    node:assert) printf '27|3|16|3|2|0|3\n' ;;
    node:util) printf '22|8|9|1|1|2|1\n' ;;
    node:buffer) printf '0|0|0|0|0|0|0\n' ;;
    *) printf '0|0|0|0|0|0|0\n' ;;
  esac
}

assert_jsvalue_cause_budget() {
  local package_spec="$1"
  local actual_surface="$2"
  local actual_unknown_any="$3"
  local actual_overload="$4"
  local actual_conditional_mapped="$5"
  local actual_callback_function="$6"
  local actual_tuple_array="$7"
  local actual_namespace_value="$8"
  local budget_surface
  local budget_unknown_any
  local budget_overload
  local budget_conditional_mapped
  local budget_callback_function
  local budget_tuple_array
  local budget_namespace_value

  IFS='|' read -r \
    budget_surface \
    budget_unknown_any \
    budget_overload \
    budget_conditional_mapped \
    budget_callback_function \
    budget_tuple_array \
    budget_namespace_value < <(jsvalue_cause_budget "$package_spec")

  if [ "$actual_surface" -gt "$budget_surface" ]; then
    echo "JSValue surface budget exceeded for $package_spec: $actual_surface > $budget_surface" >&2
    exit 1
  fi
  if [ "$actual_unknown_any" -gt "$budget_unknown_any" ]; then
    echo "JSValue unknown/any budget exceeded for $package_spec: $actual_unknown_any > $budget_unknown_any" >&2
    exit 1
  fi
  if [ "$actual_overload" -gt "$budget_overload" ]; then
    echo "JSValue overload budget exceeded for $package_spec: $actual_overload > $budget_overload" >&2
    exit 1
  fi
  if [ "$actual_conditional_mapped" -gt "$budget_conditional_mapped" ]; then
    echo "JSValue conditional/mapped budget exceeded for $package_spec: $actual_conditional_mapped > $budget_conditional_mapped" >&2
    exit 1
  fi
  if [ "$actual_callback_function" -gt "$budget_callback_function" ]; then
    echo "JSValue callback/function budget exceeded for $package_spec: $actual_callback_function > $budget_callback_function" >&2
    exit 1
  fi
  if [ "$actual_tuple_array" -gt "$budget_tuple_array" ]; then
    echo "JSValue tuple/array budget exceeded for $package_spec: $actual_tuple_array > $budget_tuple_array" >&2
    exit 1
  fi
  if [ "$actual_namespace_value" -gt "$budget_namespace_value" ]; then
    echo "JSValue namespace/value budget exceeded for $package_spec: $actual_namespace_value > $budget_namespace_value" >&2
    exit 1
  fi
}

assert_metric_budget() {
  local package_spec="$1"
  local jsvalue_functions="$2"
  local unsupported_exports="$3"
  local jsvalue_surface="$4"
  local jsvalue_unknown_any="$5"
  local jsvalue_overload="$6"
  local jsvalue_conditional_mapped="$7"
  local jsvalue_callback_function="$8"
  local jsvalue_tuple_array="$9"
  local jsvalue_namespace_value="${10}"
  local jsvalue_budget
  local unsupported_budget

  jsvalue_budget="$(jsvalue_function_budget "$package_spec")"
  unsupported_budget="$(unsupported_export_budget "$package_spec")"
  if [ "$unsupported_exports" -gt "$unsupported_budget" ]; then
    echo "Unsupported exports regressed for $package_spec: $unsupported_exports > $unsupported_budget" >&2
    exit 1
  fi
  if [ "$jsvalue_functions" -gt "$jsvalue_budget" ]; then
    echo "JSValue function budget exceeded for $package_spec: $jsvalue_functions > $jsvalue_budget" >&2
    exit 1
  fi
  assert_jsvalue_cause_budget \
    "$package_spec" \
    "$jsvalue_surface" \
    "$jsvalue_unknown_any" \
    "$jsvalue_overload" \
    "$jsvalue_conditional_mapped" \
    "$jsvalue_callback_function" \
    "$jsvalue_tuple_array" \
    "$jsvalue_namespace_value"
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

///|
#external
pub type Promise[T]
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

fn realworld_hono_handler(c : Context) -> Response {
  c.text("hello from moonbit", None, None)
}

test "real-world hono bridge smoke" {
  let app = new_hono(Some(realworld_hono_options()))
  let _ = app.hono_get("/", realworld_hono_handler)
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
    colorette)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world colorette bridge smoke" {
  let _ = get_red()
  let _ = createColors(None)
  let _ = get_is_color_supported()
}
EOF
      ;;
    magic_string)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world magic-string bridge smoke" {
  let s = new_default("hello", None)
  assert_eq(s.default_to_string(), "hello")
  let _ = s.default_append("!")
  assert_eq(s.default_to_string(), "hello!")
}
EOF
      ;;
    source_map)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world source-map bridge smoke" {
  let generator = new_source_map_generator(None)
  if generator.source_map_generator_to_string().length() == 0 {
    abort("expected source map generator output")
  }
}
EOF
      ;;
    valibot)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world valibot bridge smoke" {
  let _ = string()
  let _ = number()
  let _ = boolean()
  let _ = uuid()
}
EOF
      ;;
    immer)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_immer_object() -> JSValue =
  #| () => ({ value: 1 })

extern "js" fn realworld_immer_false() -> JSValue =
  #| () => false

test "real-world immer bridge smoke" {
  assert_true(isDraftable(realworld_immer_object()))
  assert_false(isDraftable(realworld_immer_false()))
}
EOF
      ;;
    execa)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world execa bridge smoke" {
  let parts = parseCommandString("node --version")
  assert_eq(parts.length(), 2)
  let _ = get_execa()
}
EOF
      ;;
    preact)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_preact_children() -> Array[ComponentChildren] =
  #| () => []

test "real-world preact bridge smoke" {
  let _ = h(Input, None, realworld_preact_children())
  let _ = createRef()
}
EOF
      ;;
    node_sqlite)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_node_sqlite_memory_path() -> PathLike =
  #| () => ":memory:"

fn realworld_node_sqlite_options() -> DatabaseSyncOptions {
  {
    open: Some(true),
    enableForeignKeyConstraints: None,
    enableDoubleQuotedStringLiterals: None,
    readOnly: None,
    allowExtension: None,
    timeout: None,
    readBigInts: None,
    returnArrays: None,
    allowBareNamedParameters: None,
    allowUnknownNamedParameters: None,
    defensive: None,
  }
}

extern "js" fn realworld_node_sqlite_params() -> Array[SQLInputValue] =
  #| () => []

extern "js" fn realworld_node_sqlite_row_value(row : StringRecordOfSqloutputValue?) -> String =
  #| (row) => row.value

test "real-world node:sqlite bridge smoke" {
  let db = new_database_sync(
    realworld_node_sqlite_memory_path(),
    Some(realworld_node_sqlite_options()),
  )
  assert_true(db.get_database_sync_is_open())
  db.database_sync_exec("CREATE TABLE data (key INTEGER PRIMARY KEY, value TEXT) STRICT")
  db.database_sync_exec("INSERT INTO data (key, value) VALUES (1, 'hello')")
  db.database_sync_exec("UPDATE data SET value = 'world' WHERE key = 1")
  let stmt = db.database_sync_prepare("SELECT value FROM data WHERE key = 1", None)
  let row = stmt.statement_sync_get(realworld_node_sqlite_params())
  assert_eq(realworld_node_sqlite_row_value(row), "world")
  db.database_sync_close()
  assert_false(db.get_database_sync_is_open())
}
EOF
      ;;
    node_fs)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_node_fs_path_like() -> PathLike =
  #| () => process.cwd() + "/node-fs-test.txt"

extern "js" fn realworld_node_fs_path_or_fd() -> PathOrFileDescriptor =
  #| () => process.cwd() + "/node-fs-test.txt"

extern "js" fn realworld_node_fs_data() -> String =
  #| () => "hello from moonbit"

extern "js" fn realworld_node_fs_to_string(data : NonSharedBuffer) -> String =
  #| (data) => data.toString("utf8")

test "real-world node:fs bridge smoke" {
  let path = realworld_node_fs_path_like()
  let file = realworld_node_fs_path_or_fd()
  if existsSync(path) {
    unlinkSync(path)
  }
  writeFileSync(file, realworld_node_fs_data(), None)
  assert_true(existsSync(path))
  let data = readFileSync(file, None)
  assert_eq(realworld_node_fs_to_string(data), "hello from moonbit")
  unlinkSync(path)
  assert_false(existsSync(path))
}
EOF
      ;;
    node_path)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world node:path bridge smoke" {
  assert_eq(pathNormalize("a/../b"), "b")
  assert_eq(pathBasename("/tmp/demo.txt", Some(".txt")), "demo")
  assert_eq(pathExtname("demo.txt"), ".txt")
  assert_false(pathIsAbsolute("relative/path"))
}
EOF
      ;;
    node_crypto)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_node_crypto_binary_like() -> BinaryLike =
  #| () => "hello"

test "real-world node:crypto bridge smoke" {
  let digest = hash("sha256", realworld_node_crypto_binary_like(), None)
  assert_eq(
    digest,
    "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
  )
  if getHashes().length() == 0 {
    abort("expected crypto hash algorithms")
  }
}
EOF
      ;;
    node_os)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world node:os bridge smoke" {
  if tmpdir().length() == 0 {
    abort("expected tmpdir")
  }
  if homedir().length() == 0 {
    abort("expected homedir")
  }
  if availableParallelism() <= 0.0 {
    abort("expected available parallelism")
  }
}
EOF
      ;;
    node_url)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world node:url bridge smoke" {
  assert_eq(domainToASCII("example.com"), "example.com")
  assert_eq(domainToUnicode("example.com"), "example.com")
  assert_eq(resolve("https://example.com/a/b", "../c"), "https://example.com/c")
}
EOF
      ;;
    node_querystring)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world node:querystring bridge smoke" {
  assert_eq(escape("a b"), "a%20b")
  assert_eq(unescape("a%20b"), "a b")
}
EOF
      ;;
    node_assert)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_assert_true() -> JSValue =
  #| () => true

extern "js" fn realworld_assert_one() -> JSValue =
  #| () => 1

test "real-world node:assert bridge smoke" {
  let _ = assertOk(realworld_assert_true(), None)
  assertEqual(realworld_assert_one(), realworld_assert_one(), None)
}
EOF
      ;;
    node_util)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_util_array() -> JSValue =
  #| () => []

test "real-world node:util bridge smoke" {
  assert_eq(toUSVString("ok"), "ok")
  assert_eq(stripVTControlCharacters("plain"), "plain")
  assert_true(isArray(realworld_util_array()))
}
EOF
      ;;
    node_buffer)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_buffer_value() -> Uint8Array =
  #| () => Buffer.from("hello")

test "real-world node:buffer bridge smoke" {
  assert_true(isUtf8(realworld_buffer_value()))
  if get_k_max_length() <= 0.0 {
    abort("expected positive buffer max length")
  }
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

fn realworld_hono_handler(c : @sut.Context) -> @sut.Response {
  c.text("hello from moonbit", None, None)
}

fn main {
  let app = @sut.new_hono(Some(realworld_hono_options()))
  let _ = app.hono_get("/", realworld_hono_handler)
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
    colorette)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let _ = @sut.get_red()
  let _ = @sut.createColors(None)
  let _ = @sut.get_is_color_supported()
}
EOF
      ;;
    magic_string)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let s = @sut.new_default("hello", None)
  if s.default_to_string() != "hello" {
    abort("unexpected initial magic-string output")
  }
  let _ = s.default_append("!")
  if s.default_to_string() != "hello!" {
    abort("unexpected appended magic-string output")
  }
}
EOF
      ;;
    source_map)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let generator = @sut.new_source_map_generator(None)
  if generator.source_map_generator_to_string().length() == 0 {
    abort("expected source map generator output")
  }
}
EOF
      ;;
    valibot)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let _ = @sut.string()
  let _ = @sut.number()
  let _ = @sut.boolean()
  let _ = @sut.uuid()
}
EOF
      ;;
    immer)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_immer_object() -> @sut.JSValue =
  #| () => ({ value: 1 })

extern "js" fn realworld_immer_false() -> @sut.JSValue =
  #| () => false

fn main {
  if !@sut.isDraftable(realworld_immer_object()) {
    abort("expected object to be draftable")
  }
  if @sut.isDraftable(realworld_immer_false()) {
    abort("expected false to be non-draftable")
  }
}
EOF
      ;;
    execa)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let parts = @sut.parseCommandString("node --version")
  if parts.length() != 2 {
    abort("unexpected parsed command length")
  }
  let _ = @sut.get_execa()
}
EOF
      ;;
    preact)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_preact_children() -> Array[@sut.ComponentChildren] =
  #| () => []

fn main {
  let _ = @sut.h(@sut.Input, None, realworld_preact_children())
  let _ = @sut.createRef()
}
EOF
      ;;
    node_sqlite)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_node_sqlite_memory_path() -> @sut.PathLike =
  #| () => ":memory:"

fn realworld_node_sqlite_options() -> @sut.DatabaseSyncOptions {
  @sut.DatabaseSyncOptions::{
    open: Some(true),
    enableForeignKeyConstraints: None,
    enableDoubleQuotedStringLiterals: None,
    readOnly: None,
    allowExtension: None,
    timeout: None,
    readBigInts: None,
    returnArrays: None,
    allowBareNamedParameters: None,
    allowUnknownNamedParameters: None,
    defensive: None,
  }
}

extern "js" fn realworld_node_sqlite_params() -> Array[@sut.SQLInputValue] =
  #| () => []

extern "js" fn realworld_node_sqlite_row_value(row : @sut.StringRecordOfSqloutputValue?) -> String =
  #| (row) => row.value

fn main {
  let db = @sut.new_database_sync(
    realworld_node_sqlite_memory_path(),
    Some(realworld_node_sqlite_options()),
  )
  if !db.get_database_sync_is_open() {
    abort("expected sqlite database to be open")
  }
  db.database_sync_exec("CREATE TABLE data (key INTEGER PRIMARY KEY, value TEXT) STRICT")
  db.database_sync_exec("INSERT INTO data (key, value) VALUES (1, 'hello')")
  db.database_sync_exec("UPDATE data SET value = 'world' WHERE key = 1")
  let stmt = db.database_sync_prepare("SELECT value FROM data WHERE key = 1", None)
  let row = stmt.statement_sync_get(realworld_node_sqlite_params())
  if realworld_node_sqlite_row_value(row) != "world" {
    abort("unexpected sqlite row value")
  }
  db.database_sync_close()
  if db.get_database_sync_is_open() {
    abort("expected sqlite database to be closed")
  }
}
EOF
      ;;
    node_fs)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_node_fs_path_like() -> @sut.PathLike =
  #| () => process.cwd() + "/node-fs-build-smoke.txt"

extern "js" fn realworld_node_fs_path_or_fd() -> @sut.PathOrFileDescriptor =
  #| () => process.cwd() + "/node-fs-build-smoke.txt"

extern "js" fn realworld_node_fs_data() -> String =
  #| () => "hello from moonbit"

extern "js" fn realworld_node_fs_to_string(data : @sut.NonSharedBuffer) -> String =
  #| (data) => data.toString("utf8")

fn main {
  let path = realworld_node_fs_path_like()
  let file = realworld_node_fs_path_or_fd()
  if @sut.existsSync(path) {
    @sut.unlinkSync(path)
  }
  @sut.writeFileSync(file, realworld_node_fs_data(), None)
  if !@sut.existsSync(path) {
    abort("expected file to exist")
  }
  let data = @sut.readFileSync(file, None)
  if realworld_node_fs_to_string(data) != "hello from moonbit" {
    abort("unexpected file content")
  }
  @sut.unlinkSync(path)
  if @sut.existsSync(path) {
    abort("expected file to be removed")
  }
}
EOF
      ;;
    node_path)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.pathNormalize("a/../b") != "b" {
    abort("unexpected normalize output")
  }
  if @sut.pathBasename("/tmp/demo.txt", Some(".txt")) != "demo" {
    abort("unexpected basename output")
  }
  if @sut.pathExtname("demo.txt") != ".txt" {
    abort("unexpected extname output")
  }
  if @sut.pathIsAbsolute("relative/path") {
    abort("expected relative path")
  }
}
EOF
      ;;
    node_crypto)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_node_crypto_binary_like() -> @sut.BinaryLike =
  #| () => "hello"

fn main {
  let digest = @sut.hash("sha256", realworld_node_crypto_binary_like(), None)
  if digest != "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" {
    abort("unexpected sha256 digest")
  }
  if @sut.getHashes().length() == 0 {
    abort("expected crypto hash algorithms")
  }
}
EOF
      ;;
    node_os)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.tmpdir().length() == 0 {
    abort("expected tmpdir")
  }
  if @sut.homedir().length() == 0 {
    abort("expected homedir")
  }
  if @sut.availableParallelism() <= 0.0 {
    abort("expected available parallelism")
  }
}
EOF
      ;;
    node_url)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.domainToASCII("example.com") != "example.com" {
    abort("unexpected ascii domain")
  }
  if @sut.domainToUnicode("example.com") != "example.com" {
    abort("unexpected unicode domain")
  }
  if @sut.resolve("https://example.com/a/b", "../c") != "https://example.com/c" {
    abort("unexpected url resolve output")
  }
}
EOF
      ;;
    node_querystring)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.escape("a b") != "a%20b" {
    abort("unexpected escape output")
  }
  if @sut.unescape("a%20b") != "a b" {
    abort("unexpected unescape output")
  }
}
EOF
      ;;
    node_assert)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_assert_true() -> @sut.JSValue =
  #| () => true

extern "js" fn realworld_assert_one() -> @sut.JSValue =
  #| () => 1

fn main {
  let _ = @sut.assertOk(realworld_assert_true(), None)
  @sut.assertEqual(realworld_assert_one(), realworld_assert_one(), None)
}
EOF
      ;;
    node_util)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_util_array() -> @sut.JSValue =
  #| () => []

fn main {
  if @sut.toUSVString("ok") != "ok" {
    abort("unexpected toUSVString output")
  }
  if @sut.stripVTControlCharacters("plain") != "plain" {
    abort("unexpected stripVTControlCharacters output")
  }
  if !@sut.isArray(realworld_util_array()) {
    abort("expected array")
  }
}
EOF
      ;;
    node_buffer)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_buffer_value() -> @sut.Uint8Array =
  #| () => Buffer.from("hello")

fn main {
  if !@sut.isUtf8(realworld_buffer_value()) {
    abort("expected utf8 buffer")
  }
  if @sut.get_k_max_length() <= 0.0 {
    abort("expected positive buffer max length")
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
  if [ "$module_name" = "node_sqlite" ]; then
    run_logged "$log_root/${module_name}_node_smoke.log" \
      node --experimental-sqlite "$built_js"
  else
    run_logged "$log_root/${module_name}_node_smoke.log" node "$built_js"
  fi
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

  local generated_glue_manifest="$log_root/${module_name}_generated_glue.sha256"
  record_generated_glue_manifest "$out" "$generated_glue_manifest"

  write_probe_moon_mod "$out" "$module_name"
  write_bridge_test "$out" "$module_name"

  run_logged "$log_root/${module_name}_check.log" \
    moon -C "$out" check --target js
  run_logged "$log_root/${module_name}_test.log" \
    moon -C "$out" test --target js
  run_build_smoke "$out" "$module_name"

  if [ ! -f "$out/SCAFFOLD_DIAGNOSTICS.md" ]; then
    echo "Expected scaffold diagnostics for $package_spec" >&2
    exit 1
  fi

  assert_generated_glue_manifest_unchanged \
    "$out" "$generated_glue_manifest" "$package_spec"

  printf "real-world checked %s lines=%s\n" \
    "$package_spec" \
    "$(sum_generated_moonbit_lines "$out")"
  append_metrics "$package_spec" "$out"
}

resolve_configured_types_path() {
  local configured_path="$1"

  if [ -z "$configured_path" ]; then
    return 1
  fi
  if [[ "$configured_path" = /* ]]; then
    if [ -f "$configured_path" ]; then
      printf '%s\n' "$configured_path"
      return 0
    fi
    return 1
  fi
  if [ -f "$node_modules_root/$configured_path" ]; then
    printf '%s\n' "$node_modules_root/$configured_path"
    return 0
  fi
  return 1
}

find_node_sqlite_types() {
  local configured_path="${1:-}"

  if [ -n "$configured_path" ]; then
    if resolve_configured_types_path "$configured_path"; then
      return 0
    fi
    echo "Configured node:sqlite types path does not exist: $configured_path" >&2
    exit 1
  fi
  if [ -n "${TSMBT_NODE_SQLITE_TYPES:-}" ]; then
    if [ -f "$TSMBT_NODE_SQLITE_TYPES" ]; then
      printf '%s\n' "$TSMBT_NODE_SQLITE_TYPES"
      return 0
    fi
    echo "TSMBT_NODE_SQLITE_TYPES does not exist: $TSMBT_NODE_SQLITE_TYPES" >&2
    exit 1
  fi

  if [ -f "$node_modules_root/@types/node/sqlite.d.ts" ]; then
    printf '%s\n' "$node_modules_root/@types/node/sqlite.d.ts"
    return 0
  fi

  return 1
}

find_node_fs_types() {
  local configured_path="${1:-}"

  if [ -n "$configured_path" ]; then
    if resolve_configured_types_path "$configured_path"; then
      return 0
    fi
    echo "Configured node:fs types path does not exist: $configured_path" >&2
    exit 1
  fi
  if [ -n "${TSMBT_NODE_FS_TYPES:-}" ]; then
    if [ -f "$TSMBT_NODE_FS_TYPES" ]; then
      printf '%s\n' "$TSMBT_NODE_FS_TYPES"
      return 0
    fi
    echo "TSMBT_NODE_FS_TYPES does not exist: $TSMBT_NODE_FS_TYPES" >&2
    exit 1
  fi

  if [ -f "$node_modules_root/@types/node/fs.d.ts" ]; then
    printf '%s\n' "$node_modules_root/@types/node/fs.d.ts"
    return 0
  fi

  return 1
}

find_node_builtin_types() {
  local package_spec="$1"
  local configured_path="$2"
  local env_var="$3"
  local types_file="$4"

  if [ -n "$configured_path" ]; then
    if resolve_configured_types_path "$configured_path"; then
      return 0
    fi
    echo "Configured $package_spec types path does not exist: $configured_path" >&2
    exit 1
  fi

  local env_path="${!env_var:-}"
  if [ -n "$env_path" ]; then
    if [ -f "$env_path" ]; then
      printf '%s\n' "$env_path"
      return 0
    fi
    echo "$env_var does not exist: $env_path" >&2
    exit 1
  fi

  if [ -f "$node_modules_root/@types/node/$types_file" ]; then
    printf '%s\n' "$node_modules_root/@types/node/$types_file"
    return 0
  fi

  return 1
}

verify_node_sqlite() {
  local configured_types_path="${1:-}"
  local module_name="node_sqlite"
  local root="_build/realworld-typescript"
  local out="$root/node_sqlite"
  local types_path

  if ! types_path="$(find_node_sqlite_types "$configured_types_path")"; then
    echo "Skipping node:sqlite probe: @types/node/sqlite.d.ts not found" >&2
    echo "Set TSMBT_NODE_SQLITE_TYPES to enable it." >&2
    return
  fi

  echo "== node:sqlite"

  rm -rf "$out"
  mkdir -p "$out"

  run_logged "$log_root/${module_name}_generate.log" \
    moon run src -- \
    --input "$types_path" \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec node:sqlite

  local generated_glue_manifest="$log_root/${module_name}_generated_glue.sha256"
  record_generated_glue_manifest "$out" "$generated_glue_manifest"

  write_probe_moon_mod "$out" "$module_name"
  write_bridge_test "$out" "$module_name"

  run_logged "$log_root/${module_name}_check.log" \
    moon -C "$out" check --target js
  run_logged "$log_root/${module_name}_test.log" \
    env NODE_OPTIONS=--experimental-sqlite moon -C "$out" test --target js
  run_build_smoke "$out" "$module_name"

  assert_generated_glue_manifest_unchanged \
    "$out" "$generated_glue_manifest" "node:sqlite"

  printf "real-world checked %s lines=%s\n" \
    "node:sqlite" \
    "$(sum_generated_moonbit_lines "$out")"
  append_metrics "node:sqlite" "$out"
}

verify_node_fs() {
  local configured_types_path="${1:-}"
  local module_name="node_fs"
  local root="_build/realworld-typescript"
  local out="$root/node_fs"
  local types_path

  if ! types_path="$(find_node_fs_types "$configured_types_path")"; then
    echo "Skipping node:fs probe: @types/node/fs.d.ts not found" >&2
    echo "Set TSMBT_NODE_FS_TYPES to enable it." >&2
    return
  fi

  echo "== node:fs"

  rm -rf "$out"
  mkdir -p "$out"

  run_logged "$log_root/${module_name}_generate.log" \
    moon run src -- \
    --input "$types_path" \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec node:fs

  local generated_glue_manifest="$log_root/${module_name}_generated_glue.sha256"
  record_generated_glue_manifest "$out" "$generated_glue_manifest"

  write_probe_moon_mod "$out" "$module_name"
  write_bridge_test "$out" "$module_name"

  run_logged "$log_root/${module_name}_check.log" \
    moon -C "$out" check --target js
  run_logged "$log_root/${module_name}_test.log" \
    moon -C "$out" test --target js
  run_build_smoke "$out" "$module_name"

  assert_generated_glue_manifest_unchanged \
    "$out" "$generated_glue_manifest" "node:fs"

  printf "real-world checked %s lines=%s\n" \
    "node:fs" \
    "$(sum_generated_moonbit_lines "$out")"
  append_metrics "node:fs" "$out"
}

verify_node_builtin() {
  local package_spec="$1"
  local module_name="$2"
  local configured_types_path="${3:-}"
  local types_file="$4"
  local env_var="$5"
  local root="_build/realworld-typescript"
  local out="$root/$module_name"
  local types_path

  if ! types_path="$(find_node_builtin_types "$package_spec" "$configured_types_path" "$env_var" "$types_file")"; then
    echo "Skipping $package_spec probe: @types/node/$types_file not found" >&2
    echo "Set $env_var to enable it." >&2
    return
  fi

  echo "== $package_spec"

  rm -rf "$out"
  mkdir -p "$out"

  run_logged "$log_root/${module_name}_generate.log" \
    moon run src -- \
    --input "$types_path" \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec "$package_spec"

  local generated_glue_manifest="$log_root/${module_name}_generated_glue.sha256"
  record_generated_glue_manifest "$out" "$generated_glue_manifest"

  write_probe_moon_mod "$out" "$module_name"
  write_bridge_test "$out" "$module_name"

  run_logged "$log_root/${module_name}_check.log" \
    moon -C "$out" check --target js
  run_logged "$log_root/${module_name}_test.log" \
    moon -C "$out" test --target js
  run_build_smoke "$out" "$module_name"

  assert_generated_glue_manifest_unchanged \
    "$out" "$generated_glue_manifest" "$package_spec"

  printf "real-world checked %s lines=%s\n" \
    "$package_spec" \
    "$(sum_generated_moonbit_lines "$out")"
  append_metrics "$package_spec" "$out"
}

rm -rf _build/realworld-typescript
init_metrics

while IFS='|' read -r kind package_spec module_name types_path; do
  if [ -z "${kind:-}" ] || [[ "$kind" == \#* ]]; then
    continue
  fi
  case "$kind" in
    package)
      verify_package "$package_spec" "$module_name"
      ;;
    node_builtin)
      case "$package_spec" in
        node:sqlite) verify_node_sqlite "$types_path" ;;
        node:fs) verify_node_fs "$types_path" ;;
        node:path) verify_node_builtin "$package_spec" "$module_name" "$types_path" "path.d.ts" "TSMBT_NODE_PATH_TYPES" ;;
        node:crypto) verify_node_builtin "$package_spec" "$module_name" "$types_path" "crypto.d.ts" "TSMBT_NODE_CRYPTO_TYPES" ;;
        node:os) verify_node_builtin "$package_spec" "$module_name" "$types_path" "os.d.ts" "TSMBT_NODE_OS_TYPES" ;;
        node:url) verify_node_builtin "$package_spec" "$module_name" "$types_path" "url.d.ts" "TSMBT_NODE_URL_TYPES" ;;
        node:querystring) verify_node_builtin "$package_spec" "$module_name" "$types_path" "querystring.d.ts" "TSMBT_NODE_QUERYSTRING_TYPES" ;;
        node:assert) verify_node_builtin "$package_spec" "$module_name" "$types_path" "assert.d.ts" "TSMBT_NODE_ASSERT_TYPES" ;;
        node:util) verify_node_builtin "$package_spec" "$module_name" "$types_path" "util.d.ts" "TSMBT_NODE_UTIL_TYPES" ;;
        node:buffer) verify_node_builtin "$package_spec" "$module_name" "$types_path" "buffer.d.ts" "TSMBT_NODE_BUFFER_TYPES" ;;
        *)
          echo "Unsupported node_builtin corpus entry: $package_spec" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "Unsupported corpus entry kind: $kind" >&2
      exit 1
      ;;
  esac
done < "$corpus_file"

echo "metrics written to $metrics_file"
