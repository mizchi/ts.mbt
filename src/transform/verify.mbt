// Verify the OUTPUT, not the pass.
//
// Every liveness bug this pipeline has had ends the same way: a
// declaration is gone and a reference to it is still standing. That is
// detectable without running anything, and without trusting any of the
// analyses that made the deletion — one walk over the emitted bundle,
// asking whether every name it reads resolves to something.
//
// `ReferenceError: CODES is not defined` (Excalidraw's
// `packages/common/src/keys.ts`, deleted by a treeshake whose liveness
// walk could not see through a `TypeArgs` wrapper) would have been
// caught here. So would `mtsc entry.ts --bundle` deleting every method
// of a class whose call sites are in another module, in the sense that
// the free-variable check is the same shape of question — though not
// that instance, since a missing METHOD is not a missing binding. See
// `docs/type-aware-dce.md` (experiment E1).
//
// This is the LLVM `-verify` / Wasm-validation posture: a cheap total
// invariant, re-checked after the transforms, that does not share code
// with them. Two properties matter and are worth stating:
//
//   * It re-PARSES the emitted JavaScript rather than inspecting the
//     final AST. A verifier built on the pipeline's own in-memory state
//     can share a bug with the pipeline; one that starts from the bytes
//     cannot. It also catches emitter bugs (a lost parenthesis, a
//     swallowed statement) for free, since a bundle that no longer
//     parses is itself a violation.
//   * It is FAIL-QUIET on anything it cannot model. A verifier that
//     cries wolf gets turned off, and then it protects nothing.
//     Unresolved names are reported only when they are not a host
//     global, not an import, and not declared anywhere in the bundle.

///|
/// One thing wrong with an emitted bundle.
pub(all) struct Violation {
  // Machine-readable category, for tests and for the harnesses.
  kind : String
  name : String
  detail : String
} derive(Show)

///|
/// Names that resolve to nothing inside the bundle and are not the
/// host's. Empty means the bundle has no dangling reference.
///
/// `externals` are names the caller knows are provided from outside and
/// may not appear as import bindings in the text (a bundle emitted for
/// a CommonJS host, a name injected by a wrapper).
pub fn verify_emitted_bundle(
  js : String,
  externals? : Map[String, Bool] = {},
) -> Array[Violation] {
  let out : Array[Violation] = []
  let parsed = @parser.Parser::from_source(js).parse_module_block() catch {
    e => {
      out.push({
        kind: "unparsable",
        name: "",
        detail: "the emitted bundle does not parse: \{e}",
      })
      return out
    }
  }
  // Import bindings live on the module block, not in its statements, so
  // the symbol graph never declares them.
  let allowed : Map[String, Bool] = {}
  for name in js_runtime_global_names() {
    allowed[name] = true
  }
  for name in verifier_extra_globals() {
    allowed[name] = true
  }
  for name in externals.keys() {
    allowed[name] = true
  }
  for imp in parsed.imports {
    match imp.default_binding {
      Some(n) => allowed[n] = true
      None => ()
    }
    match imp.namespace_binding {
      Some(n) => allowed[n] = true
      None => ()
    }
    for pair in imp.named_bindings {
      allowed[pair.1] = true
    }
  }
  let g = build_symbol_graph(parsed.block, {})
  for name in g.unresolved.keys() {
    if allowed.contains(name) {
      continue
    }
    out.push({
      kind: "free-variable",
      name,
      detail: "`\{name}` is referenced but nothing in the bundle declares it, and it is not a host global or an import — a pass deleted a live binding",
    })
  }
  out
}

///|
/// Host names `js_runtime_global_names()` does not carry.
///
/// That list exists to pre-seed the linker's collision-rename table, so
/// it covers what user code *shadows*, not everything user code *reads*.
/// The additions here are the shapes a verifier meets in real emitted
/// bundles, and each one is a name no bundle declares.
fn verifier_extra_globals() -> Array[String] {
  [
    // Not bindings at all: the parser hands these to the walk as plain
    // identifiers, and no scope declares them.
    "this", "arguments", "super", "import",
    // The parser's sentinel for a declaration with no initializer:
    // `let x;` parses as `Let(x, Any, Var("__ts_no_init__"))`. It never
    // reaches the output — but this verifier RE-PARSES the output, so
    // the sentinel is recreated on the way in and then looks like a
    // free variable. Every bundle with an uninitialized `let` reported
    // it, which is the shape of noise that gets a verifier switched
    // off.
     "__ts_no_init__",
    // CommonJS / Node, which a bundle targeting Node reads directly.
     "require", "module", "exports", "__dirname", "__filename", "Buffer", "global",
    "globalThis",
    // Web platform names that appear in library code often enough to
    // matter, and that nothing declares.
     "performance", "crypto", "TextEncoder", "TextDecoder", "AbortController", "AbortSignal",
    "Event", "EventTarget", "CustomEvent", "Blob", "File", "FileReader", "FormData",
    "Headers", "Request", "Response", "ReadableStream", "WritableStream", "TransformStream",
    "MessageChannel", "MessagePort", "Worker", "SharedWorker", "BroadcastChannel",
    "WebSocket", "XMLHttpRequest", "Image", "HTMLElement", "HTMLCanvasElement", "SVGElement",
    "Node", "Element", "CanvasRenderingContext2D", "Path2D", "DOMMatrix", "DOMParser",
    "XMLSerializer", "MutationObserver", "ResizeObserver", "IntersectionObserver",
    "requestAnimationFrame", "cancelAnimationFrame", "requestIdleCallback", "getComputedStyle",
    "matchMedia", "localStorage", "sessionStorage", "indexedDB", "atob", "btoa",
    "alert", "addEventListener", "removeEventListener", "dispatchEvent", "open",
    "close", "postMessage", "scrollTo", "scrollBy", "getSelection", "caches", "OffscreenCanvas",
    "createImageBitmap", "ImageData", "FontFace", "fonts", "confirm", "prompt", "screen",
    "history", "top", "parent", "frames", "devicePixelRatio", "visualViewport", "reportError",
    // Test / bundler injections.
     "describe", "it", "test", "expect", "vi", "jest", "beforeEach", "afterEach",
    "beforeAll", "afterAll",
  ]
}
