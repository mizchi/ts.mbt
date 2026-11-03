///| Convert Node's Buffer result to a MoonBit String without weakening the

///|
/// generated `readFileSync` return type.
extern "js" fn utf8_text(data : @fs.NonSharedBuffer) -> String =
  #| (data) => data.toString("utf8")

///| A `ReadStream`-shaped object, so the accessor pair below can be observed

///| without opening a file. `ReadStream` is an opaque `#external` type, and

///|
/// what the accessors touch is one property.
extern "js" fn read_stream_with_path(path : String) -> @fs.ReadStream =
  #| (path) => ({ path })

///|
fn script_target() -> @ts.ScriptTarget {
  @ts.ScriptTarget::ES2024
}

///| `ReadStream.path` is declared `PathLike` — a tagged union whose MoonBit

///| repr is `{ "$tag": i, "_0": v }` and whose JS repr is the bare value — so

///| both accessors have to convert. Neither did: the getter handed the raw JS

///| string back as if it were the enum, and the setter stored the enum object

///| into Node's field.

///|

///| Checked by VALUE rather than by compiling, because both bugs compile

///| perfectly: the declared type is the same either way. The round trip is

///| what catches the write direction — a setter that stored the box leaves the

///| getter looking at an object that is neither string, Buffer nor URL, and

///|
/// its `_from_js` throws.
fn check_tagged_union_property_accessors() -> Unit {
  let stream = read_stream_with_path("read-stream-accessor.ts")
  match stream.get_read_stream_path() {
    StringValue(text) =>
      if text != "read-stream-accessor.ts" {
        abort("ReadStream.path getter returned the wrong string: " + text)
      }
    _ =>
      abort(
        "expected ReadStream.path to build PathLike::StringValue from a JS string",
      )
  }
  stream.set_read_stream_path(@fs.path_like_from_string("reassigned.ts"))
  match stream.get_read_stream_path() {
    StringValue(text) =>
      if text != "reassigned.ts" {
        abort("ReadStream.path setter stored the wrong string: " + text)
      }
    _ => abort("expected ReadStream.path to round trip through PathLike")
  }
}

///|
fn main {
  // This is the generated TypeScript compiler API, imported just like a
  // normal MoonBit package through `moon.pkg`.
  let source = @ts.createSourceFile(
    "answer.ts",
    "export const answer: number = 42",
    script_target(),
    Some(true),
    None,
  )
  let printed = @ts.createPrinter(None, None).printFile(source)
  if !printed.contains("answer") {
    abort("expected TypeScript printer output")
  }

  // `node:fs` is another generated package. The generated union helpers keep
  // the filename typed as `PathLike` / `PathOrFileDescriptor`.
  let path = @fs.path_like_from_string("typescript-node-imports-example.ts")
  let file = @fs.path_or_file_descriptor_from_path_like(path)
  if @fs.existsSync(path) {
    @fs.unlinkSync(path)
  }
  @fs.writeFileSync(file, printed, None)
  // `@types/node` 26.6 added a generic `readFileSync<T>(path, { buffer })`
  // overload FIRST, so the generator gives it the base name and the
  // `(path, options?) -> NonSharedBuffer` form this reads with gets its
  // descriptive name.
  let disk_text = utf8_text(
    @fs.readFileSync_path_or_file_descriptor_read_file_sync_options_with_buffer_encoding_optional(
      file,
      None,
    ),
  )
  @fs.unlinkSync(path)

  if disk_text != printed {
    abort("node:fs round trip changed the TypeScript output")
  }
  check_tagged_union_property_accessors()
  println("ok")
}
