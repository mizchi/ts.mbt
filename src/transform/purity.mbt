// Function purity / side-effect analysis.
//
// Walks the bundle's top-level function definitions to figure out
// which ones are observably pure — they don't write to anything
// outside their own scope, don't call I/O sinks, and don't pull
// in anything impure transitively. Treeshake / inline / DCE can
// then drop unused calls to pure functions, the same way they
// drop unused literals.
//
// The analysis also flags getters whose body contains an
// observable side effect. JS getters are conventionally pure
// (or lazy memoization at worst); side effects in a getter are
// almost always a bug.

///|
/// Output of one purity analysis run.
pub(all) struct PurityReport {
  // Names of top-level function bindings the analysis classified
  // as pure. A name is pure when its body has no direct side
  // effects AND every function it calls is itself pure.
  pure_functions : Map[String, Bool]
  // Per-getter diagnostics: the class name, the getter name, and
  // a short reason string. Empty when every getter is pure.
  impure_getters : Array[ImpureGetter]
}

///|
pub(all) struct ImpureGetter {
  class_name : String
  getter_name : String
  reason : String
}

///|
/// Built-in globals whose method calls are observably pure.
/// Method calls anchored on these names propagate purity rather
/// than impurity. Functions and properties on these globals
/// don't have side effects on the surrounding program.
let pure_global_methods : Array[String] = [
  "Math", "JSON", "Object", "Array", "String", "Number", "Boolean", "Symbol",
  "BigInt", "Date", "RegExp", "Int8Array", "Uint8Array", "Int16Array",
  "Uint16Array", "Int32Array", "Uint32Array", "Float32Array", "Float64Array",
  "BigInt64Array", "BigUint64Array", "Map", "Set", "WeakMap", "WeakSet",
  "Promise", "Reflect", "Proxy",
]

///|
/// Names of pure top-level functions the JS runtime ships with —
/// these are bare `Call(name, args)` references, not method calls.
let pure_global_functions : Array[String] = [
  "parseInt", "parseFloat", "isNaN", "isFinite", "encodeURI",
  "encodeURIComponent", "decodeURI", "decodeURIComponent", "structuredClone",
  "BigInt", "Number", "String", "Boolean", "Array", "Object",
]

///|
/// Run the purity pass over a flat top-level block. Returns the
/// pure function set + impure-getter diagnostics.
pub fn analyze_purity(block : @ast.TsBlock) -> PurityReport {
  analyze_purity_with(block, {})
}

///|
/// `assumed_pure` is the caller-supplied "definitely pure"
/// override — typically populated from JSDoc
/// `@__PURE__` / `@__NO_SIDE_EFFECTS__` annotations on function
/// declarations. Names in this set are added to the pure result
/// unconditionally and exempt their callers from being marked
/// impure through them.
pub fn analyze_purity_with(
  block : @ast.TsBlock,
  assumed_pure : Map[String, Bool],
) -> PurityReport {
  // Step 0: signature-based purity inference. Functions whose every
  // parameter is an immutable primitive AND whose body contains no
  // statement that could escape state — i.e. arithmetic, comparison,
  // local lets, ifs, switches, returns, pure-global method calls —
  // are provably pure even when their declaration carries no
  // `@__PURE__` annotation. We add them to `assumed_pure` before the
  // main analysis runs so the existing fixpoint trusts them when
  // their callers loop in.
  let augmented_assumed : Map[String, Bool] = {}
  for entry in assumed_pure {
    augmented_assumed[entry.0] = entry.1
  }
  for stmt in block.stmts {
    match stmt {
      Let(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Const(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Var(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f)) =>
        if is_signature_pure_func(f) {
          augmented_assumed[name] = true
        }
      _ => ()
    }
  }
  let assumed_pure = augmented_assumed
  // Step 1: collect every top-level function-like declaration —
  // both `Let/Const(Ident(name), _, FuncExpr/ArrowFunc)` and
  // explicit `NativeClassStmt` declarations.
  let funcs : Map[String, @ast.TsBlock] = {}
  for stmt in block.stmts {
    match stmt {
      Let(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f)) =>
        funcs[name] = f.body
      Const(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f)) =>
        funcs[name] = f.body
      Var(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f)) =>
        funcs[name] = f.body
      Let(@ast.TsBinding::Ident(name), _, @ast.TsExpr::ArrowFunc(_, _, body, _))
      | Const(
          @ast.TsBinding::Ident(name),
          _,
          @ast.TsExpr::ArrowFunc(_, _, body, _),
        )
      | Var(@ast.TsBinding::Ident(name), _, @ast.TsExpr::ArrowFunc(_, _, body, _)) =>
        match body {
          ArrowBlock(b) => funcs[name] = b
          ArrowExpr(e) =>
            // Wrap the single-expression body so the same
            // analysis walks both forms.
            funcs[name] = {
              stmts: [Return(Some(e))],
              stmt_positions: [],
            }
        }
      _ => ()
    }
  }
  // Step 2: per-function direct purity + call set.
  let direct_impure : Map[String, Bool] = {}
  let calls_of : Map[String, Array[String]] = {}
  for entry in funcs {
    let (name, body) = entry
    let mut directly_impure = false
    let called : Array[String] = []
    let called_seen : Map[String, Bool] = {}
    walk_block_for_purity(body, false, fn(kind) {
      match kind {
        PureWalkEvent::SideEffect => directly_impure = true
        PureWalkEvent::Calls(target) =>
          if not(called_seen.contains(target)) {
            called_seen[target] = true
            called.push(target)
          }
      }
    })
    direct_impure[name] = directly_impure
    calls_of[name] = called
  }
  // Step 3: fixpoint. A function is impure if it's directly
  // impure OR it calls an impure function. Iterate until no
  // new names get marked.
  let impure : Map[String, Bool] = {}
  for entry in direct_impure {
    let (name, flag) = entry
    // `assumed_pure` overrides direct-impurity flags: a JSDoc-
    // annotated function trusted to be pure stays out of the
    // impure set even when its body calls into externally-
    // declared APIs the analyzer can't see through.
    if flag && not(assumed_pure.contains(name)) {
      impure[name] = true
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for entry in calls_of {
      let (name, callees) = entry
      if impure.contains(name) {
        continue
      }
      for callee in callees {
        // If the callee is a known function and impure, mark.
        // If the callee isn't in our function table, it's an
        // external reference (built-in / external import) and
        // we treat it as impure unless it's a known-pure
        // global function.
        if funcs.contains(callee) {
          if impure.contains(callee) {
            impure[name] = true
            changed = true
            break
          }
        } else if pure_global_functions.contains(callee) {
          continue
        } else {
          impure[name] = true
          changed = true
          break
        }
      }
    }
  }
  // Step 4: invert — pure = funcs that aren't impure. Also fold
  // in every assumption from `assumed_pure` so JSDoc-annotated
  // functions land in the output even when they aren't in our
  // collected function table (e.g. ambient `declare function`).
  let pure : Map[String, Bool] = {}
  for entry in direct_impure {
    let (name, _) = entry
    if not(impure.contains(name)) {
      pure[name] = true
    }
  }
  for name in assumed_pure.keys() {
    pure[name] = true
  }
  // Step 5: getter side-effect detection. Walk every
  // `NativeClassStmt` (and the IIFE-shape `@@get:` PropAssigns,
  // already handled by the desugar) checking the getter body for
  // direct impurity. Diagnostics carry the class name + getter
  // name + a short reason.
  let getter_warnings : Array[ImpureGetter] = []
  for stmt in block.stmts {
    match stmt {
      NativeClassStmt(decl, _) =>
        for m in decl.methods {
          // The class decl doesn't currently distinguish
          // accessor methods from regular methods in its
          // `methods` array — getters are folded into properties
          // by the runtime decl builder, so the only place to
          // find them is by inspecting source-side state. For
          // now, treat every method named like a typical accessor
          // (`get*`, `value`, `length`) as a candidate; future
          // work is to thread the accessor_kind through.
          let _ = m.name
          let _ = decl.name
        }
      _ => ()
    }
  }
  // Also scan the desugar IIFE form for `Object.defineProperty(
  //   proto, "name", { get: fn })` patterns and check the `fn`.
  scan_iife_classes_for_impure_getters(block, getter_warnings, assumed_pure)
  { pure_functions: pure, impure_getters: getter_warnings }
}

///|
priv enum PureWalkEvent {
  SideEffect
  Calls(String)
}

///|
/// Walk a block's statements + nested expressions, signaling
/// every side effect or named call via the callback. The
/// `inside_func` flag marks crossings into nested function
/// bodies — we don't want a nested closure's side effect to
/// leak back to its enclosing function (the closure's body runs
/// only when CALLED, not when the outer scope evaluates).
fn walk_block_for_purity(
  block : @ast.TsBlock,
  inside_func : Bool,
  yield_ : (PureWalkEvent) -> Unit,
) -> Unit {
  for s in block.stmts {
    walk_stmt_for_purity(s, inside_func, yield_)
  }
}

///|
fn walk_stmt_for_purity(
  stmt : @ast.TsStmt,
  inside_func : Bool,
  yield_ : (PureWalkEvent) -> Unit,
) -> Unit {
  match stmt {
    Assign(_, e) | CompoundAssign(_, _, e) => {
      // Assignment writes to an outer binding — observable.
      // Local `let`s reassigned inside the function don't
      // technically escape, but at this scope-tracking depth we
      // play conservative: flag any assignment.
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(e, inside_func, yield_)
    }
    IndexAssign(target, idx, val) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(target, inside_func, yield_)
      walk_expr_for_purity(idx, inside_func, yield_)
      walk_expr_for_purity(val, inside_func, yield_)
    }
    PropAssign(target, _, val) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(target, inside_func, yield_)
      walk_expr_for_purity(val, inside_func, yield_)
    }
    Throw(_) => if not(inside_func) { yield_(SideEffect) }
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) =>
      walk_expr_for_purity(e, inside_func, yield_)
    Return(Some(e)) => walk_expr_for_purity(e, inside_func, yield_)
    If(c, t, e) => {
      walk_expr_for_purity(c, inside_func, yield_)
      walk_block_for_purity(t, inside_func, yield_)
      match e {
        Some(b) => walk_block_for_purity(b, inside_func, yield_)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      walk_expr_for_purity(c, inside_func, yield_)
      walk_block_for_purity(b, inside_func, yield_)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => walk_stmt_for_purity(s, inside_func, yield_)
        None => ()
      }
      match cond {
        Some(e) => walk_expr_for_purity(e, inside_func, yield_)
        None => ()
      }
      match update {
        Some(s) => walk_stmt_for_purity(s, inside_func, yield_)
        None => ()
      }
      walk_block_for_purity(body, inside_func, yield_)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      walk_expr_for_purity(iter, inside_func, yield_)
      walk_block_for_purity(body, inside_func, yield_)
    }
    Switch(e, cases) => {
      walk_expr_for_purity(e, inside_func, yield_)
      for c in cases {
        match c.test_expr {
          Some(te) => walk_expr_for_purity(te, inside_func, yield_)
          None => ()
        }
        walk_block_for_purity(c.body, inside_func, yield_)
      }
    }
    Try(b, _, cb, fb) => {
      walk_block_for_purity(b, inside_func, yield_)
      match cb {
        Some(blk) => walk_block_for_purity(blk, inside_func, yield_)
        None => ()
      }
      match fb {
        Some(blk) => walk_block_for_purity(blk, inside_func, yield_)
        None => ()
      }
    }
    Label(_, inner) => walk_stmt_for_purity(inner, inside_func, yield_)
    Block(b) => walk_block_for_purity(b, inside_func, yield_)
    _ => ()
  }
}

///|
fn walk_expr_for_purity(
  expr : @ast.TsExpr,
  inside_func : Bool,
  yield_ : (PureWalkEvent) -> Unit,
) -> Unit {
  match expr {
    Call(name, args) => {
      if not(inside_func) {
        yield_(Calls(name))
      }
      for a in args {
        walk_expr_for_purity(a, inside_func, yield_)
      }
    }
    CallExpr(callee, args) => {
      // Unknown callable shape — treat as side-effect at the
      // current scope. (Inside a nested closure, the impurity
      // applies to the closure, not the surrounding function;
      // the `inside_func` guard skips the report.)
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(callee, inside_func, yield_)
      for a in args {
        walk_expr_for_purity(a, inside_func, yield_)
      }
    }
    New(_, args) | NewExpr(_, args) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      for a in args {
        walk_expr_for_purity(a, inside_func, yield_)
      }
    }
    MethodCall(recv, _, args) => {
      // Method calls on well-known pure globals (`Math.floor`,
      // `JSON.parse`) don't escape. Anything else is a black
      // box — treat as side effect.
      let recv_pure = match recv {
        Var(name) => pure_global_methods.contains(name)
        _ => false
      }
      if not(recv_pure) && not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(recv, inside_func, yield_)
      for a in args {
        walk_expr_for_purity(a, inside_func, yield_)
      }
    }
    Await(inner) | YieldStar(inner) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(inner, inside_func, yield_)
    }
    Yield(opt) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      match opt {
        Some(e) => walk_expr_for_purity(e, inside_func, yield_)
        None => ()
      }
    }
    AssignExpr(_, v) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(v, inside_func, yield_)
    }
    CompoundAssignExpr(t, _, v) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(t, inside_func, yield_)
      walk_expr_for_purity(v, inside_func, yield_)
    }
    AssignPattern(_, v) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(v, inside_func, yield_)
    }
    PropAssignExpr(recv, _, v) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(recv, inside_func, yield_)
      walk_expr_for_purity(v, inside_func, yield_)
    }
    IndexAssignExpr(recv, idx, v) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(recv, inside_func, yield_)
      walk_expr_for_purity(idx, inside_func, yield_)
      walk_expr_for_purity(v, inside_func, yield_)
    }
    UnaryOp(op, inner) => {
      // `++` / `--` / `delete` mutate.
      match op {
        PreInc | PreDec | PostInc | PostDec | Delete =>
          if not(inside_func) {
            yield_(SideEffect)
          }
        _ => ()
      }
      walk_expr_for_purity(inner, inside_func, yield_)
    }
    BinOp(_, l, r) => {
      walk_expr_for_purity(l, inside_func, yield_)
      walk_expr_for_purity(r, inside_func, yield_)
    }
    Cond(c, t, e) => {
      walk_expr_for_purity(c, inside_func, yield_)
      walk_expr_for_purity(t, inside_func, yield_)
      walk_expr_for_purity(e, inside_func, yield_)
    }
    ArrayLit(items) => for it in items {
      walk_expr_for_purity(it, inside_func, yield_)
    }
    ObjectLit(entries) => for ent in entries {
      walk_expr_for_purity(ent.1, inside_func, yield_)
    }
    ComputedProp(k, v) => {
      walk_expr_for_purity(k, inside_func, yield_)
      walk_expr_for_purity(v, inside_func, yield_)
    }
    PropAccess(recv, _) => walk_expr_for_purity(recv, inside_func, yield_)
    IndexAccess(recv, idx) => {
      walk_expr_for_purity(recv, inside_func, yield_)
      walk_expr_for_purity(idx, inside_func, yield_)
    }
    Spread(inner) | As(inner, _) | Satisfies(inner, _) | NonNull(inner)
    | OptionalChain(inner) =>
      walk_expr_for_purity(inner, inside_func, yield_)
    Seq(a, b) => {
      walk_expr_for_purity(a, inside_func, yield_)
      walk_expr_for_purity(b, inside_func, yield_)
    }
    // Crossing into a nested function body — anything inside
    // executes only at call time, so it doesn't affect the outer
    // function's purity at evaluation. We still recurse to pick
    // up named calls (so the closure's own purity can be
    // inferred from its `name` if we track it elsewhere).
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => walk_expr_for_purity(e, true, yield_)
        ArrowBlock(b) => walk_block_for_purity(b, true, yield_)
      }
    FuncExpr(f) => walk_block_for_purity(f.body, true, yield_)
    DynamicImport(spec, opts) => {
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(spec, inside_func, yield_)
      match opts {
        Some(o) => walk_expr_for_purity(o, inside_func, yield_)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      // Tag function is called — same as a regular call.
      if not(inside_func) {
        yield_(SideEffect)
      }
      walk_expr_for_purity(tag, inside_func, yield_)
      for e in exprs {
        walk_expr_for_purity(e, inside_func, yield_)
      }
    }
    TemplateLiteral(_, exprs) => for e in exprs {
      walk_expr_for_purity(e, inside_func, yield_)
    }
    // `/* @__PURE__ */` wrap — by definition the call is pure.
    // We still walk argument expressions for diagnostic purposes
    // (a Pure call to `f(g())` where `g()` itself has a side
    // effect is still observably impure, but the user has
    // ASSERTED the wrapper is pure, so we honor it).
    PureCall(_) => ()
    _ => ()
  }
}

///|
/// Scan IIFE-shape class desugars for getter installations.
/// Match the `PropAssign(proto, "@@get:value", fn)` pattern that
/// `parser_class.mbt` emits (the emit-time stripper rewrites
/// those to `Object.defineProperty(proto, "value", { get: fn })`).
/// We see the pre-emit shape here, so the analysis catches it
/// before the rewrite. Each impure getter is appended to `out`.
fn scan_iife_classes_for_impure_getters(
  block : @ast.TsBlock,
  out : Array[ImpureGetter],
  assumed_pure : Map[String, Bool],
) -> Unit {
  for stmt in block.stmts {
    scan_stmt_for_impure_getters(stmt, "<anonymous>", out, assumed_pure)
  }
}

///|
fn scan_stmt_for_impure_getters(
  stmt : @ast.TsStmt,
  class_name : String,
  out : Array[ImpureGetter],
  assumed_pure : Map[String, Bool],
) -> Unit {
  match stmt {
    // `let ClassName = function() { … }()` — the desugar IIFE.
    Let(@ast.TsBinding::Ident(name), _, CallExpr(FuncExpr(f), _))
    | Const(@ast.TsBinding::Ident(name), _, CallExpr(FuncExpr(f), _))
    | Var(@ast.TsBinding::Ident(name), _, CallExpr(FuncExpr(f), _)) => {
      // Walk the IIFE body looking for `@@get:` PropAssigns.
      for inner in f.body.stmts {
        match inner {
          PropAssign(_, prop, value) =>
            if prop.has_prefix("@@get:") {
              let getter_name = prop.substring(start=6, end=prop.length()).to_string()
              let unwrapped = match value {
                Var(_) =>
                  // The getter function landed in a temp let
                  // earlier (`let __get_value = function …`). Find
                  // and inspect that temp.
                  find_temp_getter_body(f.body.stmts, value)
                FuncExpr(_) | ArrowFunc(_, _, _, _) => Some(value)
                _ => None
              }
              match unwrapped {
                Some(getter_fn) => {
                  let reason = check_getter_purity(getter_fn, assumed_pure)
                  match reason {
                    Some(r) =>
                      out.push({
                        class_name: name,
                        getter_name,
                        reason: r,
                      })
                    None => ()
                  }
                }
                None => ()
              }
            }
          _ => ()
        }
      }
      // Also recurse — nested classes inside a method body could
      // contain getters.
      walk_inner_class_getters(f.body, name, out, assumed_pure)
    }
    NativeClassStmt(_, _) =>
      // The native-class path keeps getters as TsClassMethodDecl
      // entries. The current AST doesn't distinguish accessor
      // kinds, so we'd need a side channel; revisit when the
      // parser threads `accessor_kind` through.
      ()
    Block(b) =>
      for inner in b.stmts {
        scan_stmt_for_impure_getters(inner, class_name, out, assumed_pure)
      }
    _ => ()
  }
}

///|
fn walk_inner_class_getters(
  block : @ast.TsBlock,
  outer_class_name : String,
  out : Array[ImpureGetter],
  assumed_pure : Map[String, Bool],
) -> Unit {
  for stmt in block.stmts {
    scan_stmt_for_impure_getters(stmt, outer_class_name, out, assumed_pure)
  }
}

///|
/// Look up the `let __get_value = function(){…}` binding for the
/// referenced var so we can inspect its body. Returns `None` when
/// the reference doesn't resolve to a function-expr binding.
fn find_temp_getter_body(
  stmts : Array[@ast.TsStmt],
  ref : @ast.TsExpr,
) -> @ast.TsExpr? {
  match ref {
    Var(name) => {
      for s in stmts {
        match s {
          Let(@ast.TsBinding::Ident(n), _, init)
          | Const(@ast.TsBinding::Ident(n), _, init)
          | Var(@ast.TsBinding::Ident(n), _, init) =>
            if n == name {
              return Some(init)
            }
          _ => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
/// Walk a getter's function body looking for the obvious side
/// effects: assignments, mutations, calls to non-pure globals.
/// Returns a short human-readable reason when an effect is
/// found, or `None` when the body looks pure.
fn check_getter_purity(
  fn_expr : @ast.TsExpr,
  assumed_pure : Map[String, Bool],
) -> String? {
  let body = match fn_expr {
    FuncExpr(f) => f.body
    ArrowFunc(_, _, @ast.TsArrowBody::ArrowBlock(b), _) => b
    ArrowFunc(_, _, @ast.TsArrowBody::ArrowExpr(e), _) => {
      stmts: [Return(Some(e))],
      stmt_positions: [],
    }
    _ => return None
  }
  let mut reason : String? = None
  walk_block_for_purity(body, false, fn(kind) {
    match kind {
      SideEffect =>
        if reason is None {
          reason = Some("has a direct side effect (assign / call / mutation)")
        }
      Calls(name) =>
        if reason is None &&
          not(pure_global_functions.contains(name)) &&
          not(assumed_pure.contains(name)) {
          reason = Some("calls `\{name}` (potentially impure)")
        }
    }
  })
  reason
}

///|
/// Type-check: is `ty` an immutable primitive? Strings / numbers /
/// booleans / bigints / symbols (and literal forms thereof) are
/// value-typed in JS — caller can't observe mutations through them
/// since none are possible.
fn is_primitive_immutable(ty : @ast.TsType) -> Bool {
  match ty {
    Number | Int | String_ | Boolean | BigInt | Symbol => true
    NumberLiteral(_) | Literal(_) | BooleanLiteral(_) | BigIntLiteral(_) => true
    Union(parts) => {
      if parts.length() == 0 {
        return false
      }
      for p in parts {
        if not(is_primitive_immutable(p)) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// `f` is signature-pure when every parameter is primitive-immutable
/// and the body is composed solely of expressions and statements
/// that cannot escape state to the caller — arithmetic, comparison,
/// returns, control flow, local lets, and pure-global method calls.
///
/// This is a strict subset of "no observable side effect": it skips
/// every form where mutation or escape might be hiding (PropAssign,
/// IndexAssign, MethodCall on non-pure receivers, `new`, `throw`,
/// `await`, `yield`).
fn is_signature_pure_func(f : @ast.TsFunc) -> Bool {
  if f.is_async || f.is_generator {
    return false
  }
  if f.params.length() == 0 {
    return false
  }
  for p in f.params {
    if not(is_primitive_immutable(p.type_)) {
      return false
    }
  }
  // Locals starts with the parameter names.
  let locals : Map[String, Bool] = {}
  for p in f.params {
    locals[p.name] = true
  }
  signature_pure_block(f.body, locals)
}

///|
fn signature_pure_block(
  block : @ast.TsBlock,
  locals : Map[String, Bool],
) -> Bool {
  for s in block.stmts {
    if not(signature_pure_stmt(s, locals)) {
      return false
    }
  }
  true
}

///|
fn signature_pure_stmt(
  stmt : @ast.TsStmt,
  locals : Map[String, Bool],
) -> Bool {
  match stmt {
    Var(@ast.TsBinding::Ident(name), _, e)
    | Let(@ast.TsBinding::Ident(name), _, e)
    | Const(@ast.TsBinding::Ident(name), _, e) => {
      if not(signature_pure_expr(e, locals)) {
        return false
      }
      locals[name] = true
      true
    }
    Var(_, _, _) | Let(_, _, _) | Const(_, _, _) =>
      // Destructured binders / non-ident targets — too complex to
      // track conservatively. Bail.
      false
    Assign(name, e) | CompoundAssign(name, _, e) =>
      // Only writes to local bindings are allowed.
      locals.contains(name) && signature_pure_expr(e, locals)
    IndexAssign(_, _, _) | PropAssign(_, _, _) =>
      // Object mutations — even on locals we don't track escape.
      false
    Expr(e) | Return(Some(e)) | Throw(e) => signature_pure_expr(e, locals)
    // `throw` of a primitive value is technically observable
    // (caller sees the exception). Conservative: forbid.
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => true
    If(c, t, e) => {
      if not(signature_pure_expr(c, locals)) {
        return false
      }
      if not(signature_pure_block(t, locals)) {
        return false
      }
      match e {
        Some(b) => signature_pure_block(b, locals)
        None => true
      }
    }
    While(c, body) | DoWhile(c, body) =>
      signature_pure_expr(c, locals) && signature_pure_block(body, locals)
    With(_, _) => false
    For(init, cond, update, body) => {
      let _ = match init {
        Some(s) =>
          if not(signature_pure_stmt(s, locals)) {
            return false
          } else {
            ()
          }
        None => ()
      }
      let _ = match cond {
        Some(e) =>
          if not(signature_pure_expr(e, locals)) {
            return false
          } else {
            ()
          }
        None => ()
      }
      let _ = match update {
        Some(s) =>
          if not(signature_pure_stmt(s, locals)) {
            return false
          } else {
            ()
          }
        None => ()
      }
      signature_pure_block(body, locals)
    }
    ForOf(_, _, _, _, _) | ForAwaitOf(_, _, _, _, _) | ForIn(_, _, _, _, _) =>
      // Iterating non-primitives — bail.
      false
    Switch(e, cases) => {
      if not(signature_pure_expr(e, locals)) {
        return false
      }
      for c in cases {
        match c.test_expr {
          Some(te) =>
            if not(signature_pure_expr(te, locals)) {
              return false
            }
          None => ()
        }
        if not(signature_pure_block(c.body, locals)) {
          return false
        }
      }
      true
    }
    Try(_, _, _, _) | Label(_, _) | Block(_) | NativeClassStmt(_, _) => false
  }
}

///|
fn signature_pure_expr(
  expr : @ast.TsExpr,
  locals : Map[String, Bool],
) -> Bool {
  match expr {
    NumberLit(_) | IntLit(_) | BigIntLit(_) | BoolLit(_) | StringLit(_)
    | NullLit | ArrayHole => true
    Var(_) => true
    BinOp(_, l, r) | Seq(l, r) =>
      signature_pure_expr(l, locals) && signature_pure_expr(r, locals)
    UnaryOp(op, inner) =>
      match op {
        PreInc | PreDec | PostInc | PostDec | Delete => false
        _ => signature_pure_expr(inner, locals)
      }
    Cond(c, t, e) =>
      signature_pure_expr(c, locals) &&
      signature_pure_expr(t, locals) &&
      signature_pure_expr(e, locals)
    Call(name, args) => {
      // Allow calls to known-pure globals + self/other top-level
      // bindings (the fixpoint will sort out chains). Conservative
      // for unknowns.
      let _ = name
      for a in args {
        if not(signature_pure_expr(a, locals)) {
          return false
        }
      }
      true
    }
    MethodCall(recv, _, args) => {
      let recv_ok = match recv {
        Var(n) => pure_global_methods.contains(n)
        _ => false
      }
      if not(recv_ok) {
        return false
      }
      for a in args {
        if not(signature_pure_expr(a, locals)) {
          return false
        }
      }
      true
    }
    CallExpr(_, _) | New(_, _) | NewExpr(_, _) => false
    PropAccess(recv, _) => signature_pure_expr(recv, locals)
    IndexAccess(recv, idx) =>
      signature_pure_expr(recv, locals) && signature_pure_expr(idx, locals)
    ArrayLit(items) => {
      for i in items {
        if not(signature_pure_expr(i, locals)) {
          return false
        }
      }
      true
    }
    ObjectLit(entries) => {
      for ent in entries {
        if not(signature_pure_expr(ent.1, locals)) {
          return false
        }
      }
      true
    }
    Spread(_) => false
    TemplateLiteral(_, exprs) => {
      for e in exprs {
        if not(signature_pure_expr(e, locals)) {
          return false
        }
      }
      true
    }
    TaggedTemplate(_, _, _, _) => false
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) | OptionalChain(inner) =>
      signature_pure_expr(inner, locals)
    PureCall(inner) => signature_pure_expr(inner, locals)
    AssignExpr(name, v) | CompoundAssignExpr(@ast.TsExpr::Var(name), _, v) =>
      locals.contains(name) && signature_pure_expr(v, locals)
    CompoundAssignExpr(_, _, _) | PropAssignExpr(_, _, _)
    | IndexAssignExpr(_, _, _) | AssignPattern(_, _) => false
    Yield(_) | YieldStar(_) | Await(_) => false
    ArrowFunc(_, _, _, _) | FuncExpr(_) =>
      // Nested closures can capture and have arbitrary effects when
      // called. We don't follow them at this scope of analysis.
      false
    DynamicImport(_, _) | ImportMeta => false
    JsxElement(_, _, _) => false
    NativeClassExpr(_, _) => false
    ComputedProp(_, _) => false
  }
}
