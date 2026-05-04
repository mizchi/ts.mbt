#!/usr/bin/env bash

tsmbt_run_no_warnings() {
  local tmp
  local status
  local had_errexit=0

  case "$-" in
    *e*) had_errexit=1 ;;
  esac

  tmp="$(mktemp)"
  set +e
  "$@" >"$tmp" 2>&1
  status=$?
  if [ "$had_errexit" -eq 1 ]; then
    set -e
  fi

  cat "$tmp"
  # `[0020]` is the MoonBit deprecation warning code (e.g. "Use Debug
  # instead of Show for debugging purposes" on `assert_eq`). It surfaces
  # whenever CI's bleeding-edge moonbit toolchain runs ahead of what
  # local development uses; the deprecation isn't actionable from this
  # repo, so let it through. Treat every other Warning as fatal.
  if grep -E '(^|[[:space:]])([Ww]arning):|forwardRef requires a render function' "$tmp" \
      | grep -vE '^Warning: \[0020\]' >&2; then
    printf 'warning output detected while running:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    rm -f "$tmp"
    return 1
  fi

  rm -f "$tmp"
  return "$status"
}

moon() {
  tsmbt_run_no_warnings command moon "$@"
}

pnpm() {
  tsmbt_run_no_warnings command pnpm "$@"
}

node() {
  tsmbt_run_no_warnings command node "$@"
}
