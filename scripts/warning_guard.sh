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
  # "`moon.mod.json` at '...' is deprecated. Run `moon fmt` to migrate to
  # `moon.mod`" is `moon`'s own manifest-format deprecation, not a
  # diagnostic about any code we generate. It fires on the fixture
  # manifests these harnesses write themselves (86 of them across
  # verify_scaffolds / verify_examples / verify_generated_fixtures), and
  # the remedy it names was RUN rather than reasoned about: `moon fmt`
  # migrates a dep-free manifest cleanly (`preferred-target` becomes
  # `preferred_target`, `deps` becomes `import { "name@version", }`), and
  # for a fixture carrying a LOCAL path dependency it REFUSES outright —
  #
  #     Error: moon.mod does not support local dependency `mizchi/js` in
  #     `import`; use workspace configuration in `moon.work` instead.
  #
  # 9 of verify_scaffolds' 12 manifests and 7 of verify_examples' 14 are
  # exactly that shape (a `mizchi/js` stub resolved by path), so the
  # migration is a `moon.work` restructure of the fixture layout and not
  # a rename. A partial migration buys nothing here either: the guard is
  # all-or-nothing per run, so the first un-migratable fixture would make
  # it fatal again. The legacy name is also still a supported INPUT to
  # this repo's own product — `main.mbt` looks for both spellings when it
  # resolves a consumer's module root — so these fixtures are exercising
  # a shape we deliberately accept. Let the deprecation through; the
  # `moon.work` migration is tracked separately.
  #
  # Treat every other Warning as fatal.
  if grep -E '(^|[[:space:]])([Ww]arning):|forwardRef requires a render function' "$tmp" \
      | grep -vE '^Warning: \[0020\]|^Warning: \[0005\]|^Warning: \[0082\]|^Warning: \[0035\]|^warning: unhandled Platform key|^Warning: `moon\.(mod|pkg)\.json` at .* is deprecated' >&2; then
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
