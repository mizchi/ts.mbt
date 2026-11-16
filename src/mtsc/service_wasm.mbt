// The wasm-gc entry points: the language service with its host IMPORTED.
//
// This file is compiled for the `wasm-gc` backend only (see `targets` in
// `moon.pkg`). It is the counterpart of `host_js.mbt` + `service_js.mbt`
// for a runtime that loads a `.wasm` rather than a `.js` — a browser
// worker, an edge runtime, any embedder with Wasm GC — and it exists so
// the same checker runs there with the same host contract.
//
// A wasm module's imports are fixed at instantiation, so the host is not
// an argument: it is whatever the `mtsc_host` import namespace answers.
// `js/language-service-wasm.mjs` binds those imports to a
// `LanguageServiceHost`-shaped object per call, which is what lets one
// instance serve many hosts. Strings cross as JS strings
// (`use-js-builtin-string`), so a path or a source text costs no copy at
// the boundary, and every structured answer leaves as JSON — a wasm
// export returns a value, not an object graph.
//
// The imports are the host's methods, one each, with two encodings the
// boundary needs: `readFile` cannot return `undefined` across it, so
// existence is its own import (`fileExists`) and the source cache asks it
// first; and `resolveModuleName` answers `""` for "use the built-in
// resolution", `"\u0000"` for "do not follow", anything else a path —
// the encoding `host_js.mbt` uses for the same hook.

///|
fn wasm_host_file_exists(path : String) -> Bool = "mtsc_host" "fileExists"

///|
fn wasm_host_read_file(path : String) -> String = "mtsc_host" "readFile"

///|
fn wasm_host_directory_exists(path : String) -> Bool = "mtsc_host" "directoryExists"

///|
fn wasm_host_realpath(path : String) -> String = "mtsc_host" "realpath"

///|
fn wasm_host_resolve_module_name(
  specifier : String,
  containing_file : String,
) -> String = "mtsc_host" "resolveModuleName"

///|
/// The roots, one per line: a path cannot contain a newline, and a
/// string crosses the boundary where an array would need a protocol.
fn wasm_host_script_file_names() -> String = "mtsc_host" "getScriptFileNames"

///|
fn wasm_host_current_directory() -> String = "mtsc_host" "getCurrentDirectory"

///|
fn wasm_host_jsx() -> Bool = "mtsc_host" "jsx"

///|
fn wasm_host_skip_lib_check() -> Bool = "mtsc_host" "skipLibCheck"

///|
/// The host the imports describe. A value with nothing in it: every
/// answer comes from the import namespace.
priv enum MtscWasmHost {
  Imports
}

///|
impl MtscHost for MtscWasmHost with fn read_file(_, path) {
  if wasm_host_file_exists(path) {
    Some(wasm_host_read_file(path))
  } else {
    None
  }
}

///|
impl MtscHost for MtscWasmHost with fn script_file_names(_) {
  let out : Array[String] = []
  for line in wasm_host_script_file_names().split("\n") {
    if line.length() > 0 {
      out.push(line.to_owned())
    }
  }
  out
}

///|
impl MtscHost for MtscWasmHost with fn current_directory(_) {
  let dir = wasm_host_current_directory()
  if dir == "" {
    "."
  } else {
    dir
  }
}

///|
impl MtscHost for MtscWasmHost with fn compilation_settings(_) {
  { jsx: wasm_host_jsx(), skipLibCheck: wasm_host_skip_lib_check(), }
}

///|
impl MtscHost for MtscWasmHost with fn directory_exists(_, path) {
  wasm_host_directory_exists(path)
}

///|
impl MtscHost for MtscWasmHost with fn realpath(_, path) {
  wasm_host_realpath(path)
}

///|
impl MtscHost for MtscWasmHost with fn resolve_module_name(
  _,
  specifier,
  containing_file,
) {
  match wasm_host_resolve_module_name(specifier, containing_file) {
    "" => UseDefault
    "\u{0}" => External
    path => ResolvedTo(path)
  }
}

///|
fn wasm_diagnostic_json(d : MtscDiagnostic) -> Json {
  {
    "file": Json::string(d.file),
    "category": Json::string(d.category),
    "source": Json::string(d.source),
    "messageText": Json::string(d.messageText),
    "context": Json::string(d.context),
  }
}

///|
fn wasm_diagnostics_json(ds : Array[MtscDiagnostic]) -> String {
  Json::array(ds.map(wasm_diagnostic_json)).stringify()
}

///|
/// `getProgramDiagnostics()`, as a JSON array of diagnostics.
pub fn wasm_get_program_diagnostics() -> String {
  wasm_diagnostics_json(get_program_diagnostics(Imports))
}

///|
/// `getSemanticDiagnostics(fileName)`, as a JSON array.
pub fn wasm_get_semantic_diagnostics(file : String) -> String {
  wasm_diagnostics_json(get_semantic_diagnostics(Imports, file))
}

///|
/// `getSyntacticDiagnostics(fileName)`, as a JSON array.
pub fn wasm_get_syntactic_diagnostics(file : String) -> String {
  wasm_diagnostics_json(get_syntactic_diagnostics(Imports, file))
}

///|
/// `getProgramFileNames()`, as a JSON array of paths.
pub fn wasm_get_program_file_names() -> String {
  Json::array(get_program_file_names(Imports).map(Json::string)).stringify()
}

///|
/// `resolveModuleName(containingFile, moduleName)`, as a JSON object.
pub fn wasm_resolve_module_name(
  containing_file : String,
  specifier : String,
) -> String {
  let r = resolve_module_name(Imports, containing_file, specifier)
  let j : Json = {
    "resolvedFileName": Json::string(r.resolvedFileName),
    "isExternal": Json::boolean(r.isExternal),
  }
  j.stringify()
}
