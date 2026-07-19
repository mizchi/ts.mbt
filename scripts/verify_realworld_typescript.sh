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
repo_node_modules_root="$repo_root/node_modules"

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
  printf '%s\n' bridge.mbti bridge.js moon.pkg
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

  # bash 3.2 misbehaves with inline regex literals when this function is
  # invoked through process substitution; assign the patterns to variables to
  # bypass that.
  local pat_tuple_array="(Array\[JSValue\]|JSValue\])"
  local pat_namespace_value="(Unsupported export|namespace|Namespace|default|Default|get_|constants|Constants|meta|Meta|rest|Rest|runtime|Runtime|build|Build)"
  local pat_call="<call>"
  local pat_callback_function="(callback|Callback|listener|Listener|handler|Handler|dispatch|Dispatch|reducer|Reducer|action|Action|func|Func|function|Function|component|Component|render|Render|propsAreEqual|Promise|NoParamCallback)"
  local pat_conditional_mapped="(props|Props|children|Children|Ref|Element|ReactNode|LibraryManaged|Intrinsic|JSX|Partial|Readonly|Record|Exclude|Extract|NonNullable|ReturnType|Parameters|DOMAttributes|Key|source|self)"
  local pat_declare_pub_fn="^declare pub fn"

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
    if [[ "$line" =~ $pat_tuple_array ]]; then
      tuple_array_fallback=$((tuple_array_fallback + 1))
    elif [[ "$line" =~ $pat_namespace_value ]]; then
      namespace_value_fallback=$((namespace_value_fallback + 1))
    elif [[ "$line" =~ $pat_call ]]; then
      overload_fallback=$((overload_fallback + 1))
    elif [[ "$line" =~ $pat_callback_function ]]; then
      callback_function_fallback=$((callback_function_fallback + 1))
    elif [[ "$line" =~ $pat_conditional_mapped ]]; then
      conditional_mapped_fallback=$((conditional_mapped_fallback + 1))
    elif [[ "$line" =~ $pat_declare_pub_fn ]]; then
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

  # Budgets recalibrated after the `mizchi/js` removal: the in-house
  # `JSValue` extern type now appears literally in struct field types
  # too (where it previously rendered as `@js.Any` and slipped past the
  # `JSValue`-only metric grep), so historical numbers move up.
  case "$package_spec" in
    clsx) printf '0\n' ;;
    chalk) printf '3\n' ;;
    dotenv) printf '0\n' ;;
    ignore) printf '1\n' ;;
    hono) printf '5\n' ;;
    zod) printf '607\n' ;;
    date-fns) printf '22\n' ;;
    colorette) printf '1\n' ;;
    magic-string) printf '0\n' ;;
    source-map) printf '9\n' ;;
    valibot) printf '291\n' ;;
    immer) printf '16\n' ;;
    execa) printf '5\n' ;;
    preact) printf '7\n' ;;
    react) printf '30\n' ;;
    ms) printf '1\n' ;;
    nanoid) printf '0\n' ;;
    dayjs) printf '3\n' ;;
    qs) printf '2\n' ;;
    yaml) printf '69\n' ;;
    superstruct) printf '56\n' ;;
    eventemitter3) printf '0\n' ;;
    mitt) printf '1\n' ;;
    marked) printf '14\n' ;;
    semver) printf '33\n' ;;
    picomatch) printf '5\n' ;;
    deepmerge) printf '4\n' ;;
    axios) printf '60\n' ;;
    commander) printf '25\n' ;;
    debug) printf '5\n' ;;
    chokidar) printf '3\n' ;;
    pino) printf '8\n' ;;
    lodash) printf '288\n' ;;
    uuid) printf '5\n' ;;
    minimatch) printf '10\n' ;;
    ws) printf '6\n' ;;
    vitest/runtime) printf '6\n' ;;
    playwright) printf '411\n' ;;
    react-router) printf '84\n' ;;
    jose) printf '46\n' ;;
    express) printf '6\n' ;;
    glob) printf '7\n' ;;
    node:sqlite) printf '1\n' ;;
    node:fs) printf '8\n' ;;
    node:path) printf '0\n' ;;
    node:crypto) printf '24\n' ;;
    node:os) printf '0\n' ;;
    node:url) printf '0\n' ;;
    node:querystring) printf '0\n' ;;
    node:assert) printf '23\n' ;;
    node:util) printf '13\n' ;;
    node:buffer) printf '3\n' ;;
    *) printf '0\n' ;;
  esac
}

unsupported_export_budget() {
  local package_spec="$1"

  case "$package_spec" in
    zod) printf '3\n' ;;
    magic-string) printf '1\n' ;;
    valibot) printf '14\n' ;;
    execa) printf '2\n' ;;
    preact) printf '2\n' ;;
    react-router) printf '3\n' ;;
    glob) printf '1\n' ;;
    yaml) printf '3\n' ;;
    superstruct) printf '1\n' ;;
    mitt) printf '1\n' ;;
    marked) printf '3\n' ;;
    minimatch) printf '1\n' ;;

    node:sqlite) printf '2\n' ;;
    node:fs) printf '2\n' ;;
    node:crypto) printf '2\n' ;;
    node:util) printf '2\n' ;;
    node:buffer) printf '1\n' ;;
    *) printf '0\n' ;;
  esac
}

jsvalue_cause_budget() {
  local package_spec="$1"

  # See `jsvalue_function_budget` for the rationale: post-`mizchi/js`-removal
  # numbers include the formerly-hidden `Array[@js.Any]` widening that now
  # renders as `Array[JSValue]` in struct fields and is therefore counted.
  case "$package_spec" in
    clsx) printf '0|0|0|0|0|0|0\n' ;;
    chalk) printf '5|0|0|0|0|4|1\n' ;;
    dotenv) printf '0|0|0|0|0|0|0\n' ;;
    ignore) printf '3|2|0|1|0|0|0\n' ;;
    hono) printf '85|12|6|26|4|28|9\n' ;;
    zod) printf '1901|513|9|524|405|422|28\n' ;;
    date-fns) printf '26|4|5|0|0|15|2\n' ;;
    colorette) printf '1|0|1|0|0|0|0\n' ;;
    magic-string) printf '0|0|0|0|0|0|0\n' ;;
    source-map) printf '17|6|0|7|0|3|1\n' ;;
    valibot) printf '1672|1172|24|14|13|411|38\n' ;;
    immer) printf '23|4|7|2|3|1|6\n' ;;
    execa) printf '17|2|0|4|1|0|10\n' ;;
    preact) printf '48|12|1|4|14|17|0\n' ;;
    react) printf '129|43|8|24|34|14|6\n' ;;
    ms) printf '1|0|0|0|0|0|1\n' ;;
    nanoid) printf '0|0|0|0|0|0|0\n' ;;
    dayjs) printf '3|0|1|0|1|0|1\n' ;;
    qs) printf '8|2|1|0|0|0|5\n' ;;
    yaml) printf '179|34|7|84|0|20|34\n' ;;
    superstruct) printf '83|4|0|15|0|59|5\n' ;;
    eventemitter3) printf '16|0|0|0|5|6|5\n' ;;
    mitt) printf '10|4|0|2|3|1|0\n' ;;
    marked) printf '57|10|0|0|20|13|14\n' ;;
    semver) printf '33|0|30|2|0|0|1\n' ;;
    picomatch) printf '11|6|4|0|0|0|1\n' ;;
    deepmerge) printf '14|8|0|2|0|3|1\n' ;;
    axios) printf '188|78|4|18|1|54|33\n' ;;
    commander) printf '26|0|0|10|3|3|10\n' ;;
    debug) printf '19|6|0|1|0|12|0\n' ;;
    chokidar) printf '3|0|0|1|0|0|2\n' ;;
    pino) printf '51|38|4|1|0|4|4\n' ;;
    lodash) printf '1643|444|120|252|49|771|7\n' ;;
    uuid) printf '5|0|5|0|0|0|0\n' ;;
    minimatch) printf '10|0|0|2|0|3|5\n' ;;
    ws) printf '43|28|0|3|2|4|6\n' ;;
    vitest/runtime) printf '64|35|2|3|6|18|0\n' ;;
    playwright) printf '1336|196|0|85|885|170|0\n' ;;
    react-router) printf '347|164|25|30|39|67|22\n' ;;
    jose) printf '67|18|1|15|11|10|12\n' ;;
    express) printf '6|0|0|0|0|2|4\n' ;;
    glob) printf '17|6|0|1|0|2|8\n' ;;
    node:sqlite) printf '3|2|0|0|0|1|0\n' ;;
    node:fs) printf '34|8|0|0|0|26|0\n' ;;
    node:path) printf '0|0|0|0|0|0|0\n' ;;
    node:crypto) printf '102|24|3|18|1|56|0\n' ;;
    node:os) printf '0|0|0|0|0|0|0\n' ;;
    node:url) printf '0|0|0|0|0|0|0\n' ;;
    node:querystring) printf '0|0|0|0|0|0|0\n' ;;
    node:assert) printf '29|6|4|2|13|0|4\n' ;;
    node:util) printf '25|12|8|1|1|2|1\n' ;;
    node:buffer) printf '9|6|0|3|0|0|0\n' ;;
    *) printf '0|0|0|0|0|0|0\n' ;;
  esac
}

realworld_fallback_policy() {
  local package_spec="$1"

  case "$package_spec" in
    clsx | node:path | node:os | node:url | node:querystring | node:buffer)
      printf 'zero-target|Keep public JSValue surface at zero; any fallback is a regression.\n'
      ;;
    node:crypto)
      printf 'naturalize-target|Generic key/cert option types (e.g. `PublicKeyExportOptions<%c>`) widen literal generic args to JSValue; the rest of the surface is naturalised.\n' "'"
      ;;
    hono)
      printf 'naturalize-target|Reduce generic context/router fallbacks while keeping route handlers and response helpers natural.\n'
      ;;
    react-router)
      printf 'naturalize-target|Reduce route/path utility overload and option-object fallbacks; keep typed navigation helpers usable from MoonBit.\n'
      ;;
    jose)
      printf 'naturalize-target|Reduce builder option and compact JWS/JWT overload fallbacks around the smoke-tested APIs.\n'
      ;;
    glob)
      printf 'naturalize-target|Reduce pattern/options namespace fallbacks for common sync glob calls.\n'
      ;;
    node:assert | node:util)
      printf 'naturalize-target|Shrink remaining Node built-in overload/unknown fallbacks toward zero for the common API surface.\n'
      ;;
    date-fns | magic-string | source-map | yaml | marked | axios | pino | lodash | ws | node:sqlite | node:fs)
      printf 'naturalize-target|Keep reducing fallback around finite option bags, tuple results, and class/value helper APIs.\n'
      ;;
    zod | valibot)
      printf 'budgeted-fallback|Schema/parser generics are intentionally smoke-tested and budgeted, not treated as naturally typed MoonBit APIs yet.\n'
      ;;
    preact)
      printf 'budgeted-fallback|JSX/component/children generics are intentionally budgeted until a dedicated JSX/component binding layer exists.\n'
      ;;
    react)
      printf 'budgeted-fallback|Component layer v1 (element_of_component + use_state_typed, SSR smoke-tested); remaining JSX/attribute generics stay budgeted.\n'
      ;;
    playwright)
      printf 'budgeted-fallback|Large event/callback-heavy API is smoke-tested; only selected launch/device/options surfaces are naturalization targets.\n'
      ;;
    chalk | dotenv | ignore | colorette | immer | execa | vitest/runtime | express | ms | nanoid | dayjs | qs | superstruct | eventemitter3 | mitt | semver | picomatch | deepmerge | commander | debug | chokidar | uuid | minimatch)
      printf 'low-fallback-maintain|Current fallback is small and explicitly budgeted; naturalize only when a real smoke use case needs it.\n'
      ;;
    *)
      printf 'unclassified|Add an explicit fallback policy before accepting this package into the real-world corpus.\n'
      ;;
  esac
}

append_fallback_policy_report() {
  {
    printf '\n## Fallback Policy\n\n'
    printf 'This table separates practical naturalization targets from intentionally budgeted fallback packages. New corpus entries must be classified here before their `JSValue` budget is accepted.\n\n'
    printf '| package | policy | action |\n'
    printf '| --- | --- | --- |\n'
  } >> "$metrics_file"

  local kind
  local package_spec
  local module_name
  local types_path
  local policy
  local action

  while IFS='|' read -r kind package_spec module_name types_path; do
    if [ -z "${kind:-}" ] || [[ "$kind" == \#* ]]; then
      continue
    fi
    IFS='|' read -r policy action < <(realworld_fallback_policy "$package_spec")
    if [ "$policy" = "unclassified" ]; then
      echo "Missing fallback policy classification for $package_spec" >&2
      exit 1
    fi
    printf '| %s | %s | %s |\n' \
      "$package_spec" \
      "$policy" \
      "$action" >> "$metrics_file"
  done < "$corpus_file"
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

package_root_for_spec() {
  local package_spec="$1"

  if [[ "$package_spec" == @* ]]; then
    local scope name rest
    IFS=/ read -r scope name rest <<< "$package_spec"
    printf '%s/%s\n' "$scope" "$name"
  else
    printf '%s\n' "${package_spec%%/*}"
  fi
}

node_modules_root_for_spec() {
  local package_spec="$1"
  local package_root
  package_root="$(package_root_for_spec "$package_spec")"

  if [ -e "$node_modules_root/$package_root" ]; then
    printf '%s\n' "$node_modules_root"
    return
  fi
  if [ -d "$repo_node_modules_root" ] &&
    [ -e "$repo_node_modules_root/$package_root" ]; then
    printf '%s\n' "$repo_node_modules_root"
    return
  fi

  echo "Missing package '$package_root' for '$package_spec' in $node_modules_root or $repo_node_modules_root" >&2
  exit 1
}

ensure_project_node_modules() {
  local project="$1"
  local selected_node_modules_root="$2"

  if [ -L "$project/node_modules" ]; then
    local current_target
    current_target="$(readlink "$project/node_modules")"
    if [ "$current_target" != "$selected_node_modules_root" ]; then
      rm "$project/node_modules"
    fi
  elif [ -e "$project/node_modules" ]; then
    echo "Expected $project/node_modules to be a symlink" >&2
    exit 1
  fi

  if [ ! -e "$project/node_modules" ]; then
    ln -s "$selected_node_modules_root" "$project/node_modules"
  fi
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
extern "js" fn realworld_hono_options() -> HonoOptions[Env] =
  #| () => ({ strict: true })

extern "js" fn realworld_hono_resolve(r : Response) -> Promise[Response] =
  #| (r) => Promise.resolve(r)

extern "js" fn realworld_hono_key(s : String) -> Key =
  #| (s) => s

extern "js" fn realworld_hono_str(v : JSValue) -> String =
  #| (v) => String(v)

extern "js" fn realworld_hono_roundtrip(app : Hono[JSValue, JSValue, JSValue]) -> Unit =
  #| (app) => {
  #|   globalThis.__tsmbt_pending = (async () => {
  #|     const ok = await app.fetch(new Request("http://localhost/"));
  #|     if (ok.status !== 200 || (await ok.text()) !== "hello from moonbit") {
  #|       console.error("hono sync route failed"); process.exit(1);
  #|     }
  #|     const a = await app.fetch(new Request("http://localhost/async"));
  #|     if (a.status !== 200 || (await a.text()) !== "async moonbit") {
  #|       console.error("hono async route failed"); process.exit(1);
  #|     }
  #|     const m = await app.fetch(new Request("http://localhost/mw"));
  #|     if (m.status !== 200 || (await m.text()) !== "from middleware") {
  #|       console.error("hono middleware failed"); process.exit(1);
  #|     }
  #|     const missing = await app.fetch(new Request("http://localhost/nope"));
  #|     if (missing.status !== 404) { console.error("hono 404 failed"); process.exit(1); }
  #|   })();
  #| }

fn realworld_hono_handler(
  c : Context[JSValue, JSValue, JSValue],
) -> Response {
  c.text("hello from moonbit", None, None)
}

fn realworld_hono_async_handler(
  c : Context[JSValue, JSValue, JSValue],
) -> Promise[Response] {
  realworld_hono_resolve(c.text("async moonbit", None, None))
}

fn realworld_hono_mw(
  c : Context[JSValue, JSValue, JSValue],
  next : () -> Promise[Unit],
) -> Promise[Unit] {
  c.set(realworld_hono_key("who"), unsafeCast("from middleware"))
  next()
}

fn realworld_hono_mw_handler(
  c : Context[JSValue, JSValue, JSValue],
) -> Response {
  c.text(realworld_hono_str(c.get(realworld_hono_key("who"))), None, None)
}

test "real-world hono bridge smoke" {
  let app : Hono[JSValue, JSValue, JSValue] = new_hono(
    Some(realworld_hono_options()),
  )
  app.use_middleware(None, realworld_hono_mw)
  let _ = app.get("/", realworld_hono_handler)
  app.get_async("/async", realworld_hono_async_handler)
  let _ = app.get("/mw", realworld_hono_mw_handler)
  realworld_hono_roundtrip(app)
}
EOF
      ;;
    zod)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world zod bridge smoke" {
  let _ = number(None)
  let _ = boolean(None)
  // Concrete schemas expose the flattened ZodType surface directly.
  let s = string(None)
  if !s.safeParse(unsafeCast("hello"), None).success {
    abort("expected zod safeParse success")
  }
  if s.safeParse(unsafeCast(42), None).success {
    abort("expected zod safeParse failure")
  }
  let email = string(None).email(None)
  if !email.safeParse(unsafeCast("a@b.co"), None).success {
    abort("expected zod email success")
  }
  if email.safeParse(unsafeCast("nope"), None).success {
    abort("expected zod email failure")
  }
  // Generic owners (ZodObject) reach the surface via the as_schema upcast;
  // the shape is built with the loose_shape_from_pairs module hook.
  let shape = loose_shape_from_pairs(
    ["name"],
    [unsafeCast(string(None))],
  )
  let obj = as_schema(object(Some(shape), None))
  if obj.safeParse(unsafeCast("not an object"), None).success {
    abort("expected zod object failure")
  }
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
  assert_eq(s.to_string(), "hello")
  let _ = s.append("!")
  assert_eq(s.to_string(), "hello!")
}
EOF
      ;;
    source_map)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world source-map bridge smoke" {
  let generator = new_source_map_generator(None)
  if generator.to_string().length() == 0 {
    abort("expected source map generator output")
  }
}
EOF
      ;;
    valibot)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_valibot_success(r : JSValue) -> Bool =
  #| (r) => r.success === true

test "real-world valibot bridge smoke" {
  let _ = number()
  let _ = boolean()
  let _ = uuid()
  let s : BaseSchema[JSValue, JSValue, BaseIssue[JSValue]] = unsafeCast(string())
  if !realworld_valibot_success(safeParse(s, unsafeCast("hello"), None)) {
    abort("expected valibot safeParse success")
  }
  if realworld_valibot_success(safeParse(s, unsafeCast(42), None)) {
    abort("expected valibot safeParse failure")
  }
  let piped : BaseSchema[JSValue, JSValue, BaseIssue[JSValue]] = unsafeCast(
    pipe(s, [unsafeCast(minLength(3.0))]),
  )
  if !realworld_valibot_success(safeParse(piped, unsafeCast("abcd"), None)) {
    abort("expected valibot pipe success")
  }
  if realworld_valibot_success(safeParse(piped, unsafeCast("ab"), None)) {
    abort("expected valibot pipe failure")
  }
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
    react)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_react_vnode(
  elem : DetailedReactHTMLElement[
    InputHTMLAttributes[HTMLInputElement],
    HTMLInputElement,
  ],
) -> VNode =
  #| (e) => e

extern "js" fn realworld_render_to_string(element : JSValue) -> String =
  #| (element) => require("react-dom/server").renderToString(element)

test "real-world react bridge smoke" {
  let elem = createElement("input", None, [])
  if !isValidElement(realworld_react_vnode(elem)) {
    abort("expected a valid react element")
  }
  let _ = createRef()
  if !get_version().has_prefix("19") {
    abort("unexpected react version")
  }
}

test "real-world react component layer smoke" {
  let counter = fn(_props : JSValue) -> JSValue {
    let (count, _set_count) = use_state_typed(41)
    unsafeCast(createElement("div", None, [unsafeCast(count)]))
  }
  let element = element_of_component(counter, None, [])
  assert_eq(realworld_render_to_string(element), "<div>41</div>")
}
EOF
      ;;
    ms)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world ms bridge smoke" {
  assert_eq(default(60000, None), "1m")
}
EOF
      ;;
    nanoid)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world nanoid bridge smoke" {
  assert_eq(nanoid(Some(10)).length(), 10)
  assert_eq(get_url_alphabet().length(), 64)
}
EOF
      ;;
    dayjs)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_dayjs_format(d : Dayjs_Dayjs) -> String =
  #| (d) => d.format("YYYY")

test "real-world dayjs bridge smoke" {
  let d = default(None)
  assert_eq(realworld_dayjs_format(d).length(), 4)
}
EOF
      ;;
    qs)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_qs_obj() -> JSValue =
  #| () => ({ a: "1" })

test "real-world qs bridge smoke" {
  let parsed = parse("a=1&b=2", None)
  if parsed.op_get("a") is None {
    abort("expected parsed key a")
  }
  assert_eq(stringify(realworld_qs_obj(), None), "a=1")
}
EOF
      ;;
    yaml)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world yaml bridge smoke" {
  let doc = parse("a: 1", None)
  assert_eq(stringify(doc, None), "a: 1\n")
}
EOF
      ;;
    superstruct)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_ss_string_value() -> JSValue =
  #| () => "hello"

test "real-world superstruct bridge smoke" {
  let s : Struct[JSValue, JSValue] = unsafeCast(string())
  assert_(realworld_ss_string_value(), s, None)
  let _ = validate(realworld_ss_string_value(), s, None)
}
EOF
      ;;
    eventemitter3)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_ee3_event() -> EventEmitter_EventNames =
  #| () => "ping"

test "real-world eventemitter3 bridge smoke" {
  let ee : Default[JSValue, JSValue] = new_default()
  let listener : EventEmitter_EventListener = unsafeCast(fn(_args : Array[JSValue]) -> Unit {  })
  let _ = ee.on(realworld_ee3_event(), listener, None)
  assert_eq(ee.listener_count(realworld_ee3_event()), 1)
}
EOF
      ;;
    mitt)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_mitt_event() -> JSValue =
  #| () => "ping"

extern "js" fn realworld_mitt_counter() -> Ref[Int] =
  #| () => ({ val: 0 })

extern "js" fn realworld_mitt_handler(counter : Ref[Int]) -> EmitterOnArg1Callback =
  #| (counter) => () => { counter.val++ }

test "real-world mitt bridge smoke" {
  let emitter = default(None)
  let counter = realworld_mitt_counter()
  emitter.on(realworld_mitt_event(), realworld_mitt_handler(counter))
  emitter.emit(realworld_mitt_event(), realworld_mitt_event())
  assert_eq(counter.val, 1)
}
EOF
      ;;
    marked)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world marked bridge smoke" {
  let html = marked_string_marked_options_optional("# hello", None)
  let rendered : String = unsafeCast(html)
  if !rendered.contains("<h1>hello</h1>") {
    abort("unexpected marked output: \{rendered}")
  }
}
EOF
      ;;
    semver)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world semver bridge smoke" {
  assert_eq(valid(Some(unsafeCast("1.2.3")), None), Some("1.2.3"))
  assert_eq(clean(" 1.2.3 ", None), Some("1.2.3"))
  assert_eq(major(unsafeCast("2.4.6"), None), 2)
}
EOF
      ;;
    picomatch)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_pm_match(m : Picomatch_Matcher, input : String) -> Bool =
  #| (m, input) => m(input)

test "real-world picomatch bridge smoke" {
  let matcher = default(unsafeCast("*.ts"), None, None)
  if !realworld_pm_match(matcher, "a.ts") {
    abort("expected *.ts to match a.ts")
  }
  if realworld_pm_match(matcher, "a.js") {
    abort("expected *.ts not to match a.js")
  }
}
EOF
      ;;
    deepmerge)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_dm_obj_a() -> Partial =
  #| () => ({ a: 1 })

extern "js" fn realworld_dm_obj_b() -> Partial =
  #| () => ({ b: 2 })

extern "js" fn realworld_dm_has(v : JSValue, key : String) -> Bool =
  #| (v, key) => Object.prototype.hasOwnProperty.call(v, key)

test "real-world deepmerge bridge smoke" {
  let merged = default(realworld_dm_obj_a(), realworld_dm_obj_b(), None)
  if !realworld_dm_has(merged, "a") || !realworld_dm_has(merged, "b") {
    abort("expected merged object with both keys")
  }
}
EOF
      ;;
    axios)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_axios_config() -> AxiosRequestConfig[JSValue] =
  #| () => ({ url: "/users/1", baseURL: "https://example.test" })

test "real-world axios bridge smoke" {
  let axios_core : Axios = unsafeCast(get_default())
  let uri = axios_core.get_uri(Some(realworld_axios_config()))
  assert_eq(uri, "https://example.test/users/1")
  let _ = create(None)
}
EOF
      ;;
    commander)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_cmd_debug_flag(opts : OptionValues) -> Bool =
  #| (opts) => opts.debug === true

test "real-world commander bridge smoke" {
  let cmd = new_command(Some("app"))
    .option("-d, --debug", Some("enable debug"), None)
    .parse(Some(["node", "app", "--debug"]), None)
  if !realworld_cmd_debug_flag(cmd.opts()) {
    abort("expected --debug flag to parse")
  }
}
EOF
      ;;
    debug)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world debug bridge smoke" {
  let dbg : Debug = unsafeCast(get_default())
  dbg.enable("tsmbt:*")
  if !dbg.enabled("tsmbt:probe") {
    abort("expected namespace to be enabled")
  }
  let _ = dbg.disable()
  let logger = dbg._call_("tsmbt:probe")
  let _ = logger
}
EOF
      ;;
    chokidar)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world chokidar bridge smoke" {
  let watcher = new_fswatcher(None)
  let _ = watcher.close()
}
EOF
      ;;
    pino)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_pino_options() -> Pino_LoggerOptions =
  #| () => ({ level: "warn" })

extern "js" fn realworld_pino_level(logger : Pino_Logger) -> String =
  #| (logger) => logger.level

test "real-world pino bridge smoke" {
  let logger = default(realworld_pino_options(), None)
  assert_eq(realworld_pino_level(logger), "warn")
}
EOF
      ;;
    lodash)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_lodash_list() -> ArrayLike =
  #| () => [1, 2, 3, 4, 5]

test "real-world lodash bridge smoke" {
  assert_eq(camelCase(Some("hello world")), "helloWorld")
  assert_eq(kebabCase(Some("helloWorld")), "hello-world")
  let chunks = chunk(Some(realworld_lodash_list()), Some(2))
  assert_eq(chunks.length(), 3)
}
EOF
      ;;
    uuid)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_uuid_absent() -> JSValue =
  #| () => undefined

test "real-world uuid bridge smoke" {
  let id = v4_version4_options_optional_undefined_number_optional(
    None,
    realworld_uuid_absent(),
    None,
  )
  assert_eq(id.length(), 36)
  if !validate(unsafeCast(id)) {
    abort("expected generated uuid to validate")
  }
  assert_eq(version(id), 4)
  if validate(unsafeCast("not-a-uuid")) {
    abort("expected invalid string to fail validation")
  }
}
EOF
      ;;
    minimatch)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world minimatch bridge smoke" {
  if !minimatch("bar.foo", "*.foo", None) {
    abort("expected *.foo to match bar.foo")
  }
  if minimatch("bar.foo", "*.bar", None) {
    abort("expected *.bar not to match bar.foo")
  }
  let is_foo = filter("*.foo", None)
  if !is_foo("bar.foo") {
    abort("expected filter matcher to match")
  }
}
EOF
      ;;
    ws)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_ws_server_options() -> WebSocketServerOptions[JSValue, JSValue] =
  #| () => ({ noServer: true })

test "real-world ws bridge smoke" {
  let server : Server[JSValue, JSValue] = new_server(
    Some(realworld_ws_server_options()),
    None,
  )
  server.close(None)
}
EOF
      ;;
    vitest_runtime)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_vitest_global() -> JSValue =
  #| () => globalThis

extern "js" fn realworld_vitest_options() -> StringRecordOfAny =
  #| () => ({})

extern "js" fn realworld_vitest_object() -> JSValue =
  #| () => ({})

test "real-world vitest environments bridge smoke" {
  let envs = get_builtin_environments()
  assert_eq(envs.node.name, "node")
  assert_eq(envs.jsdom.name, "jsdom")
  let global = realworld_vitest_global()
  let options = realworld_vitest_options()
  let _ = envs.node.setup(global, options)
  match envs.node.setupVM {
    Some(setup_vm) => {
      let _ = setup_vm(options)
    }
    None => ()
  }
  let populated = populateGlobal(
    realworld_vitest_object(),
    realworld_vitest_object(),
    None,
  )
  let _ = populated.keys
}
EOF
      ;;
    playwright)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world playwright bridge smoke" {
  // Compile-only smoke: exercise the public surface so the generated
  // package builds. Do not invoke the playwright runtime — it depends on
  // pre-installed browser binaries we don't ship in CI, and the lazily
  // initialised globals throw `Cannot read properties of undefined` when
  // accessed without the npm postinstall step having run.
  let _launch_options = LaunchOptions::{
    args: Some(["--disable-dev-shm-usage"]),
    artifactsDir: None,
    channel: None,
    chromiumSandbox: Some(false),
    downloadsPath: None,
    env: None,
    executablePath: None,
    firefoxUserPrefs: None,
    handleSIGHUP: None,
    handleSIGINT: None,
    handleSIGTERM: None,
    headless: Some(true),
    ignoreDefaultArgs: None,
    logger: None,
    proxy: None,
    slowMo: Some(0.0),
    timeout: Some(1000.0),
    tracesDir: None,
  }
  let _ = _launch_options
}
EOF
      ;;
    react_router)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world react-router bridge smoke" {
  let path = PathPartial::{
    pathname: Some("/docs"),
    search: None,
    hash: None,
  }
  assert_eq(createPath(path), "/docs")
  let parsed = parsePath("/docs?tab=api#top")
  assert_eq(parsed.pathname, Some("/docs"))
  assert_eq(generatePath("/docs", None), "/docs")
  let full_path = PathPartial::{
    pathname: Some("/docs"),
    search: Some("?tab=api"),
    hash: Some("#top"),
  }
  assert_eq(createPath(full_path), "/docs?tab=api#top")
  assert_eq(
    generate_path_params("/users/:id", params_from_pairs(["id"], ["42"])),
    "/users/42",
  )
  let resolved = resolvePath(to_from_string("../api"), Some("/docs/reference"))
  assert_eq(resolved.pathname, "/docs/api")
  assert_eq(resolved.search, "")
  assert_eq(resolved.hash, "")
}
EOF
      ;;
    jose)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world jose bridge smoke" {
  let jwt = new_unsecured_jwt(None)
  let _ = jwt.set_issuer("https://issuer.example")
  let _ = jwt.set_subject("user-42")
  let _ = jwt.set_jti("token-1")
  let _ = unsecured_jwt_set_issued_at_double(jwt, 1710000000.0)
  let encoded = jwt.encode()
  let decoded = unsecured_jwt_decode(encoded, None)
  let _ = decoded.header
  let _ = decodeJwt(encoded)
  let signer = new_sign_jwt(None)
  let _ = signer.set_issuer("https://issuer.example")
  let _ = signer.set_subject("user-42")
  let _ = signer.set_jti("token-1")
  let _ = sign_jwt_set_issued_at_double(signer, 1710000000.0)
}
EOF
      ;;
    express)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world express bridge smoke" {
  let options = RouterOptions::{
    caseSensitive: Some(true),
    mergeParams: Some(true),
    strict: Some(false),
  }
  let _ = router(Some(options))
  let _ = get_json()
  let _ = get_urlencoded()
  let _ = get_static()
  let _ = get_request()
  let _ = get_response()
  let _ = default()
}
EOF
      ;;
    glob)
      cat > "$out/bridge_test.mbt" <<'EOF'
fn realworld_glob_options() -> GlobOptions {
  GlobOptions::{
    absolute: Some(false),
    allowWindowsEscape: None,
    cwd: None,
    dot: Some(false),
    dotRelative: None,
    follow: Some(false),
    ignore: None,
    magicalBraces: Some(false),
    mark: None,
    matchBase: None,
    maxDepth: Some(4.0),
    nobrace: None,
    nocase: None,
    nodir: Some(true),
    noext: None,
    noglobstar: None,
    platform: None,
    realpath: None,
    root: None,
    scurry: None,
    stat: None,
    signal: None,
    windowsPathsNoEscape: Some(false),
    withFileTypes: Some(false),
    fs: None,
    debug: None,
    posix: None,
    includeChildMatches: None,
    braceExpandMax: None,
  }
}

test "real-world glob bridge smoke" {
  let matches = globSync_string_glob_options_with_file_types_unset_optional(
    "*.json",
    None,
  )
  if matches.length() == 0 {
    abort("expected json files in generated project")
  }
  let opts = MinimatchOptionsPickWindowsPathsNoEscapeMagicalBraces::{
    windowsPathsNoEscape: Some(false),
    magicalBraces: Some(false),
  }
  assert_eq(escape("src/*.mbt", Some(opts)), "src/\\*.mbt")
  assert_eq(unescape("src/\\*.mbt", Some(opts)), "src/*.mbt")
  if !has_magic("src/*.mbt", Some(realworld_glob_options())) {
    abort("expected glob pattern to have magic")
  }
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
    limits: None,
  }
}

extern "js" fn realworld_node_sqlite_params() -> Array[SQLInputValue] =
  #| () => []

extern "js" fn realworld_node_sqlite_row_value(row : StringRecordOfSqloutputValue) -> String =
  #| (row) => row.value

test "real-world node:sqlite bridge smoke" {
  let db = new_database_sync(
    realworld_node_sqlite_memory_path(),
    Some(realworld_node_sqlite_options()),
  )
  assert_true(db.get_database_sync_is_open())
  db.exec("CREATE TABLE data (key INTEGER PRIMARY KEY, value TEXT) STRICT")
  db.exec("INSERT INTO data (key, value) VALUES (1, 'hello')")
  db.exec("UPDATE data SET value = 'world' WHERE key = 1")
  let stmt = db.prepare("SELECT value FROM data WHERE key = 1", None)
  match stmt.get(realworld_node_sqlite_params()) {
    Some(row) => assert_eq(realworld_node_sqlite_row_value(row), "world")
    None => abort("expected the prepared statement to return a row")
  }
  db.close()
  assert_false(db.get_database_sync_is_open())
}
EOF
      ;;
    node_fs)
      cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn realworld_node_fs_to_string(data : NonSharedBuffer) -> String =
  #| (data) => data.toString("utf8")

test "real-world node:fs bridge smoke" {
  let path = path_like_from_string("node-fs-test.txt")
  let file = path_or_file_descriptor_from_path_like(path)
  if existsSync(path) {
    unlinkSync(path)
  }
  writeFileSync(file, "hello from moonbit", None)
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
test "real-world node:assert bridge smoke" {
  assert_ok_bool(true, None)
  assert_equal_double(1.0, 1.0, None)
  assert_strict_equal_string("ok", "ok", None)
  assert_not_equal_double(1.0, 2.0, None)
  assert_not_strict_equal_string("ok", "ng", None)
}
EOF
      ;;
    node_util)
      cat > "$out/bridge_test.mbt" <<'EOF'
test "real-world node:util bridge smoke" {
  assert_eq(toUSVString("ok"), "ok")
  assert_eq(stripVTControlCharacters("plain"), "plain")
  if diff_string("alpha", "alps").length() == 0 {
    abort("expected util.diff string wrapper to produce chunks")
  }
  assert_true(is_array_string_array(["ok"]))
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
extern "js" fn realworld_hono_options() -> @sut.HonoOptions[@sut.Env] =
  #| () => ({ strict: true })

fn realworld_hono_handler(
  c : @sut.Context[@sut.JSValue, @sut.JSValue, @sut.JSValue],
) -> @sut.Response {
  c.text("hello from moonbit", None, None)
}

fn main {
  let app : @sut.Hono[@sut.JSValue, @sut.JSValue, @sut.JSValue] = @sut.new_hono(
    Some(realworld_hono_options()),
  )
  let _ = app.get("/", realworld_hono_handler)
}
EOF
      ;;
    zod)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let _ = @sut.number(None)
  let _ = @sut.boolean(None)
  let s = @sut.string(None)
  if !s.safeParse(@sut.unsafeCast("hello"), None).success {
    abort("expected zod safeParse success")
  }
  if s.safeParse(@sut.unsafeCast(42), None).success {
    abort("expected zod safeParse failure")
  }
  let obj = @sut.as_schema(@sut.object(None, None))
  if obj.safeParse(@sut.unsafeCast("nope"), None).success {
    abort("expected zod object failure")
  }
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
  if s.to_string() != "hello" {
    abort("unexpected initial magic-string output")
  }
  let _ = s.append("!")
  if s.to_string() != "hello!" {
    abort("unexpected appended magic-string output")
  }
}
EOF
      ;;
    source_map)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let generator = @sut.new_source_map_generator(None)
  if generator.to_string().length() == 0 {
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
    react)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_react_vnode(
  elem : @sut.DetailedReactHTMLElement[
    @sut.InputHTMLAttributes[@sut.HTMLInputElement],
    @sut.HTMLInputElement,
  ],
) -> @sut.VNode =
  #| (e) => e

fn main {
  let elem = @sut.createElement("input", None, [])
  if !@sut.isValidElement(realworld_react_vnode(elem)) {
    abort("expected a valid react element")
  }
  let counter = fn(_props : @sut.JSValue) -> @sut.JSValue {
    let (count, _set_count) = @sut.use_state_typed(41)
    @sut.unsafeCast(@sut.createElement("div", None, [@sut.unsafeCast(count)]))
  }
  let _ = @sut.element_of_component(counter, None, [])
}
EOF
      ;;
    ms)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.default(60000, None) != "1m" {
    abort("unexpected ms output")
  }
}
EOF
      ;;
    nanoid)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.nanoid(Some(10)).length() != 10 {
    abort("unexpected nanoid length")
  }
  // Returned-function option unwrap: the closure customAlphabet returns
  // takes `Double?`; a MoonBit `None` must reach JS as `undefined` so the
  // default size (8) fires — the unwrapped `null` used to yield "".
  let hex_id = @sut.customAlphabet("0123456789abcdef", Some(8))
  if hex_id(None).length() != 8 {
    abort("customAlphabet returned-function lost its default size")
  }
  if hex_id(Some(12)).length() != 12 {
    abort("customAlphabet returned-function ignored explicit size")
  }
}
EOF
      ;;
    dayjs)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_dayjs_format(d : @sut.Dayjs_Dayjs) -> String =
  #| (d) => d.format("YYYY")

fn main {
  if realworld_dayjs_format(@sut.default(None)).length() != 4 {
    abort("unexpected dayjs format")
  }
}
EOF
      ;;
    qs)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let parsed = @sut.parse("a=1&b=2", None)
  if parsed.op_get("a") is None {
    abort("expected parsed key a")
  }
}
EOF
      ;;
    yaml)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let doc = @sut.parse("a: 1", None)
  if @sut.stringify(doc, None) != "a: 1\n" {
    abort("unexpected yaml roundtrip")
  }
}
EOF
      ;;
    superstruct)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_ss_string_value() -> @sut.JSValue =
  #| () => "hello"

fn main {
  let s : @sut.Struct[@sut.JSValue, @sut.JSValue] = @sut.unsafeCast(@sut.string())
  @sut.assert_(realworld_ss_string_value(), s, None)
}
EOF
      ;;
    eventemitter3)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_ee3_event() -> @sut.EventEmitter_EventNames =
  #| () => "ping"

fn main {
  let ee : @sut.Default[@sut.JSValue, @sut.JSValue] = @sut.new_default()
  let listener : @sut.EventEmitter_EventListener = @sut.unsafeCast(fn(_args : Array[@sut.JSValue]) -> Unit {  })
  let _ = ee.on(realworld_ee3_event(), listener, None)
  if ee.listener_count(realworld_ee3_event()) != 1 {
    abort("unexpected listener count")
  }
}
EOF
      ;;
    mitt)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_mitt_event() -> @sut.JSValue =
  #| () => "ping"

extern "js" fn realworld_mitt_counter() -> Ref[Int] =
  #| () => ({ val: 0 })

extern "js" fn realworld_mitt_handler(counter : Ref[Int]) -> @sut.EmitterOnArg1Callback =
  #| (counter) => () => { counter.val++ }

fn main {
  let emitter = @sut.default(None)
  let counter = realworld_mitt_counter()
  emitter.on(realworld_mitt_event(), realworld_mitt_handler(counter))
  emitter.emit(realworld_mitt_event(), realworld_mitt_event())
  if counter.val != 1 {
    abort("unexpected mitt counter")
  }
}
EOF
      ;;
    marked)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let html = @sut.marked_string_marked_options_optional("# hello", None)
  let rendered : String = @sut.unsafeCast(html)
  if !rendered.contains("<h1>hello</h1>") {
    abort("unexpected marked output")
  }
}
EOF
      ;;
    semver)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.valid(Some(@sut.unsafeCast("1.2.3")), None) != Some("1.2.3") {
    abort("unexpected semver valid")
  }
  if @sut.major(@sut.unsafeCast("2.4.6"), None) != 2 {
    abort("unexpected semver major")
  }
}
EOF
      ;;
    picomatch)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_pm_match(m : @sut.Picomatch_Matcher, input : String) -> Bool =
  #| (m, input) => m(input)

fn main {
  let matcher = @sut.default(@sut.unsafeCast("*.ts"), None, None)
  if !realworld_pm_match(matcher, "a.ts") {
    abort("expected *.ts to match a.ts")
  }
}
EOF
      ;;
    deepmerge)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_dm_obj_a() -> @sut.Partial =
  #| () => ({ a: 1 })

extern "js" fn realworld_dm_obj_b() -> @sut.Partial =
  #| () => ({ b: 2 })

extern "js" fn realworld_dm_has(v : @sut.JSValue, key : String) -> Bool =
  #| (v, key) => Object.prototype.hasOwnProperty.call(v, key)

fn main {
  let merged = @sut.default(realworld_dm_obj_a(), realworld_dm_obj_b(), None)
  if !realworld_dm_has(merged, "a") || !realworld_dm_has(merged, "b") {
    abort("expected merged object with both keys")
  }
}
EOF
      ;;
    axios)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_axios_config() -> @sut.AxiosRequestConfig[@sut.JSValue] =
  #| () => ({ url: "/users/1", baseURL: "https://example.test" })

fn main {
  let axios_core : @sut.Axios = @sut.unsafeCast(@sut.get_default())
  if axios_core.get_uri(Some(realworld_axios_config())) != "https://example.test/users/1" {
    abort("unexpected axios uri")
  }
  // Promise consumption layer: axios.all resolves locally (no network),
  // and the callbacks run before node drains the event loop, so a wrong
  // count aborts the smoke with a non-zero exit.
  let vals : Array[@sut.JSValue] = [
    @sut.JSValue::from_int(1),
    @sut.JSValue::from_int(2),
    @sut.JSValue::from_int(3),
  ]
  @sut.all(vals)
  .map(fn(items : Array[@sut.JSValue]) -> Int { items.length() })
  .then_catch(
    fn(n : Int) { if n != 3 { abort("unexpected axios.all count") } },
    fn(_err) { abort("axios.all rejected") },
  )
  // MoonBit-native async integration: `.wait()` awaits inside an async
  // fn, and a rejected promise (connection refused on a closed port)
  // surfaces as the catchable JsRejection error.
  async fn smoke_async() -> Unit {
    let awaited = @sut.all(vals).wait()
    if awaited.length() != 3 {
      abort("unexpected awaited axios.all count")
    }
    let core : @sut.Axios = @sut.unsafeCast(@sut.get_default())
    let mut rejected = false
    let resp : @sut.JSValue = core
      .get("http://127.0.0.1:1/unreachable", None)
      .wait() catch {
      @sut.JsRejection(_) => {
        rejected = true
        @sut.unsafeCast(0)
      }
      _ => @sut.unsafeCast(0)
    }
    ignore(resp)
    if !rejected {
      abort("expected axios rejection to surface as JsRejection")
    }
  }

  @sut.run_async(smoke_async)
  // Typed JSValue constructors: object_from_pairs builds a heterogeneous
  // config object without unsafeCast.
  let probe = @sut.JSValue::object_from_pairs([
    ("name", @sut.JSValue::from_string("tsmbt")),
    ("count", @sut.JSValue::from_int(42)),
  ])
  ignore(probe)
}
EOF
      ;;
    commander)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_cmd_debug_flag(opts : @sut.OptionValues) -> Bool =
  #| (opts) => opts.debug === true

fn main {
  let cmd = @sut.new_command(Some("app"))
    .option("-d, --debug", Some("enable debug"), None)
    .parse(Some(["node", "app", "--debug"]), None)
  if !realworld_cmd_debug_flag(cmd.opts()) {
    abort("expected --debug flag to parse")
  }
}
EOF
      ;;
    debug)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let dbg : @sut.Debug = @sut.unsafeCast(@sut.get_default())
  dbg.enable("tsmbt:*")
  if !dbg.enabled("tsmbt:probe") {
    abort("expected namespace to be enabled")
  }
}
EOF
      ;;
    chokidar)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let watcher = @sut.new_fswatcher(None)
  let _ = watcher.close()
}
EOF
      ;;
    pino)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_pino_options() -> @sut.Pino_LoggerOptions =
  #| () => ({ level: "warn" })

extern "js" fn realworld_pino_level(logger : @sut.Pino_Logger) -> String =
  #| (logger) => logger.level

fn main {
  let logger = @sut.default(realworld_pino_options(), None)
  if realworld_pino_level(logger) != "warn" {
    abort("unexpected pino level")
  }
}
EOF
      ;;
    lodash)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.camelCase(Some("hello world")) != "helloWorld" {
    abort("unexpected lodash camelCase")
  }
}
EOF
      ;;
    uuid)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if !@sut.validate(@sut.unsafeCast("00000000-0000-0000-0000-000000000000")) {
    abort("expected NIL uuid to validate")
  }
}
EOF
      ;;
    minimatch)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if !@sut.minimatch("bar.foo", "*.foo", None) {
    abort("expected *.foo to match bar.foo")
  }
}
EOF
      ;;
    ws)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_ws_server_options() -> @sut.WebSocketServerOptions[@sut.JSValue, @sut.JSValue] =
  #| () => ({ noServer: true })

fn main {
  let server : @sut.Server[@sut.JSValue, @sut.JSValue] = @sut.new_server(
    Some(realworld_ws_server_options()),
    None,
  )
  server.close(None)
}
EOF
      ;;
    vitest_runtime)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_vitest_global() -> @sut.JSValue =
  #| () => globalThis

extern "js" fn realworld_vitest_options() -> @sut.StringRecordOfAny =
  #| () => ({})

extern "js" fn realworld_vitest_object() -> @sut.JSValue =
  #| () => ({})

fn main {
  let envs = @sut.get_builtin_environments()
  if envs.node.name != "node" {
    abort("expected node environment")
  }
  if envs.jsdom.name != "jsdom" {
    abort("expected jsdom environment")
  }
  let global = realworld_vitest_global()
  let options = realworld_vitest_options()
  let _ = envs.node.setup(global, options)
  match envs.node.setupVM {
    Some(setup_vm) => {
      let _ = setup_vm(options)
    }
    None => ()
  }
  let populated = @sut.populateGlobal(
    realworld_vitest_object(),
    realworld_vitest_object(),
    None,
  )
  let _ = populated.keys
}
EOF
      ;;
    playwright)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  // Compile-only smoke: see the explanation in the bridge_test.mbt
  // counterpart; playwright requires browser binaries to actually run.
  let _launch_options = @sut.LaunchOptions::{
    args: Some(["--disable-dev-shm-usage"]),
    artifactsDir: None,
    channel: None,
    chromiumSandbox: Some(false),
    downloadsPath: None,
    env: None,
    executablePath: None,
    firefoxUserPrefs: None,
    handleSIGHUP: None,
    handleSIGINT: None,
    handleSIGTERM: None,
    headless: Some(true),
    ignoreDefaultArgs: None,
    logger: None,
    proxy: None,
    slowMo: Some(0.0),
    timeout: Some(1000.0),
    tracesDir: None,
  }
  let _ = _launch_options
}
EOF
      ;;
    react_router)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let path = @sut.PathPartial::{
    pathname: Some("/docs"),
    search: None,
    hash: None,
  }
  if @sut.createPath(path) != "/docs" {
    abort("unexpected react-router createPath output")
  }
  let parsed = @sut.parsePath("/docs?tab=api#top")
  if parsed.pathname != Some("/docs") {
    abort("unexpected react-router parsePath pathname")
  }
  if @sut.generatePath("/docs", None) != "/docs" {
    abort("unexpected react-router generatePath output")
  }
  let full_path = @sut.PathPartial::{
    pathname: Some("/docs"),
    search: Some("?tab=api"),
    hash: Some("#top"),
  }
  if @sut.createPath(full_path) != "/docs?tab=api#top" {
    abort("unexpected react-router full createPath output")
  }
  if @sut.generate_path_params(
    "/users/:id",
    @sut.params_from_pairs(["id"], ["42"]),
  ) != "/users/42" {
    abort("unexpected react-router param generatePath output")
  }
  let resolved = @sut.resolvePath(
    @sut.to_from_string("../api"),
    Some("/docs/reference"),
  )
  if resolved.pathname != "/docs/api" {
    abort("unexpected react-router resolvePath pathname")
  }
  if resolved.search != "" || resolved.hash != "" {
    abort("unexpected react-router resolvePath search/hash")
  }
}
EOF
      ;;
    jose)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let jwt = @sut.new_unsecured_jwt(None)
  let _ = jwt.set_issuer("https://issuer.example")
  let _ = jwt.set_subject("user-42")
  let _ = jwt.set_jti("token-1")
  let _ = @sut.unsecured_jwt_set_issued_at_double(jwt, 1710000000.0)
  let _ = @sut.unsecured_jwt_set_not_before_double(jwt, 1710000000.0)
  let _ = @sut.unsecured_jwt_set_expiration_time_double(jwt, 4070908800.0)
  let encoded = jwt.encode()
  let decoded = @sut.unsecured_jwt_decode(encoded, None)
  let _ = decoded.header
  let _ = @sut.decodeJwt(encoded)
  let signer = @sut.new_sign_jwt(None)
  let _ = signer.set_issuer("https://issuer.example")
  let _ = signer.set_subject("user-42")
  let _ = signer.set_jti("token-1")
  let _ = @sut.sign_jwt_set_issued_at_double(signer, 1710000000.0)
  let _ = @sut.sign_jwt_set_not_before_double(signer, 1710000000.0)
  let _ = @sut.sign_jwt_set_expiration_time_double(signer, 4070908800.0)
}
EOF
      ;;
    express)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  let options = @sut.RouterOptions::{
    caseSensitive: Some(true),
    mergeParams: Some(true),
    strict: Some(false),
  }
  let _ = @sut.router(Some(options))
  let _ = @sut.get_json()
  let _ = @sut.get_urlencoded()
  let _ = @sut.get_static()
  let _ = @sut.get_request()
  let _ = @sut.get_response()
  let _ = @sut.default()
}
EOF
      ;;
    glob)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn realworld_glob_options() -> @sut.GlobOptions {
  @sut.GlobOptions::{
    absolute: Some(false),
    allowWindowsEscape: None,
    cwd: None,
    dot: Some(false),
    dotRelative: None,
    follow: Some(false),
    ignore: None,
    magicalBraces: Some(false),
    mark: None,
    matchBase: None,
    maxDepth: Some(4.0),
    nobrace: None,
    nocase: None,
    nodir: Some(true),
    noext: None,
    noglobstar: None,
    platform: None,
    realpath: None,
    root: None,
    scurry: None,
    stat: None,
    signal: None,
    windowsPathsNoEscape: Some(false),
    withFileTypes: Some(false),
    fs: None,
    debug: None,
    posix: None,
    includeChildMatches: None,
    braceExpandMax: None,
  }
}

fn main {
  let matches = @sut.globSync_string_glob_options_with_file_types_unset_optional(
    "*.json",
    None,
  )
  if matches.length() == 0 {
    abort("expected json files in generated project")
  }
  let opts = @sut.MinimatchOptionsPickWindowsPathsNoEscapeMagicalBraces::{
    windowsPathsNoEscape: Some(false),
    magicalBraces: Some(false),
  }
  if @sut.escape("src/*.mbt", Some(opts)) != "src/\\*.mbt" {
    abort("unexpected glob escape output")
  }
  if @sut.unescape("src/\\*.mbt", Some(opts)) != "src/*.mbt" {
    abort("unexpected glob unescape output")
  }
  if !@sut.has_magic("src/*.mbt", Some(realworld_glob_options())) {
    abort("expected glob pattern to have magic")
  }
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
    limits: None,
  }
}

extern "js" fn realworld_node_sqlite_params() -> Array[@sut.SQLInputValue] =
  #| () => []

extern "js" fn realworld_node_sqlite_row_value(row : @sut.StringRecordOfSqloutputValue) -> String =
  #| (row) => row.value

fn main {
  let db = @sut.new_database_sync(
    realworld_node_sqlite_memory_path(),
    Some(realworld_node_sqlite_options()),
  )
  if !db.get_database_sync_is_open() {
    abort("expected sqlite database to be open")
  }
  db.exec("CREATE TABLE data (key INTEGER PRIMARY KEY, value TEXT) STRICT")
  db.exec("INSERT INTO data (key, value) VALUES (1, 'hello')")
  db.exec("UPDATE data SET value = 'world' WHERE key = 1")
  let stmt = db.prepare("SELECT value FROM data WHERE key = 1", None)
  let row = match stmt.get(realworld_node_sqlite_params()) {
    Some(row) => row
    None => abort("expected the prepared statement to return a row")
  }
  if realworld_node_sqlite_row_value(row) != "world" {
    abort("unexpected sqlite row value")
  }
  db.close()
  if db.get_database_sync_is_open() {
    abort("expected sqlite database to be closed")
  }
}
EOF
      ;;
    node_fs)
      cat > "$smoke_dir/main.mbt" <<'EOF'
extern "js" fn realworld_node_fs_to_string(data : @sut.NonSharedBuffer) -> String =
  #| (data) => data.toString("utf8")

fn main {
  let path = @sut.path_like_from_string("node-fs-build-smoke.txt")
  let file = @sut.path_or_file_descriptor_from_path_like(path)
  if @sut.existsSync(path) {
    @sut.unlinkSync(path)
  }
  @sut.writeFileSync(file, "hello from moonbit", None)
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
fn main {
  @sut.assert_ok_bool(true, None)
  @sut.assert_equal_double(1.0, 1.0, None)
  @sut.assert_strict_equal_string("ok", "ok", None)
}
EOF
      ;;
    node_util)
      cat > "$smoke_dir/main.mbt" <<'EOF'
fn main {
  if @sut.toUSVString("ok") != "ok" {
    abort("unexpected toUSVString output")
  }
  if @sut.stripVTControlCharacters("plain") != "plain" {
    abort("unexpected stripVTControlCharacters output")
  }
  if @sut.diff_string("alpha", "alps").length() == 0 {
    abort("expected util.diff string wrapper to produce chunks")
  }
  if !@sut.is_array_string_array(["ok"]) {
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
  if [ "$module_name" = "vitest_runtime" ]; then
    run_logged "$log_root/${module_name}_bridge_js_smoke.log" \
      node --input-type=module -e '
import { pathToFileURL } from "node:url";
const bridge = await import(pathToFileURL(process.argv[1]).href);
const envs = bridge.__ts_mbt_get_builtin_environments();
if (envs.node.name !== "node" || envs.jsdom.name !== "jsdom") {
  throw new Error("unexpected Vitest builtin environment names");
}
const setupResult = await envs.node.setup(globalThis, {});
if (typeof setupResult.teardown !== "function") {
  throw new Error("expected node setup teardown function");
}
await setupResult.teardown(globalThis);
const vmResult = await envs.node.setupVM({});
if (!vmResult.getVmContext()) {
  throw new Error("expected node VM context");
}
await vmResult.teardown();
const populated = bridge.__ts_mbt_populate_global({}, {}, undefined);
if (!populated.keys || !populated.skipKeys) {
  throw new Error("expected populateGlobal result");
}
' "$out/bridge.js"
  fi
}

verify_package() {
  local package_spec="$1"
  local module_name="$2"
  local root="_build/realworld-typescript"
  local project="$root/project"
  local out="$project/dist/$module_name"

  local selected_node_modules_root
  selected_node_modules_root="$(node_modules_root_for_spec "$package_spec")"

  echo "== $package_spec"

  rm -rf "$out"
  mkdir -p "$project"
  ensure_project_node_modules "$project" "$selected_node_modules_root"

  # Per-package oracle scope: when an oracle cache exists for this
  # module under `_build/oracle-cache/<module_name>.json`, expose it via
  # `TS_MBT_ORACLE_CACHE` so the bridge splices in the tsc-resolved
  # types for this run only. Adjacent packages stay on the in-house
  # lowering — the previous global env experiment showed that naive
  # cross-package application widens hono-style aliases.
  local oracle_cache_path="$repo_root/_build/oracle-cache/${module_name}.json"
  local generate_env=(env)
  if [ -f "$oracle_cache_path" ]; then
    generate_env+=("TS_MBT_ORACLE_CACHE=$oracle_cache_path")
  fi

  (
    cd "$project"
    run_logged "$repo_root/$log_root/${module_name}_generate.log" \
      "${generate_env[@]}" \
      moon run "$repo_root/src/cmd/ts2mbt" -- \
      --input "$package_spec" \
      --out "dist/$module_name"
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
    moon run src/cmd/ts2mbt -- \
    --input "$types_path" \
    --out "$out" \
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
    moon run src/cmd/ts2mbt -- \
    --input "$types_path" \
    --out "$out" \
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
    moon run src/cmd/ts2mbt -- \
    --input "$types_path" \
    --out "$out" \
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

append_fallback_policy_report

echo "metrics written to $metrics_file"
