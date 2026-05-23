// Identifier mangling pass.
//
// This is the v0 of the type-aware mangling that's the eventual goal
// of the transform stack (the packelyze retry). Scope of this commit:
//
//   - Rename function-local declarations (`let`, `const`, `var`,
//     parameters, nested function names) to short two-letter
//     identifiers (`a`, `b`, …, `aa`, `ab`, …).
//   - Reserved-by-default: every top-level binding stays put (the
//     bundle's exports + every name visible at module scope), plus
//     every JS builtin / DOM global the engine might look up.
//   - All references in the same function — `Var`, `PropAccess`
//     receivers, call-site `Call(name, …)`, assignment targets,
//     destructuring patterns — get renamed in lockstep.
//
// Property keys, member-call methods, and object-literal keys are
// *not* renamed yet. That's where the checker integration lands in a
// follow-up; for now this pass treats every dot / index access as
// safe-to-rename only at the receiver side.
//
//   block ──► mangle_block(block, cfg) ──► block (with locals renamed)
//
// `cfg.reserved` augments the default reserved set. `cfg.preserve_top_level`
// (`true` by default) makes every top-level binding stay so library
// consumers can still call `export const greet = ...` after the
// transform — flip to `false` for sealed application bundles where the
// module-level surface is itself private.

///|
pub(all) struct ManglerConfig {
  // Extra names that must never get mangled. Combined with the
  // built-in reserved set (globals, JS keywords, common DOM
  // identifiers).
  reserved : Array[String]
  // When `true` (default) every identifier introduced at the top
  // level of `mangle_block` is added to the reserved set before the
  // pass starts. Use `false` to mangle top-level names too — only
  // safe once the caller has its own re-export shim list.
  preserve_top_level : Bool
}

///|
pub fn ManglerConfig::default() -> ManglerConfig {
  { reserved: [], preserve_top_level: true }
}

///|
pub fn ManglerConfig::with_reserved(
  self : ManglerConfig,
  names : Array[String],
) -> ManglerConfig {
  let merged : Array[String] = []
  for n in self.reserved {
    merged.push(n)
  }
  for n in names {
    merged.push(n)
  }
  { ..self, reserved: merged }
}

///|
pub fn ManglerConfig::with_preserve_top_level(
  self : ManglerConfig,
  preserve : Bool,
) -> ManglerConfig {
  { ..self, preserve_top_level: preserve }
}

// ---------------------------------------------------------------------------
// Built-in reserved set
// ---------------------------------------------------------------------------

///|
/// Names every browser / Node engine looks up at runtime. Renaming
/// any of these would silently break the program, so the mangler
/// treats them as reserved unconditionally.
let mangler_builtin_reserved : Array[String] = [
  // JS / ECMAScript globals
  "undefined", "null", "true", "false", "this", "globalThis",
  "Object", "Array", "Function", "Boolean", "Number", "String",
  "Symbol", "BigInt", "RegExp", "Date", "Error", "TypeError",
  "RangeError", "SyntaxError", "ReferenceError", "EvalError", "URIError",
  "AggregateError", "Math", "JSON", "Promise", "Map", "Set", "WeakMap",
  "WeakSet", "WeakRef", "FinalizationRegistry", "Proxy", "Reflect",
  "Int8Array", "Uint8Array", "Uint8ClampedArray", "Int16Array",
  "Uint16Array", "Int32Array", "Uint32Array", "Float32Array",
  "Float64Array", "BigInt64Array", "BigUint64Array",
  "ArrayBuffer", "SharedArrayBuffer", "DataView", "Atomics",
  "Iterator", "AsyncIterator", "Generator", "AsyncGenerator",
  "Infinity", "NaN", "isNaN", "isFinite", "parseInt", "parseFloat",
  "encodeURI", "decodeURI", "encodeURIComponent", "decodeURIComponent",
  "escape", "unescape", "eval",
  // Browser globals
  "window", "document", "location", "navigator", "history", "console",
  "alert", "confirm", "prompt", "fetch", "XMLHttpRequest", "WebSocket",
  "setTimeout", "setInterval", "clearTimeout", "clearInterval",
  "requestAnimationFrame", "cancelAnimationFrame", "queueMicrotask",
  // Module / runtime
  "require", "module", "exports", "__dirname", "__filename",
  "Buffer", "process",
  // React / JSX runtime (so JSX-lowering output keeps working)
  "jsx", "jsxs", "jsxDEV", "jsxsDEV", "Fragment", "React",
  // Keywords that can't be used as identifiers anyway
  "let", "const", "var", "function", "class", "if", "else", "return",
  "for", "while", "do", "switch", "case", "default", "break",
  "continue", "throw", "try", "catch", "finally", "new", "delete",
  "typeof", "instanceof", "void", "in", "of", "yield", "await",
  "async", "import", "export", "from", "as", "extends", "super",
  "static", "public", "private", "protected", "readonly", "implements",
  "interface", "type", "namespace", "module", "declare", "abstract",
  "with", "debugger", "enum",
]

// ---------------------------------------------------------------------------
// Scope tracking
// ---------------------------------------------------------------------------

///|
priv struct ScopeFrame {
  parent : ScopeFrame?
  // Map from original name to its mangled rename. A missing entry
  // means the name is reserved (no rename) or resolved through a
  // parent scope.
  renames : Map[String, String]
  // Every short name already taken in this scope or any of its
  // ancestors — used so generated names don't shadow a still-
  // reachable binding.
  used : Map[String, Bool]
  // Counter for the next short name to allocate.
  mut counter : Int
  // Reserved-name set — shared across the whole scope tree so nested
  // functions / arrow bodies see the same names as the root.
  reserved : Map[String, Bool]
}

///|
fn ScopeFrame::new_root(reserved : Map[String, Bool]) -> ScopeFrame {
  let used : Map[String, Bool] = {}
  for entry in reserved {
    let (n, _) = entry
    used[n] = true
  }
  { parent: None, renames: {}, used, counter: 0, reserved }
}

///|
fn ScopeFrame::child(parent : ScopeFrame) -> ScopeFrame {
  let inherited : Map[String, Bool] = {}
  for entry in parent.used {
    inherited[entry.0] = true
  }
  {
    parent: Some(parent),
    renames: {},
    used: inherited,
    counter: 0,
    reserved: parent.reserved,
  }
}

///|
/// Resolve `name` through the scope chain; returns the mangled
/// identifier (or the original when nothing was registered).
fn ScopeFrame::resolve(self : ScopeFrame, name : String) -> String {
  let mut cur : ScopeFrame? = Some(self)
  while cur is Some(frame) {
    match frame.renames.get(name) {
      Some(renamed) => return renamed
      None => cur = frame.parent
    }
  }
  name
}

///|
/// Register `name` as declared in this scope. Returns the chosen
/// mangled name (the original when the name is in the reserved set
/// or any ancestor frame has it as used and we can't safely
/// generate a new one).
fn ScopeFrame::bind(
  self : ScopeFrame,
  name : String,
  reserved : Map[String, Bool],
) -> String {
  // Reserved names stay put. They still mark themselves as used so
  // subsequent declarations don't pick a colliding short name.
  if reserved.contains(name) {
    self.used[name] = true
    self.renames[name] = name
    return name
  }
  // Allocate the next free short name. Bump `counter` until the
  // generated name isn't already used in this frame or any ancestor.
  let mut candidate = next_short_name(self.counter)
  self.counter = self.counter + 1
  while self.used.contains(candidate) || reserved.contains(candidate) {
    candidate = next_short_name(self.counter)
    self.counter = self.counter + 1
  }
  self.used[candidate] = true
  self.renames[name] = candidate
  candidate
}

///|
/// Generate the `n`th short identifier in lexicographic order:
///   0 → "a", 1 → "b", … 25 → "z", 26 → "aa", 27 → "ab", … 51 → "az",
///   52 → "ba", …, 675 → "zz", 676 → "aaa", …
fn next_short_name(n : Int) -> String {
  let chars : Array[Int] = []
  let mut k = n
  while {
    chars.push(k % 26)
    k = k / 26
    k > 0
  } {
    k = k - 1
  }
  let buf = StringBuilder::new()
  let mut i = chars.length() - 1
  while i >= 0 {
    let c = chars[i]
    buf.write_char(((97 + c) : Int).unsafe_to_char())
    i = i - 1
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// Public entrypoint
// ---------------------------------------------------------------------------

///|
/// Run the local-identifier mangling pass over `block`. Returns a
/// new `TsBlock` with every function-local name renamed to a short
/// `a` / `b` / … identifier. Top-level bindings stay put when
/// `cfg.preserve_top_level` is `true`.
pub fn mangle_block(
  block : @ast.TsBlock,
  cfg : ManglerConfig,
) -> @ast.TsBlock {
  // Reserved set = built-ins ∪ explicit ∪ (top-level decls when
  // `preserve_top_level`).
  let reserved : Map[String, Bool] = {}
  for n in mangler_builtin_reserved {
    reserved[n] = true
  }
  for n in cfg.reserved {
    reserved[n] = true
  }
  if cfg.preserve_top_level {
    collect_top_level_decls(block, reserved)
  }
  let root = ScopeFrame::new_root(reserved)
  // Predeclare top-level names in the root frame so child scopes can
  // see them but don't pick conflicting short names.
  for entry in reserved {
    let _ = root.bind(entry.0, reserved)
  }
  let new_stmts : Array[@ast.TsStmt] = []
  for stmt in block.stmts {
    new_stmts.push(rename_stmt(stmt, root, reserved))
  }
  { stmts: new_stmts, stmt_positions: block.stmt_positions }
}

///|
fn collect_top_level_decls(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for stmt in block.stmts {
    match stmt {
      Var(@ast.TsBinding::Ident(n), _, _)
      | Let(@ast.TsBinding::Ident(n), _, _)
      | Const(@ast.TsBinding::Ident(n), _, _) => out[n] = true
      Var(b, _, _) | Let(b, _, _) | Const(b, _, _) =>
        collect_binding_names(b, out)
      _ => ()
    }
  }
}

///|
fn collect_binding_names(
  binding : @ast.TsBinding,
  out : Map[String, Bool],
) -> Unit {
  match binding {
    Ident(n) => out[n] = true
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => collect_binding_names(be.binding, out)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_binding_names(r, out)
        None => ()
      }
    }
    Object(ob) => {
      for p in ob.props {
        collect_binding_names(p.binding, out)
      }
      match ob.rest {
        Some(n) => out[n] = true
        None => ()
      }
    }
    Target(_) => ()
  }
}

// ---------------------------------------------------------------------------
// AST walker
// ---------------------------------------------------------------------------

///|
fn rename_stmt(
  stmt : @ast.TsStmt,
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, init) =>
      Var(rename_binding_decl(b, scope, reserved), t, rename_expr(init, scope))
    Let(b, t, init) =>
      Let(rename_binding_decl(b, scope, reserved), t, rename_expr(init, scope))
    Const(b, t, init) =>
      Const(
        rename_binding_decl(b, scope, reserved),
        t,
        rename_expr(init, scope),
      )
    Expr(e) => Expr(rename_expr(e, scope))
    Return(opt) =>
      match opt {
        Some(e) => Return(Some(rename_expr(e, scope)))
        None => Return(None)
      }
    Throw(e) => Throw(rename_expr(e, scope))
    Assign(name, e) =>
      Assign(scope.resolve(name), rename_expr(e, scope))
    CompoundAssign(name, op, e) =>
      CompoundAssign(scope.resolve(name), op, rename_expr(e, scope))
    PropAssign(recv, prop, value) =>
      PropAssign(rename_expr(recv, scope), prop, rename_expr(value, scope))
    IndexAssign(recv, idx, value) =>
      IndexAssign(
        rename_expr(recv, scope),
        rename_expr(idx, scope),
        rename_expr(value, scope),
      )
    If(cond, then_b, else_opt) =>
      If(rename_expr(cond, scope), rename_block_inline(then_b, scope, reserved), match else_opt {
        Some(b) => Some(rename_block_inline(b, scope, reserved))
        None => None
      })
    While(c, b) =>
      While(rename_expr(c, scope), rename_block_inline(b, scope, reserved))
    DoWhile(c, b) =>
      DoWhile(rename_expr(c, scope), rename_block_inline(b, scope, reserved))
    For(init_opt, cond_opt, update_opt, body) => {
      // `for (let i = 0; …; …) { … }` creates a new lexical scope.
      let inner = ScopeFrame::child(scope)
      let new_init = match init_opt {
        Some(s) => Some(rename_stmt(s, inner, reserved))
        None => None
      }
      let new_cond = match cond_opt {
        Some(c) => Some(rename_expr(c, inner))
        None => None
      }
      let new_update = match update_opt {
        Some(s) => Some(rename_stmt(s, inner, reserved))
        None => None
      }
      let new_body = rename_block_inline(body, inner, reserved)
      For(new_init, new_cond, new_update, new_body)
    }
    ForOf(kind, b, t, iter, body) => {
      let inner = ScopeFrame::child(scope)
      let new_binding = rename_binding_decl(b, inner, reserved)
      let new_iter = rename_expr(iter, scope)
      let new_body = rename_block_inline(body, inner, reserved)
      ForOf(kind, new_binding, t, new_iter, new_body)
    }
    ForAwaitOf(kind, b, t, iter, body) => {
      let inner = ScopeFrame::child(scope)
      let new_binding = rename_binding_decl(b, inner, reserved)
      let new_iter = rename_expr(iter, scope)
      let new_body = rename_block_inline(body, inner, reserved)
      ForAwaitOf(kind, new_binding, t, new_iter, new_body)
    }
    ForIn(kind, b, t, iter, body) => {
      let inner = ScopeFrame::child(scope)
      let new_binding = rename_binding_decl(b, inner, reserved)
      let new_iter = rename_expr(iter, scope)
      let new_body = rename_block_inline(body, inner, reserved)
      ForIn(kind, new_binding, t, new_iter, new_body)
    }
    Switch(scrutinee, cases) => {
      let new_scrutinee = rename_expr(scrutinee, scope)
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        let new_test = match c.test_expr {
          Some(t) => Some(rename_expr(t, scope))
          None => None
        }
        let inner = ScopeFrame::child(scope)
        new_cases.push({
          test_expr: new_test,
          body: rename_block_inline_in(c.body, inner, reserved),
        })
      }
      Switch(new_scrutinee, new_cases)
    }
    Try(try_b, catch_bind, catch_b, finally_b) => {
      let new_try = rename_block_inline(try_b, scope, reserved)
      let (new_bind, new_catch) = match (catch_bind, catch_b) {
        (Some(b), Some(cb)) => {
          let inner = ScopeFrame::child(scope)
          let renamed_bind = rename_binding_decl(b, inner, reserved)
          (Some(renamed_bind), Some(rename_block_inline_in(cb, inner, reserved)))
        }
        (None, Some(cb)) =>
          (None, Some(rename_block_inline(cb, scope, reserved)))
        _ => (None, None)
      }
      let new_finally = match finally_b {
        Some(fb) => Some(rename_block_inline(fb, scope, reserved))
        None => None
      }
      Try(new_try, new_bind, new_catch, new_finally)
    }
    Block(b) => Block(rename_block_inline(b, scope, reserved))
    Label(name, inner) =>
      Label(name, rename_stmt(inner, scope, reserved))
    With(target, body) =>
      With(rename_expr(target, scope), rename_block_inline(body, scope, reserved))
    Break(_) | Continue(_) | Empty | Debugger => stmt
  }
}

///|
/// Rename `block` using the given scope without spawning a new
/// frame. Used inside `if` / `while` / `try` bodies where TS / JS
/// scoping is lexical-block but our v0 keeps the frames at the
/// function granularity.
fn rename_block_inline(
  block : @ast.TsBlock,
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> @ast.TsBlock {
  rename_block_inline_in(block, scope, reserved)
}

///|
fn rename_block_inline_in(
  block : @ast.TsBlock,
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(rename_stmt(s, scope, reserved))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn rename_binding_decl(
  binding : @ast.TsBinding,
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> @ast.TsBinding {
  match binding {
    Ident(n) => Ident(scope.bind(n, reserved))
    Array(ab) => {
      let new_items : Array[@ast.TsBindingElem?] = []
      for elem in ab.items {
        match elem {
          Some(be) => {
            let new_inner = rename_binding_decl(be.binding, scope, reserved)
            let new_default : @ast.TsExpr? = match be.default {
              Some(d) => Some(rename_expr(d, scope))
              None => None
            }
            new_items.push(Some({ binding: new_inner, default: new_default }))
          }
          None => new_items.push(None)
        }
      }
      let new_rest : @ast.TsBinding? = match ab.rest {
        Some(r) => Some(rename_binding_decl(r, scope, reserved))
        None => None
      }
      Array({ items: new_items, rest: new_rest })
    }
    Object(ob) => {
      let new_props : Array[@ast.TsObjectBindingProp] = []
      for p in ob.props {
        let new_inner = rename_binding_decl(p.binding, scope, reserved)
        let new_default : @ast.TsExpr? = match p.default {
          Some(d) => Some(rename_expr(d, scope))
          None => None
        }
        new_props.push({
          key: p.key,
          key_expr: p.key_expr,
          binding: new_inner,
          default: new_default,
        })
      }
      let new_rest : String? = match ob.rest {
        Some(n) => Some(scope.bind(n, reserved))
        None => None
      }
      Object({ props: new_props, rest: new_rest })
    }
    Target(e) => Target(rename_expr(e, scope))
  }
}

// ---------------------------------------------------------------------------
// Expression walker
// ---------------------------------------------------------------------------

///|
fn rename_expr(expr : @ast.TsExpr, scope : ScopeFrame) -> @ast.TsExpr {
  match expr {
    Var(name) => Var(scope.resolve(name))
    Call(name, args) => {
      // `Call(name, …)` is a free-function call site; the name is a
      // variable reference, so it follows the scope chain.
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr(a, scope))
      }
      Call(scope.resolve(name), new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr(a, scope))
      }
      CallExpr(rename_expr(callee, scope), new_args)
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr(a, scope))
      }
      New(scope.resolve(name), new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr(a, scope))
      }
      NewExpr(rename_expr(callee, scope), new_args)
    }
    MethodCall(recv, method, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr(a, scope))
      }
      // Property name is left untouched — property mangling is a
      // separate pass that needs type info to be safe.
      MethodCall(rename_expr(recv, scope), method, new_args)
    }
    PropAccess(recv, name) => PropAccess(rename_expr(recv, scope), name)
    IndexAccess(recv, idx) =>
      IndexAccess(rename_expr(recv, scope), rename_expr(idx, scope))
    BinOp(op, l, r) =>
      BinOp(op, rename_expr(l, scope), rename_expr(r, scope))
    UnaryOp(op, inner) => UnaryOp(op, rename_expr(inner, scope))
    Cond(c, t, e) =>
      Cond(rename_expr(c, scope), rename_expr(t, scope), rename_expr(e, scope))
    ArrayLit(items) => {
      let out : Array[@ast.TsExpr] = []
      for i in items {
        out.push(rename_expr(i, scope))
      }
      ArrayLit(out)
    }
    Spread(inner) => Spread(rename_expr(inner, scope))
    ObjectLit(entries) => {
      let out : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        out.push((ent.0, rename_expr(ent.1, scope)))
      }
      ObjectLit(out)
    }
    ComputedProp(k, v) =>
      ComputedProp(rename_expr(k, scope), rename_expr(v, scope))
    AssignExpr(name, value) =>
      AssignExpr(scope.resolve(name), rename_expr(value, scope))
    AssignPattern(b, value) => {
      // Destructuring assignment to an existing pattern; the LHS is
      // an *assignment* not a declaration, so the names resolve via
      // the scope chain rather than introducing new bindings.
      AssignPattern(rename_binding_lhs(b, scope), rename_expr(value, scope))
    }
    CompoundAssignExpr(target, op, value) =>
      CompoundAssignExpr(
        rename_expr(target, scope), op, rename_expr(value, scope),
      )
    PropAssignExpr(recv, prop, value) =>
      PropAssignExpr(rename_expr(recv, scope), prop, rename_expr(value, scope))
    IndexAssignExpr(recv, idx, value) =>
      IndexAssignExpr(
        rename_expr(recv, scope),
        rename_expr(idx, scope),
        rename_expr(value, scope),
      )
    Seq(a, b) => Seq(rename_expr(a, scope), rename_expr(b, scope))
    ArrowFunc(params, ret_ty, body, is_async) => {
      // New scope for the arrow function body.
      let inner = ScopeFrame::child(scope)
      let new_params = rename_param_list(params, inner, inner.reserved)
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(rename_expr(e, inner))
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(
            rename_block_inline_in(b, inner, inner.reserved),
          )
      }
      ArrowFunc(new_params, ret_ty, new_body, is_async)
    }
    FuncExpr(f) => FuncExpr(rename_function_expr(f, scope))
    Yield(opt) =>
      match opt {
        Some(e) => Yield(Some(rename_expr(e, scope)))
        None => Yield(None)
      }
    YieldStar(inner) => YieldStar(rename_expr(inner, scope))
    Await(inner) => Await(rename_expr(inner, scope))
    DynamicImport(spec, opts) =>
      DynamicImport(rename_expr(spec, scope), match opts {
        Some(o) => Some(rename_expr(o, scope))
        None => None
      })
    TaggedTemplate(tag, parts, raw, exprs) => {
      let out : Array[@ast.TsExpr] = []
      for e in exprs {
        out.push(rename_expr(e, scope))
      }
      TaggedTemplate(rename_expr(tag, scope), parts, raw, out)
    }
    TemplateLiteral(parts, exprs) => {
      let out : Array[@ast.TsExpr] = []
      for e in exprs {
        out.push(rename_expr(e, scope))
      }
      TemplateLiteral(parts, out)
    }
    As(inner, ty) => As(rename_expr(inner, scope), ty)
    Satisfies(inner, ty) => Satisfies(rename_expr(inner, scope), ty)
    NonNull(inner) => NonNull(rename_expr(inner, scope))
    OptionalChain(inner) => OptionalChain(rename_expr(inner, scope))
    JsxElement(_, _, _) => expr // JSX should be lowered before mangling
    _ => expr
  }
}

///|
/// Same as `rename_binding_decl` but treats `Ident(n)` as an
/// assignment-LHS reference instead of a declaration — the name
/// resolves through `scope.resolve` rather than introducing a new
/// binding. Used by `AssignPattern(b, value)`.
fn rename_binding_lhs(
  binding : @ast.TsBinding,
  scope : ScopeFrame,
) -> @ast.TsBinding {
  match binding {
    Ident(n) => Ident(scope.resolve(n))
    Array(ab) => {
      let new_items : Array[@ast.TsBindingElem?] = []
      for elem in ab.items {
        match elem {
          Some(be) => {
            let new_inner = rename_binding_lhs(be.binding, scope)
            let new_default : @ast.TsExpr? = match be.default {
              Some(d) => Some(rename_expr(d, scope))
              None => None
            }
            new_items.push(Some({ binding: new_inner, default: new_default }))
          }
          None => new_items.push(None)
        }
      }
      let new_rest : @ast.TsBinding? = match ab.rest {
        Some(r) => Some(rename_binding_lhs(r, scope))
        None => None
      }
      Array({ items: new_items, rest: new_rest })
    }
    Object(ob) => {
      let new_props : Array[@ast.TsObjectBindingProp] = []
      for p in ob.props {
        let new_inner = rename_binding_lhs(p.binding, scope)
        let new_default : @ast.TsExpr? = match p.default {
          Some(d) => Some(rename_expr(d, scope))
          None => None
        }
        new_props.push({
          key: p.key,
          key_expr: p.key_expr,
          binding: new_inner,
          default: new_default,
        })
      }
      let new_rest : String? = match ob.rest {
        Some(n) => Some(scope.resolve(n))
        None => None
      }
      Object({ props: new_props, rest: new_rest })
    }
    Target(e) => Target(rename_expr(e, scope))
  }
}

///|
fn rename_function_expr(
  f : @ast.TsFunc,
  scope : ScopeFrame,
) -> @ast.TsFunc {
  // `function name(…)` introduces `name` into the parent scope's
  // value namespace. v0 keeps the function name verbatim — the
  // bundle layer can't predict whether the function is referenced
  // by name elsewhere yet (without checker symbol-graph analysis).
  let inner = ScopeFrame::child(scope)
  let new_params = rename_param_list(f.params, inner, inner.reserved)
  let new_body = rename_block_inline_in(f.body, inner, inner.reserved)
  {
    name: f.name,
    type_params: f.type_params,
    const_type_params: f.const_type_params,
    params: new_params,
    return_type: f.return_type,
    body: new_body,
    is_generator: f.is_generator,
    is_async: f.is_async,
  }
}

///|
fn rename_param_list(
  params : Array[@ast.TsParam],
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> Array[@ast.TsParam] {
  let out : Array[@ast.TsParam] = []
  for p in params {
    let new_binding : @ast.TsBinding? = match p.binding {
      Some(b) => Some(rename_binding_decl(b, scope, reserved))
      None => None
    }
    let new_name = match new_binding {
      Some(@ast.TsBinding::Ident(n)) => n
      _ =>
        if p.name == "" {
          ""
        } else {
          scope.bind(p.name, reserved)
        }
    }
    let new_default : @ast.TsExpr? = match p.default {
      Some(d) => Some(rename_expr(d, scope))
      None => None
    }
    out.push({
      name: new_name,
      binding: new_binding,
      is_rest: p.is_rest,
      type_: p.type_,
      default: new_default,
    })
  }
  out
}
