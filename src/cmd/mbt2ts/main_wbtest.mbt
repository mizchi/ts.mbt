///|
test "mbt2ts keeps the unified package generator as its public CLI contract" {
  let help = mbt2ts_help_lines()
  assert_eq(
    help[0],
    "  --input <pkg-or-mbti> --out <dir> [--diagnostics <path>] [--strict] [--no-facade] [--import-rewrites <json>] Generate a complete build-backed TypeScript package from a MoonBit pkg.generated.mbti",
  )
  assert_true(
    help.contains(
      "  scaffold <mbti> <out-dir> [import-rewrite-json] Emit build-backed JS/TypeScript scaffold from a MoonBit package interface",
    ),
  )
  assert_true(
    help.contains(
      "  facade-scaffold <mbti> <out-dir> [import-rewrite-json] Emit build-backed JS/TypeScript scaffold plus facade wrappers for omitted local methods",
    ),
  )
}
