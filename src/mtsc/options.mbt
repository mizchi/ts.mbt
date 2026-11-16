///|
/// The `strict` family the parser's option detectors read. Each one is
/// `explicit ?? strict ?? true` in tsc 7, whose `strict` defaults to true
/// (probed: a tsconfig with no `strict` reports TS2322 / TS7006 / TS2564).
/// `alwaysStrict` is deliberately absent: it changes which strict-mode
/// GRAMMAR rules apply to a script, and is emitted only when a config
/// names it or `strict` explicitly.
let strict_family_options : Array[String] = [
  "noImplicitAny", "strictNullChecks", "strictPropertyInitialization", "useUnknownInCatchVariables",
  "noImplicitThis",
]

///|
/// Options passed through verbatim when a config sets them. Their
/// detectors default to tsc's own default when the line is absent, so an
/// unset option emits nothing.
let verbatim_options : Array[String] = [
  "experimentalDecorators", "useDefineForClassFields", "noImplicitOverride", "noPropertyAccessFromIndexSignature",
  "noUnusedLocals", "importHelpers", "allowUnreachableCode", "noLib",
]

///|
/// Compiler options as the conformance harness spells them, one
/// `// @name: value` line each, for `Parser::from_source_with_jsx`'s
/// `option_header~`.
///
/// `options` is what a `tsconfig.json`'s `compilerOptions` set, as
/// `(name, value)` with booleans spelled `true` / `false` and `lib` a
/// comma-joined list; a later entry for the same name wins. The parser's
/// detectors were written for test-file headers, so this translates a
/// config into that vocabulary rather than teaching every detector a
/// second one.
///
/// `@strict:` is never written. The detectors give `@strict: false`
/// precedence over an explicit per-flag `true`, which is the opposite of
/// tsc (`strict: false, strictNullChecks: true` checks nulls), so the
/// family is resolved HERE and written flag by flag. An empty `options`
/// is an empty header, which is exactly today's behaviour.
pub fn compiler_option_header(options : Array[(String, String)]) -> String {
  if options.is_empty() {
    return ""
  }
  let given : Map[String, String] = Map([])
  for entry in options {
    given[entry.0] = entry.1
  }
  let lines : Array[String] = []
  let strict = given.get("strict")
  for name in strict_family_options {
    let value = match given.get(name) {
      Some(v) => v
      None =>
        match strict {
          Some(v) => v
          None => "true"
        }
    }
    lines.push("// @\{name}: \{value}")
  }
  match given.get("alwaysStrict") {
    Some(v) => lines.push("// @alwaysStrict: \{v}")
    None =>
      match strict {
        Some(v) => lines.push("// @alwaysStrict: \{v}")
        None => ()
      }
  }
  for name in verbatim_options {
    match given.get(name) {
      Some(v) => lines.push("// @\{name}: \{v}")
      None => ()
    }
  }
  // The detectors for these lower-case the window, and the target-based
  // `useDefineForClassFields` default matches a lower-case spelling.
  for name in ["target", "module", "lib"] {
    match given.get(name) {
      Some(v) => lines.push("// @\{name}: \{v.to_lower()}")
      None => ()
    }
  }
  lines.join("\n") + "\n"
}
