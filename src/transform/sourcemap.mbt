// Source Map v3 generator.
//
// Goal of this initial module is to make the transform pipeline
// *capable* of producing source maps — the position-tracking
// emitter, the VLQ encoder, and the JSON serializer all live here.
// The first integration only attaches statement-level mappings; AST
// nodes carrying per-token positions will come in a follow-up.
//
// Public surface:
//
//   - `LineIndex::new(source)` — precompute line starts so byte
//     offsets convert to (line, col) in O(log lines).
//   - `Position` — zero-indexed line / column pair.
//   - `SourceMapBuilder::new()` + `.add_mapping(emit_line,
//     emit_col, src_line, src_col)` — accumulate raw segments.
//   - `SourceMapBuilder::to_json(...)` — emit the v3 JSON document.
//   - `vlq_encode(n)` — base64 VLQ for one signed integer.
//
// The internal representation is intentionally close to the v3 shape
// so the JSON serializer is a trivial walk.

///|
pub(all) struct Position {
  line : Int // 0-indexed
  column : Int // 0-indexed
} derive(Eq, Show)

///|
pub fn Position::new(line : Int, column : Int) -> Position {
  { line, column }
}

///|
/// Map between byte offsets and (line, column) positions in a source
/// string. Precomputes line-start byte offsets so the per-lookup cost
/// is O(log lines).
pub(all) struct LineIndex {
  line_starts : Array[Int]
}

///|
pub fn LineIndex::new(source : String) -> LineIndex {
  let starts : Array[Int] = [0]
  let len = source.length()
  let mut i = 0
  while i < len {
    let c = source[i]
    if c == '\n' {
      starts.push(i + 1)
    } else if c == '\r' {
      // Treat `\r\n` and bare `\r` both as one newline.
      let next = if i + 1 < len { source[i + 1] } else { 0 }
      if next == '\n' {
        starts.push(i + 2)
        i = i + 2
        continue
      } else {
        starts.push(i + 1)
      }
    }
    i = i + 1
  }
  { line_starts: starts }
}

///|
/// Convert a byte offset into a zero-indexed `(line, column)` pair.
/// Out-of-range offsets clamp to the last line.
pub fn LineIndex::position(self : LineIndex, offset : Int) -> Position {
  let starts = self.line_starts
  if starts.length() == 0 {
    return { line: 0, column: 0 }
  }
  // Binary search for the largest start <= offset.
  let mut lo = 0
  let mut hi = starts.length() - 1
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if starts[mid] <= offset {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  let line = lo
  let column = offset - starts[lo]
  { line, column }
}

// ---------------------------------------------------------------------------
// Base64 VLQ encoder.
// ---------------------------------------------------------------------------

///|
let vlq_base64_chars : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
/// Encode a single signed integer as a base64 VLQ string. This is the
/// per-segment encoding used in the `mappings` field of a v3 source
/// map.
pub fn vlq_encode(value : Int) -> String {
  let buf = StringBuilder::new()
  // Move the sign bit to bit 0 of the resulting unsigned integer.
  let mut v = if value < 0 { (-value).lsl(1).lor(1) } else { value.lsl(1) }
  if v == 0 {
    return "A"
  }
  while v != 0 {
    let mut digit = v.land(0x1f)
    v = v.lsr(5)
    if v != 0 {
      digit = digit.lor(0x20)
    }
    let ch = vlq_base64_chars[digit].unsafe_to_char()
    buf.write_char(ch)
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// Mapping segments.
// ---------------------------------------------------------------------------

///|
/// One raw mapping segment. Source-side fields are optional — a
/// mapping that only records an output position (no original mapping)
/// emits as `vlq(out_col_delta)` alone.
pub(all) struct Segment {
  out_col : Int
  src_line : Int?
  src_col : Int?
  // Source-id slot. The current builder uses a single source string,
  // so this is always 0 when present.
  src_id : Int?
}

///|
pub(all) struct SourceMapBuilder {
  // Per output line, the segments on that line. Empty arrays in
  // between represent blank lines.
  lines : Array[Array[Segment]]
  // Tracked so the builder can grow lines lazily.
  mut last_out_line : Int
  // Index into the `sources` array used when `add_mapping` is called
  // without explicit source-id. The bundler switches this between
  // modules so each module's mappings point at the right source
  // file.
  mut current_source : Int
}

///|
pub fn SourceMapBuilder::new() -> SourceMapBuilder {
  { lines: [[]], last_out_line: 0, current_source: 0 }
}

///|
/// Switch the active source-id for subsequent `add_mapping` calls.
/// Used by the bundler when concatenating modules so each module's
/// mappings point back at its own slot in the source-map's
/// `sources` array.
pub fn SourceMapBuilder::set_current_source(
  self : SourceMapBuilder,
  source_id : Int,
) -> Unit {
  self.current_source = source_id
}

///|
fn SourceMapBuilder::ensure_line(self : SourceMapBuilder, line : Int) -> Unit {
  while self.lines.length() <= line {
    self.lines.push([])
  }
  if line > self.last_out_line {
    self.last_out_line = line
  }
}

///|
/// Record a mapping from an emitted `(out_line, out_col)` to a source
/// `(src_line, src_col)`. Multiple mappings on the same out-line are
/// expected to be added in increasing-`out_col` order; the builder
/// doesn't sort.
pub fn SourceMapBuilder::add_mapping(
  self : SourceMapBuilder,
  out_line : Int,
  out_col : Int,
  src_line : Int,
  src_col : Int,
) -> Unit {
  self.ensure_line(out_line)
  self.lines[out_line].push({
    out_col,
    src_line: Some(src_line),
    src_col: Some(src_col),
    src_id: Some(self.current_source),
  })
}

///|
/// Record an emit position with no source counterpart — used to
/// terminate a region without claiming a source attribution. The v3
/// spec treats these as "lookup falls through".
pub fn SourceMapBuilder::add_unmapped(
  self : SourceMapBuilder,
  out_line : Int,
  out_col : Int,
) -> Unit {
  self.ensure_line(out_line)
  self.lines[out_line].push({
    out_col,
    src_line: None,
    src_col: None,
    src_id: None,
  })
}

// ---------------------------------------------------------------------------
// JSON serialization.
// ---------------------------------------------------------------------------

///|
/// Render the accumulated mappings as a v3 source-map JSON document.
/// `source` is the original source text (embedded as `sourcesContent`)
/// and `source_path` is the value that lands in the `sources` array.
/// `output_path` becomes the `file` field.
pub fn SourceMapBuilder::to_json(
  self : SourceMapBuilder,
  source~ : String,
  source_path~ : String,
  output_path~ : String,
) -> String {
  self.to_json_multi([source_path], [source], output_path~)
}

///|
/// Multi-source variant: emits the same v3 document but with `n`
/// entries in `sources` / `sourcesContent`. Used by the bundler so
/// every module shows up in the map.
pub fn SourceMapBuilder::to_json_multi(
  self : SourceMapBuilder,
  sources : Array[String],
  sources_content : Array[String],
  output_path~ : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\"version\":3,\"file\":\"")
  write_json_escaped(buf, output_path)
  buf.write_string("\",\"sources\":[")
  for i, s in sources {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_char('"')
    write_json_escaped(buf, s)
    buf.write_char('"')
  }
  buf.write_string("],\"sourcesContent\":[")
  for i, c in sources_content {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_char('"')
    write_json_escaped(buf, c)
    buf.write_char('"')
  }
  buf.write_string("],\"names\":[],\"mappings\":\"")
  buf.write_string(self.encode_mappings())
  buf.write_string("\"}")
  buf.to_string()
}

///|
/// Build the comma-and-semicolon delimited VLQ string for the
/// `mappings` field. Per the v3 spec: each output line is a
/// `;`-separated group; within a line, segments are `,`-separated;
/// every numeric field in a segment is delta-encoded against the
/// previous segment's value.
fn SourceMapBuilder::encode_mappings(self : SourceMapBuilder) -> String {
  let buf = StringBuilder::new()
  let mut prev_src_line = 0
  let mut prev_src_col = 0
  let mut prev_src_id = 0
  for i, line in self.lines {
    if i > 0 {
      buf.write_char(';')
    }
    let mut prev_out_col = 0
    for j, seg in line {
      if j > 0 {
        buf.write_char(',')
      }
      buf.write_string(vlq_encode(seg.out_col - prev_out_col))
      prev_out_col = seg.out_col
      match (seg.src_id, seg.src_line, seg.src_col) {
        (Some(id), Some(sl), Some(sc)) => {
          buf.write_string(vlq_encode(id - prev_src_id))
          prev_src_id = id
          buf.write_string(vlq_encode(sl - prev_src_line))
          prev_src_line = sl
          buf.write_string(vlq_encode(sc - prev_src_col))
          prev_src_col = sc
        }
        _ => ()
      }
    }
  }
  buf.to_string()
}

///|
fn write_json_escaped(buf : StringBuilder, s : String) -> Unit {
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 {
          // Control characters → unicode escape.
          let hex = "0123456789abcdef"
          let v = c.to_int()
          buf.write_string("\\u00")
          buf.write_char(hex[v / 16].unsafe_to_char())
          buf.write_char(hex[v % 16].unsafe_to_char())
        } else {
          buf.write_char(c)
        }
    }
  }
}
