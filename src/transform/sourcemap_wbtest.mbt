// Tests for the source-map utility module (VLQ, LineIndex, Builder).

///|
test "sourcemap: vlq_encode round-trips small integers" {
  // Spot-check against well-known base64 VLQ encodings.
  assert_eq(vlq_encode(0), "A")
  assert_eq(vlq_encode(1), "C")
  assert_eq(vlq_encode(-1), "D")
  assert_eq(vlq_encode(16), "gB")
  assert_eq(vlq_encode(-16), "hB")
  // Sanity on a larger value: 1234 → VLQ digits 36, 45, 2 → "ktC".
  assert_eq(vlq_encode(1234), "ktC")
}

///|
test "sourcemap: LineIndex maps byte offsets to (line, col)" {
  // 3-line source. Byte offsets:
  //   "a\nbc\nd"
  //    0 1 2 3 4 5
  //   line 0 starts at 0, line 1 at 2, line 2 at 5.
  let idx = LineIndex::new("a\nbc\nd")
  assert_eq(idx.position(0), Position::new(0, 0))
  assert_eq(idx.position(1), Position::new(0, 1))
  assert_eq(idx.position(2), Position::new(1, 0))
  assert_eq(idx.position(3), Position::new(1, 1))
  assert_eq(idx.position(5), Position::new(2, 0))
}

///|
test "sourcemap: LineIndex handles `\\r\\n` as one newline" {
  // "ab\r\ncd"
  //  0 1 2 3 4 5
  // After `\r\n` (2 bytes) the next line starts at byte 4.
  let idx = LineIndex::new("ab\r\ncd")
  assert_eq(idx.position(0), Position::new(0, 0))
  assert_eq(idx.position(1), Position::new(0, 1))
  assert_eq(idx.position(4), Position::new(1, 0))
  assert_eq(idx.position(5), Position::new(1, 1))
}

///|
test "sourcemap: builder produces v3 JSON with embedded source" {
  let b = SourceMapBuilder::new()
  b.add_mapping(0, 0, 0, 0)
  b.add_mapping(0, 5, 0, 4)
  b.add_mapping(1, 0, 1, 0)
  let json = b.to_json(
    source="const a = 1;\nconst b = 2;",
    source_path="input.ts",
    output_path="output.js",
  )
  assert_true(json.contains("\"version\":3"))
  assert_true(json.contains("\"file\":\"output.js\""))
  assert_true(json.contains("\"sources\":[\"input.ts\"]"))
  assert_true(json.contains("\"sourcesContent\":["))
  assert_true(json.contains("const a = 1"))
  assert_true(json.contains("\"mappings\":\""))
  // Three mappings: 2 on line 0, 1 on line 1. Encoded as
  //   AAAA,KAAI;AACA
  // where line 0 has two segments separated by `,`, then `;` for
  // the line break, then the single line-1 segment.
  assert_true(json.contains(";"))
  assert_true(json.contains(","))
}

///|
test "sourcemap: empty builder still emits a valid mappings field" {
  let b = SourceMapBuilder::new()
  let json = b.to_json(
    source="",
    source_path="empty.ts",
    output_path="empty.js",
  )
  assert_true(json.contains("\"mappings\":\""))
}

///|
test "sourcemap: transform_source_full emits per-statement mappings" {
  // Multi-line TS source so the per-statement positions span more
  // than one source line.
  let src =
    #|const a = 1;
    #|const b = 2;
    #|const c = 3;
  match
    transform_source_full(
      src,
      JsxConfig::default(),
      with_sourcemap=true,
      source_path="prog.ts",
      output_path="prog.js",
    ) {
    Ok(out) =>
      match out.sourcemap {
        Some(json) => {
          assert_true(json.contains("\"version\":3"))
          assert_true(json.contains("\"file\":\"prog.js\""))
          assert_true(json.contains("\"sources\":[\"prog.ts\"]"))
          assert_true(json.contains("\"mappings\":\""))
          // We expect at least 3 separate lines in the mappings
          // string (`;` line separators). Each top-level stmt
          // contributes one mapping at its emitted line head.
          let mappings_start_idx = match json.find("\"mappings\":\"") {
            Some(i) => i + "\"mappings\":\"".length()
            None => 0
          }
          let after = json
            .substring(start=mappings_start_idx, end=json.length())
            .to_string()
          // Count semicolons in the mappings field (rough check).
          let mut semis = 0
          for c in after {
            if c == ';' {
              semis = semis + 1
            } else if c == '"' {
              break
            }
          }
          assert_true(semis >= 2)
        }
        None => fail("expected sourcemap, got None")
      }
    Err(e) => fail("transform error: \{e}")
  }
}

///|
test "sourcemap: with_sourcemap=false produces no mapping JSON" {
  match
    transform_source_full(
      "const x = 1;",
      JsxConfig::default(),
      with_sourcemap=false,
    ) {
    Ok(out) =>
      match out.sourcemap {
        Some(_) => fail("expected None, got Some(...)")
        None => ()
      }
    Err(e) => fail("transform error: \{e}")
  }
}
