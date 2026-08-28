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
  // Is the output JavaScript at all?
  //
  // The re-parse above uses the TypeScript parser, which is what makes
  // the free-variable check possible — and also means it happily accepts
  // syntax Node would reject. A pass that leaves TypeScript in the
  // output therefore passed this verifier silently. It happened twice:
  // `import { type Point } from "…"` survived a `record_external_import`
  // change, and un-lowered JSX (`{cond && <><span/></>}`) survived the
  // whole corpus.
  //
  // The check is the re-parse's own product: a JavaScript file cannot
  // parse to a `JsxElement` or an `As` node, so finding one means the
  // TEXT contained the construct. No second parser needed.
  for imp in parsed.imports {
    if imp.type_only {
      out.push({
        kind: "not-javascript",
        name: imp.module_spec,
        detail: "the bundle contains `import type … from \"\{imp.module_spec}\"` — TypeScript syntax, so this is not a JavaScript module",
      })
    }
    for i, pair in imp.named_bindings {
      if i < imp.named_type_only.length() && imp.named_type_only[i] {
        out.push({
          kind: "not-javascript",
          name: pair.0,
          detail: "the bundle imports `{ type \{pair.0} }` from \"\{imp.module_spec}\" — a `type` specifier is TypeScript syntax, so this is not a JavaScript module",
        })
      }
    }
  }
  for kind in typescript_constructs_in_block(parsed.block) {
    out.push({
      kind: "not-javascript",
      name: kind,
      detail: "the bundle contains a `\{kind}` construct, which is TypeScript and not JavaScript — a lowering pass did not run over it",
    })
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
/// The TypeScript-only constructs present in `block`, as construct names,
/// each reported once.
///
/// Fail-quiet like the rest of this file: the walk below has an arm for
/// every statement form and for the expression forms that carry
/// sub-expressions, and ends in a catch-all. A form it does not descend
/// into hides a violation rather than inventing one — which is the right
/// direction, and a real cost, so `verify_wbtest.mbt` feeds it each
/// construct in each position and asserts the detection instead of
/// assuming it.
///
/// `TypeArgs` is deliberately NOT on the list. `f<T>(x)` is TypeScript,
/// but `a < b > (c)` is valid JavaScript that this parser may resolve the
/// same way, and a verifier that reports valid output gets turned off.
fn typescript_constructs_in_block(block : @ast.TsBlock) -> Array[String] {
  let seen : Map[String, Bool] = {}
  ts_walk_block(block, seen)
  let names : Array[String] = []
  for entry in seen {
    names.push(entry.0)
  }
  names.sort()
  names
}

///|
fn ts_walk_block(block : @ast.TsBlock, seen : Map[String, Bool]) -> Unit {
  for s in block.stmts {
    ts_walk_stmt(s, seen)
  }
}

///|
fn ts_walk_exprs(exprs : Array[@ast.TsExpr], seen : Map[String, Bool]) -> Unit {
  for e in exprs {
    ts_walk_expr(e, seen)
  }
}

///|
fn ts_walk_class(
  decl : @ast.TsClassDecl,
  ctor : @ast.TsFunc?,
  seen : Map[String, Bool],
) -> Unit {
  match ctor {
    Some(f) => ts_walk_block(f.body, seen)
    None => ()
  }
  for m in decl.methods {
    match m.body {
      Some(b) => ts_walk_block(b, seen)
      None => ()
    }
  }
  for sf in decl.static_field_inits {
    ts_walk_expr(sf.1, seen)
  }
  match decl.base_expr {
    Some(b) => ts_walk_expr(b, seen)
    None => ()
  }
}

///|
fn ts_walk_expr(e : @ast.TsExpr, seen : Map[String, Bool]) -> Unit {
  match e {
    JsxElement(tag, attrs, children) => {
      // The tag is in the name so a violation on a 3 MB bundle points at
      // the construct instead of at the whole file.
      seen["JSX element <" + tag + ">"] = true
      for a in attrs {
        match a.1 {
          Some(v) => ts_walk_expr(v, seen)
          None => ()
        }
      }
      ts_walk_exprs(children, seen)
    }
    As(inner, _) => {
      seen["`as` type assertion"] = true
      ts_walk_expr(inner, seen)
    }
    Satisfies(inner, _) => {
      seen["`satisfies` operator"] = true
      ts_walk_expr(inner, seen)
    }
    NonNull(inner) => {
      seen["`!` non-null assertion"] = true
      ts_walk_expr(inner, seen)
    }
    // Everything below carries sub-expressions and is otherwise ordinary
    // JavaScript.
    BinOp(_, a, b) | Seq(a, b) => {
      ts_walk_expr(a, seen)
      ts_walk_expr(b, seen)
    }
    UnaryOp(_, i)
    | Spread(i)
    | Await(i)
    | YieldStar(i)
    | OptionalChain(i)
    | PureCall(i)
    | TypeArgs(_, i)
    | PropAccess(i, _) => ts_walk_expr(i, seen)
    Cond(c, t, f) => {
      ts_walk_expr(c, seen)
      ts_walk_expr(t, seen)
      ts_walk_expr(f, seen)
    }
    Call(_, args) | New(_, args) => ts_walk_exprs(args, seen)
    CallExpr(callee, args) | NewExpr(callee, args) => {
      ts_walk_expr(callee, seen)
      ts_walk_exprs(args, seen)
    }
    MethodCall(recv, _, args) => {
      ts_walk_expr(recv, seen)
      ts_walk_exprs(args, seen)
    }
    IndexAccess(a, b) | ComputedProp(a, b) => {
      ts_walk_expr(a, seen)
      ts_walk_expr(b, seen)
    }
    ArrayLit(items) => ts_walk_exprs(items, seen)
    ObjectLit(entries) =>
      for ent in entries {
        ts_walk_expr(ent.1, seen)
      }
    AssignExpr(_, v) | AssignPattern(_, v) => ts_walk_expr(v, seen)
    CompoundAssignExpr(t, _, v) => {
      ts_walk_expr(t, seen)
      ts_walk_expr(v, seen)
    }
    PropAssignExpr(recv, _, v) => {
      ts_walk_expr(recv, seen)
      ts_walk_expr(v, seen)
    }
    IndexAssignExpr(recv, idx, v) => {
      ts_walk_expr(recv, seen)
      ts_walk_expr(idx, seen)
      ts_walk_expr(v, seen)
    }
    Yield(opt) =>
      match opt {
        Some(i) => ts_walk_expr(i, seen)
        None => ()
      }
    DynamicImport(spec, opts) => {
      ts_walk_expr(spec, seen)
      match opts {
        Some(o) => ts_walk_expr(o, seen)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      ts_walk_expr(tag, seen)
      ts_walk_exprs(exprs, seen)
    }
    TemplateLiteral(_, exprs) => ts_walk_exprs(exprs, seen)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(inner) => ts_walk_expr(inner, seen)
        ArrowBlock(b) => ts_walk_block(b, seen)
      }
    FuncExpr(f) => ts_walk_block(f.body, seen)
    NativeClassExpr(decl, ctor) => ts_walk_class(decl, ctor, seen)
    _ => ()
  }
}

///|
fn ts_walk_stmt(s : @ast.TsStmt, seen : Map[String, Bool]) -> Unit {
  match s {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) => ts_walk_expr(e, seen)
    Expr(e) | Throw(e) | Assign(_, e) | CompoundAssign(_, _, e) =>
      ts_walk_expr(e, seen)
    Return(opt) =>
      match opt {
        Some(e) => ts_walk_expr(e, seen)
        None => ()
      }
    PropAssign(recv, _, v) => {
      ts_walk_expr(recv, seen)
      ts_walk_expr(v, seen)
    }
    IndexAssign(recv, idx, v) => {
      ts_walk_expr(recv, seen)
      ts_walk_expr(idx, seen)
      ts_walk_expr(v, seen)
    }
    If(c, t, eopt) => {
      ts_walk_expr(c, seen)
      ts_walk_block(t, seen)
      match eopt {
        Some(b) => ts_walk_block(b, seen)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      ts_walk_expr(c, seen)
      ts_walk_block(b, seen)
    }
    For(init, cond, update, body) => {
      match init {
        Some(st) => ts_walk_stmt(st, seen)
        None => ()
      }
      match cond {
        Some(ex) => ts_walk_expr(ex, seen)
        None => ()
      }
      match update {
        Some(st) => ts_walk_stmt(st, seen)
        None => ()
      }
      ts_walk_block(body, seen)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      ts_walk_expr(iter, seen)
      ts_walk_block(body, seen)
    }
    Switch(e, cases) => {
      ts_walk_expr(e, seen)
      for c in cases {
        match c.test_expr {
          Some(te) => ts_walk_expr(te, seen)
          None => ()
        }
        ts_walk_block(c.body, seen)
      }
    }
    Try(b, _, cb, fb) => {
      ts_walk_block(b, seen)
      match cb {
        Some(x) => ts_walk_block(x, seen)
        None => ()
      }
      match fb {
        Some(x) => ts_walk_block(x, seen)
        None => ()
      }
    }
    Block(b) => ts_walk_block(b, seen)
    Label(_, inner) => ts_walk_stmt(inner, seen)
    NativeClassStmt(decl, ctor) => ts_walk_class(decl, ctor, seen)
    _ => ()
  }
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
    "ClipboardEvent", "ClipboardItem", "DataTransfer", "Clipboard", "Selection",
    "Range", "MediaQueryList", "PointerEvent", "TouchEvent", "KeyboardEvent", "MouseEvent",
    "WheelEvent", "DragEvent", "InputEvent", "FocusEvent", "SVGSVGElement", "HTMLInputElement",
    "HTMLTextAreaElement", "HTMLDivElement", "HTMLImageElement", "HTMLAnchorElement",
    // Test / bundler injections.
     "describe", "it", "test", "expect", "vi", "jest", "beforeEach", "afterEach",
    "beforeAll", "afterAll",
  ]
}
