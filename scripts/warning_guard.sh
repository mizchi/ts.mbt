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
  # repo, so let it through.
  #
  # `[0005]` is `unused_type_variable`. The bridge generator preserves
  # interface generic parameters even when the parser substitutes their
  # body usage away (`Foo<T> { x: Wrapper<T> }` ⇒ `pub(all) struct
  # Foo[T] { x : Wrapper }`); registering the type-param arity is
  # required so call sites can reference `Foo[JSValue]` against a
  # struct of matching arity, but the resulting unused-T warning isn't
  # silenceable per-decl. The generated code is regenerated, not
  # hand-edited, so we let those warnings through.
  #
  # `[0082]` (`ambiguous_braces`: `let m : Map[...] = {}`) and `[0035]`
  # (`reserved_keyword`: identifiers like `local` / `recur`) appeared
  # with the 2026-07 toolchain and fire on long-standing idiomatic repo
  # code compiled during `moon run` — same bleeding-edge-churn category
  # as `[0020]`, so let them through until the syntax migration lands
  # upstream-wide.
  #
  # Treat every other Warning as fatal.
  if grep -E '(^|[[:space:]])([Ww]arning):|forwardRef requires a render function' "$tmp" \
      | grep -vE '^Warning: \[0020\]|^Warning: \[0005\]|^Warning: \[0082\]|^Warning: \[0035\]|^warning: unhandled Platform key' >&2; then
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
