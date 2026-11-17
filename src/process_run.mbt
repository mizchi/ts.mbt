///|
/// Run `cmd args` in `cwd` and return its exit code with stdout and
/// stderr merged.
///
/// This used to be `mizchi/x/process`'s `collect_output_merged`. That
/// package imports `mizchi/x/socket`, whose native source (0.6.1) calls
/// `Show::to_string` as a method, and moonc v0.10.21 rejects that unless
/// the impl is promoted with `extend`. The import alone failed every
/// native build. The native arm here is what that wrapper called anyway.
#cfg(not(target="js"))
async fn run_collect_merged(
  cmd : String,
  args : Array[String],
  cwd~ : String,
) -> (Int32, String) {
  let (code, output) = @async_process.collect_output_merged(cmd, args, cwd~)
  (code, output.text())
}

///|
/// The `js` arm runs the command through Node's `child_process.spawnSync`.
/// The callers run one build command and read its whole output, so a
/// blocking call is the same behaviour. stdout comes before stderr rather
/// than interleaved, which only changes the order of a failure message.
#cfg(target="js")
#warnings("-unused_async")
async fn run_collect_merged(
  cmd : String,
  args : Array[String],
  cwd~ : String,
) -> (Int32, String) {
  // `moonbitlang/async/process` has no `js` backend, and `unimplemented`
  // is the one symbol it exposes there. Naming it keeps the import used on
  // every target, as `@async_fs.unimplemented` does in `main.mbt`.
  ignore(@async_process.unimplemented)
  let packed = run_collect_merged_js(cmd, FixedArray::from_array(args), cwd)
  match packed.find("\n") {
    Some(i) => {
      let mut code = 0
      for c in packed[:i] {
        code = code * 10 + (c.to_int() - '0'.to_int())
      }
      (code, packed[i + 1:].to_owned())
    }
    None => (1, packed)
  }
}

///|
/// Returns the exit code, a newline, then the merged output. A spawn
/// failure (the command not found) is exit code 127 with the error text.
#cfg(target="js")
extern "js" fn run_collect_merged_js(
  cmd : String,
  args : FixedArray[String],
  cwd : String,
) -> String =
  #|(cmd, args, cwd) => {
  #|  const cp = typeof process.getBuiltinModule === "function"
  #|    ? process.getBuiltinModule("node:child_process")
  #|    : require("node:child_process");
  #|  const r = cp.spawnSync(cmd, args, {
  #|    cwd,
  #|    encoding: "utf8",
  #|    stdio: ["ignore", "pipe", "pipe"],
  #|    maxBuffer: 1 << 30,
  #|  });
  #|  if (r.error) {
  #|    return "127\n" + String(r.error.message) + "\n";
  #|  }
  #|  const code = r.status === null ? 1 : r.status;
  #|  return String(code) + "\n" + (r.stdout || "") + (r.stderr || "");
  #|}
