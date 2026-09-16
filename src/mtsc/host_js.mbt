// The JavaScript host: an `MtscHost` backed by a caller-supplied JS object.
//
// This file is compiled for the `js` backend only (see `targets` in
// `moon.pkg`), because every declaration in it is an `extern "js"`.
//
// The object a caller passes is TypeScript's `LanguageServiceHost`,
// spelled the way TypeScript spells it: `readFile`,
// `getScriptFileNames`, `getCurrentDirectory`, `getCompilationSettings`.
// That is the whole reason for the naming — a build tool that already
// has a `ts.LanguageServiceHost` should be able to hand the same object
// over, so `getScriptSnapshot` is accepted as a fallback for `readFile`
// (TypeScript's hosts are required to have the former and only
// optionally have the latter).
//
// Everything crossing this boundary was measured rather than assumed:
// a JS `undefined` arrives as `None` for a `String?` return, a JS array
// of strings arrives as a `FixedArray[String]` (`Array` in an FFI
// signature is deprecated), and a MoonBit struct leaves as a plain
// object whose keys are the field names. The one thing NOT relied on is
// a struct crossing INWARDS as an `extern` return value — the compiler
// options are read field by field, so a host may omit
// `getCompilationSettings` and get the default instead of a shape
// mismatch.

///|
/// A caller-supplied `LanguageServiceHost`, opaque to MoonBit.
#external
pub type MtscJsHost

///|
/// `host.readFile(path)`, falling back to `getScriptSnapshot`.
///
/// Returns `undefined` for anything unreadable, which is what the
/// resolver reads as "no file here". Throwing is caught for the same
/// reason: a host wired straight to `fs.readFileSync` raises ENOENT for
/// a path that does not exist, and resolution probes many paths that do
/// not exist — so an exception here is an ordinary answer, not a fault.
extern "js" fn mtsc_js_host_read_file(
  host : MtscJsHost,
  path : String,
) -> String? =
  #| function(host, path) {
  #|   try {
  #|     if (typeof host.readFile === "function") {
  #|       const text = host.readFile(path);
  #|       return (text === undefined || text === null) ? undefined : text;
  #|     }
  #|     if (typeof host.getScriptSnapshot === "function") {
  #|       const snapshot = host.getScriptSnapshot(path);
  #|       if (snapshot === undefined || snapshot === null) return undefined;
  #|       return snapshot.getText(0, snapshot.getLength());
  #|     }
  #|     return undefined;
  #|   } catch (e) {
  #|     return undefined;
  #|   }
  #| }

///|
/// `host.getScriptFileNames()`.
///
/// A missing or non-array answer becomes an empty program rather than a
/// crash; `get_program_diagnostics` then reports nothing, and a caller
/// who meant to name roots sees an empty `getProgramFileNames()` — which
/// is the observable that says so.
extern "js" fn mtsc_js_host_script_file_names(
  host : MtscJsHost,
) -> FixedArray[String] =
  #| function(host) {
  #|   if (typeof host.getScriptFileNames !== "function") return [];
  #|   const names = host.getScriptFileNames();
  #|   return Array.isArray(names) ? names.map(String) : [];
  #| }

///|
/// `host.getCurrentDirectory()`, defaulting to `"."`.
extern "js" fn mtsc_js_host_current_directory(host : MtscJsHost) -> String =
  #| function(host) {
  #|   if (typeof host.getCurrentDirectory !== "function") return ".";
  #|   const dir = host.getCurrentDirectory();
  #|   return (typeof dir === "string" && dir.length > 0) ? dir : ".";
  #| }

///|
/// `host.getCompilationSettings().jsx`, read as a boolean.
///
/// One extern per option rather than one returning the whole struct:
/// this way an absent `getCompilationSettings` is a default instead of a
/// shape the FFI has to reconstruct, and `ts.CompilerOptions.jsx` — an
/// enum in TypeScript, where `JsxEmit.None` is 0 — is truthy exactly
/// when JSX is enabled.
extern "js" fn mtsc_js_host_jsx(host : MtscJsHost) -> Bool =
  #| function(host) {
  #|   if (typeof host.getCompilationSettings !== "function") return false;
  #|   const options = host.getCompilationSettings();
  #|   return !!(options && options.jsx);
  #| }

///|
impl MtscHost for MtscJsHost with fn read_file(self, path) {
  mtsc_js_host_read_file(self, path)
}

///|
impl MtscHost for MtscJsHost with fn script_file_names(self) {
  let names = mtsc_js_host_script_file_names(self)
  let out : Array[String] = []
  for name in names {
    out.push(name)
  }
  out
}

///|
impl MtscHost for MtscJsHost with fn current_directory(self) {
  mtsc_js_host_current_directory(self)
}

///|
impl MtscHost for MtscJsHost with fn compilation_settings(self) {
  { jsx: mtsc_js_host_jsx(self), }
}
