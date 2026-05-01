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
  if grep -E '(^|[[:space:]])([Ww]arning):|forwardRef requires a render function' "$tmp" >&2; then
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
