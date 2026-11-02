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
  # `[0025]` (`test_unqualified_package`: a black-box test calling its
  # own package's `pub fn` without `@pkg.`) appeared with moon
  # 0.1.20261029. It can only fire on a `*_test.mbt`, and the generator
  # emits none — every one is a fixture test these harnesses write (133
  # heredocs across four scripts), so it says nothing about generated
  # code. Renaming them to `_wbtest.mbt` would silence it by dropping the
  # check that the bridge API is `pub`, which is worse; qualifying them
  # is the real migration and is tracked separately.
  #
  # "Package `moonbitlang/async...` depends on experimental package
  # `moonbitlang/core/async...`" comes from the async library's OWN
  # moon.pkg files, which do not yet set `allow-experimental-packages`.
  # Setting that option in our importing package does not silence it
  # (measured), so it is not actionable from this repo; only that exact
  # dependency's notice is let through.
  #
  # The fixture manifests these harnesses write are `moon.mod` (DSL) now:
  # moon 0.1.20261029 refuses `moon.mod.json` outright, and a fixture
  # with a local path dependency declares it as a `moon.work` member.
  #
  # Treat every other Warning as fatal.
  if grep -E '(^|[[:space:]])([Ww]arning):|forwardRef requires a render function' "$tmp" \
      | grep -vE '^Warning: \[0020\]|^Warning: \[0005\]|^Warning: \[0082\]|^Warning: \[0035\]|^Warning: \[0025\]|^warning: unhandled Platform key|^Warning: Package `moonbitlang/async[^`]*` depends on experimental package `moonbitlang/core/async[^`]*`' >&2; then
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
