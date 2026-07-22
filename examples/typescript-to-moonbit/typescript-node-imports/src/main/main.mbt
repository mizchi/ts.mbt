///| Convert Node's Buffer result to a MoonBit String without weakening the
///| generated `readFileSync` return type.
extern "js" fn utf8_text(data : @fs.NonSharedBuffer) -> String =
  #| (data) => data.toString("utf8")

fn script_target() -> @ts.ScriptTarget {
  @ts.ScriptTarget::ES2024
}

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
  let disk_text = utf8_text(@fs.readFileSync(file, None))
  @fs.unlinkSync(path)

  if disk_text != printed {
    abort("node:fs round trip changed the TypeScript output")
  }
  println("ok")
}
