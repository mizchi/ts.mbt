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
/// `host.getCompilationSettings().skipLibCheck`, read as a boolean.
extern "js" fn mtsc_js_host_skip_lib_check(host : MtscJsHost) -> Bool =
  #| function(host) {
  #|   if (typeof host.getCompilationSettings !== "function") return false;
  #|   const options = host.getCompilationSettings();
  #|   return !!(options && options.skipLibCheck);
  #| }

///|
/// `host.directoryExists(path)`, or `true` when the host has none — the
/// same default TypeScript applies, so the file probes decide.
extern "js" fn mtsc_js_host_directory_exists(
  host : MtscJsHost,
  path : String,
) -> Bool =
  #| function(host, path) {
  #|   if (typeof host.directoryExists !== "function") return true;
  #|   try { return !!host.directoryExists(path); } catch (e) { return false; }
  #| }

///|
/// `host.realpath(path)`, or `path` when the host has none.
extern "js" fn mtsc_js_host_realpath(
  host : MtscJsHost,
  path : String,
) -> String =
  #| function(host, path) {
  #|   if (typeof host.realpath !== "function") return path;
  #|   try {
  #|     const real = host.realpath(path);
  #|     return (typeof real === "string" && real.length > 0) ? real : path;
  #|   } catch (e) {
  #|     return path;
  #|   }
  #| }

///|
/// `host.resolveModuleNames([specifier], containingFile)[0]`, encoded as
/// one string: `""` for "use the built-in resolution", `"\u0000"` for
/// "do not follow", anything else a path.
///
/// TypeScript's hook takes a batch and returns `ResolvedModule |
/// undefined` per name. `undefined` here means the host has no opinion —
/// a host that maps only its own aliases should not have to reimplement
/// `node_modules` — and `null` means "external", which TypeScript has no
/// spelling for and a CDN-backed host needs.
extern "js" fn mtsc_js_host_resolve_module_name(
  host : MtscJsHost,
  specifier : String,
  containing_file : String,
) -> String =
  #| function(host, specifier, containingFile) {
  #|   if (typeof host.resolveModuleNames !== "function") return "";
  #|   let answer;
  #|   try {
  #|     const out = host.resolveModuleNames([specifier], containingFile);
  #|     answer = Array.isArray(out) ? out[0] : undefined;
  #|   } catch (e) {
  #|     return "";
  #|   }
  #|   if (answer === null) return "\u0000";
  #|   if (answer && typeof answer.resolvedFileName === "string" &&
  #|       answer.resolvedFileName.length > 0) {
  #|     return answer.resolvedFileName;
  #|   }
  #|   return "";
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
  {
    jsx: mtsc_js_host_jsx(self),
    skipLibCheck: mtsc_js_host_skip_lib_check(self),
  }
}

///|
impl MtscHost for MtscJsHost with fn directory_exists(self, path) {
  mtsc_js_host_directory_exists(self, path)
}

///|
impl MtscHost for MtscJsHost with fn realpath(self, path) {
  mtsc_js_host_realpath(self, path)
}

///|
impl MtscHost for MtscJsHost with fn resolve_module_name(
  self,
  specifier,
  containing_file,
) {
  match mtsc_js_host_resolve_module_name(self, specifier, containing_file) {
    "" => UseDefault
    "\u{0}" => External
    path => ResolvedTo(path)
  }
}
