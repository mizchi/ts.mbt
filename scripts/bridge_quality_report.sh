#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
source "$repo_root/scripts/warning_guard.sh"

report_root="_build/bridge-quality"
log_root="$report_root/logs"
report_file="$report_root/REPORT.md"
unsupported_details_file="$report_root/unsupported-exports.tsv"
ambiguous_unsupported_export_budget=1
namespace_omitted_unsupported_export_budget=0
namespace_widened_unsupported_export_budget=0

rm -rf "$report_root"
mkdir -p "$log_root"
shopt -s nullglob

checks=()
statuses=()
logs=()
metric_roots=()

run_check() {
  local name="$1"
  shift
  local log_file="$log_root/$name.log"

  checks+=("$name")
  logs+=("$log_file")
  if "$@" > "$log_file" 2>&1; then
    statuses+=("pass")
  else
    statuses+=("fail")
  fi
}

collect_metric_roots() {
  metric_roots=()
  local root
  for root in _build/scaffold_* _build/fixture_* _build/bridge_fixture_* _build/examples; do
    if [ -e "$root" ]; then
      metric_roots+=("$root")
    fi
  done
}

find_metric_files() {
  local pattern="$1"

  if [ "${#metric_roots[@]}" -eq 0 ]; then
    return
  fi
  find "${metric_roots[@]}" -type f -name "$pattern"
}

find_metric_dirs() {
  local pattern="$1"

  if [ "${#metric_roots[@]}" -eq 0 ]; then
    return
  fi
  find "${metric_roots[@]}" -type d -name "$pattern"
}

count_files() {
  local pattern="$1"

  if [ "${#metric_roots[@]}" -eq 0 ]; then
    printf '0\n'
    return
  fi
  find_metric_files "$pattern" | wc -l | tr -d ' '
}

sum_lines() {
  local name_pattern="$1"

  if [ "${#metric_roots[@]}" -eq 0 ]; then
    printf '0\n'
    return
  fi
  local total=0
  local file
  while IFS= read -r file; do
    total=$((total + $(wc -l < "$file")))
  done < <(find_metric_files "$name_pattern")
  printf '%s\n' "$total"
}

count_matching_files() {
  local name_pattern="$1"
  local pattern="$2"

  if [ "${#metric_roots[@]}" -eq 0 ]; then
    printf '0\n'
    return
  fi
  local total=0
  local file
  local count
  while IFS= read -r file; do
    count="$(grep -E -c "$pattern" "$file" 2>/dev/null || true)"
    total=$((total + count))
  done < <(find_metric_files "$name_pattern")
  printf '%s\n' "$total"
}

collect_unsupported_export_counts() {
  local details_file="$1"
  local total=0
  local ambiguous=0
  local namespace_omitted=0
  local namespace_widened=0
  local unbudgeted=0
  local file
  local line
  local line_no
  local classification

  : > "$details_file"

  while IFS= read -r file; do
    line_no=0
    while IFS= read -r line || [ -n "$line" ]; do
      line_no=$((line_no + 1))
      if [[ "$line" != ///\ Unsupported\ export* ]]; then
        continue
      fi

      total=$((total + 1))
      classification="unbudgeted"
      if [[ "$line" == *"ambiguous re-export surface is widened to JSValue; candidates: "* ]]; then
        classification="ambiguous-re-export"
        ambiguous=$((ambiguous + 1))
      elif [[ "$line" == *"runtime members inside exported namespace are omitted; only type members are exposed." ]]; then
        classification="namespace-runtime-omitted"
        namespace_omitted=$((namespace_omitted + 1))
      elif [[ "$line" == *"namespace export is widened to JSValue." ]]; then
        classification="namespace-widened"
        namespace_widened=$((namespace_widened + 1))
      else
        unbudgeted=$((unbudgeted + 1))
      fi

      printf '%s\t%s:%s\t%s\n' \
        "$classification" \
        "$file" \
        "$line_no" \
        "$line" >> "$details_file"
    done < "$file"
  done < <(find_metric_files 'bridge.mbti')

  printf '%s|%s|%s|%s|%s\n' \
    "$total" \
    "$ambiguous" \
    "$namespace_omitted" \
    "$namespace_widened" \
    "$unbudgeted"
}

jsvalue_cause_counts() {
  local surface_total=0
  local unknown_any=0
  local overload_fallback=0
  local conditional_mapped_fallback=0
  local callback_function_fallback=0
  local tuple_array_fallback=0
  local namespace_value_fallback=0
  local file
  local line

  while IFS= read -r file; do
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
  done < <(find_metric_files 'bridge.mbti')

  printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "$surface_total" \
    "$unknown_any" \
    "$overload_fallback" \
    "$conditional_mapped_fallback" \
    "$callback_function_fallback" \
    "$tuple_array_fallback" \
    "$namespace_value_fallback"
}

run_check "verify-scaffolds" bash scripts/verify_scaffolds.sh
run_check "verify-generated-fixtures" bash scripts/verify_generated_fixtures.sh
run_check "verify-examples" bash scripts/verify_examples.sh

collect_metric_roots

moonbit_bridge_files="$(count_files 'bridge.mbt')"
moonbit_decl_files="$(count_files 'bridge.mbti')"
typescript_decl_files="$(count_files '*.d.ts')"
javascript_files="$(count_files '*.js')"
moonbit_bridge_lines="$(sum_lines 'bridge.mbt')"
moonbit_decl_lines="$(sum_lines 'bridge.mbti')"
typescript_decl_lines="$(sum_lines '*.d.ts')"
javascript_lines="$(sum_lines '*.js')"
diagnostic_files=$(( $(count_files 'SCAFFOLD_DIAGNOSTICS.md') + $(count_files 'AUTOLINK_DIAGNOSTICS.md') ))
IFS='|' read -r \
  unsupported_exports \
  ambiguous_unsupported_exports \
  namespace_omitted_unsupported_exports \
  namespace_widened_unsupported_exports \
  unbudgeted_unsupported_exports < <(collect_unsupported_export_counts "$unsupported_details_file")
moonbit_declared_functions="$(count_matching_files 'bridge.mbti' '^declare pub fn ')"
moonbit_declared_types="$(count_matching_files 'bridge.mbti' '^declare pub type ')"
typescript_exported_declarations="$(count_matching_files '*.d.ts' '^export (declare )?(function|interface|class|const|type) ')"
jsvalue_refs="$(count_matching_files 'bridge.mbti' 'JSValue')"
jsvalue_functions="$(count_matching_files 'bridge.mbti' '^declare pub fn .*JSValue')"
moon_build_smokes="$(find_metric_dirs '__tsmbt_build_smoke__' | wc -l | tr -d ' ')"
IFS='|' read -r \
  jsvalue_surface_lines \
  jsvalue_unknown_any \
  jsvalue_overload_fallback \
  jsvalue_conditional_mapped_fallback \
  jsvalue_callback_function_fallback \
  jsvalue_tuple_array_fallback \
  jsvalue_namespace_value_fallback < <(jsvalue_cause_counts)

overall="pass"
for status in "${statuses[@]}"; do
  if [ "$status" != "pass" ]; then
    overall="fail"
  fi
done
if [ "$unbudgeted_unsupported_exports" -gt 0 ]; then
  overall="fail"
fi
if [ "$ambiguous_unsupported_exports" -gt "$ambiguous_unsupported_export_budget" ]; then
  overall="fail"
fi
if [ "$namespace_omitted_unsupported_exports" -gt "$namespace_omitted_unsupported_export_budget" ]; then
  overall="fail"
fi
if [ "$namespace_widened_unsupported_exports" -gt "$namespace_widened_unsupported_export_budget" ]; then
  overall="fail"
fi

{
  printf '# Bridge Quality Report\n\n'
  printf 'Generated by `scripts/bridge_quality_report.sh`.\n\n'
  printf 'Overall: `%s`\n\n' "$overall"
  printf '## Verification Summary\n\n'
  printf '| check | status | log |\n'
  printf '| --- | --- | --- |\n'
  for i in "${!checks[@]}"; do
    printf '| %s | %s | `%s` |\n' "${checks[$i]}" "${statuses[$i]}" "${logs[$i]}"
  done
  printf '\n'
  printf '## Generated Artifact Metrics\n\n'
  printf '| metric | value |\n'
  printf '| --- | ---: |\n'
  printf '| MoonBit bridge implementations | %s |\n' "$moonbit_bridge_files"
  printf '| MoonBit bridge interfaces | %s |\n' "$moonbit_decl_files"
  printf '| TypeScript declarations | %s |\n' "$typescript_decl_files"
  printf '| JavaScript files | %s |\n' "$javascript_files"
  printf '| MoonBit bridge implementation lines | %s |\n' "$moonbit_bridge_lines"
  printf '| MoonBit bridge interface lines | %s |\n' "$moonbit_decl_lines"
  printf '| TypeScript declaration lines | %s |\n' "$typescript_decl_lines"
  printf '| JavaScript lines | %s |\n' "$javascript_lines"
  printf '| MoonBit declared functions | %s |\n' "$moonbit_declared_functions"
  printf '| MoonBit declared types | %s |\n' "$moonbit_declared_types"
  printf '| TypeScript exported declarations | %s |\n' "$typescript_exported_declarations"
  printf '| diagnostics files | %s |\n' "$diagnostic_files"
  printf '| unsupported exports | %s |\n' "$unsupported_exports"
  printf '| budgeted ambiguous unsupported exports | %s / %s |\n' "$ambiguous_unsupported_exports" "$ambiguous_unsupported_export_budget"
  printf '| budgeted namespace-runtime omitted exports | %s / %s |\n' "$namespace_omitted_unsupported_exports" "$namespace_omitted_unsupported_export_budget"
  printf '| budgeted namespace-widened exports | %s / %s |\n' "$namespace_widened_unsupported_exports" "$namespace_widened_unsupported_export_budget"
  printf '| unbudgeted unsupported exports | %s |\n' "$unbudgeted_unsupported_exports"
  printf '| JSValue refs | %s |\n' "$jsvalue_refs"
  printf '| JSValue surface lines | %s |\n' "$jsvalue_surface_lines"
  printf '| JSValue functions | %s |\n' "$jsvalue_functions"
  printf '| generated build-smoke packages | %s |\n' "$moon_build_smokes"
  printf '\n'
  printf '## JSValue Cause Breakdown\n\n'
  printf 'This is a heuristic classification over generated `bridge.mbti` surface lines that contain `JSValue`, excluding the shared banner and type declaration.\n\n'
  printf '| cause | lines |\n'
  printf '| --- | ---: |\n'
  printf '| unknown / any | %s |\n' "$jsvalue_unknown_any"
  printf '| overload fallback | %s |\n' "$jsvalue_overload_fallback"
  printf '| conditional / mapped type fallback | %s |\n' "$jsvalue_conditional_mapped_fallback"
  printf '| callback / function type fallback | %s |\n' "$jsvalue_callback_function_fallback"
  printf '| tuple / array fallback | %s |\n' "$jsvalue_tuple_array_fallback"
  printf '| namespace / value fallback | %s |\n' "$jsvalue_namespace_value_fallback"
  printf '\n'
  printf '## Unsupported Export Budget\n\n'
  printf 'Only ambiguous re-export surfaces with explicit candidate diagnostics are budgeted in this fixture corpus. Any other unsupported export class fails this report unless its budget is raised deliberately.\n\n'
  printf '| class | location | diagnostic |\n'
  printf '| --- | --- | --- |\n'
  if [ -s "$unsupported_details_file" ]; then
    while IFS=$'\t' read -r classification location diagnostic; do
      printf '| %s | `%s` | %s |\n' "$classification" "$location" "$diagnostic"
    done < "$unsupported_details_file"
  else
    printf '| none |  |  |\n'
  fi
} > "$report_file"

cat "$report_file"

if [ "$overall" != "pass" ]; then
  exit 1
fi
