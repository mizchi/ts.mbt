///|
test "command_help_lines hides unstable wasm commands behind experimental names" {
  let lines = command_help_lines()
  assert_true(
    lines.contains(
      "  experimental-emit-gc <file> [out] Emit experimental wasm-gc binary (default: out.wasm)",
    ),
  )
  assert_true(
    lines.contains(
      "  experimental-analyze <file> Analyze experimental AOT compilability of functions",
    ),
  )
  assert_true(
    lines.contains(
      "  experimental-aot-check <file> Alias for experimental-analyze",
    ),
  )
  assert_false(
    lines.contains(
      "  emit-gc <file> [out] Emit wasm-gc binary (default: out.wasm)",
    ),
  )
  assert_false(
    lines.contains(
      "  analyze <file>       Analyze AOT compilability of functions",
    ),
  )
  assert_false(lines.contains("  aot-check <file>     Alias for analyze"))
}
