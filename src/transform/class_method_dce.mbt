// Unused class-method DCE (whole-program, syntactic).
//
// Native class declarations carry a method list. Many libraries
// ship classes with many methods of which only a subset is
// reached from the entry. Treeshake already handles unused
// top-level bindings; this pass extends DCE *inside* native
// class declarations.
//
//   class Foo {
//     start() {}     // referenced
//     legacy() {}    // never accessed -> drop
//   }
//   const f = new Foo();
//   f.start();
//
// becomes
//
//   class Foo {
//     start() {}
//   }
//   const f = new Foo();
//   f.start();
//
// Safety (syntactic, no type info needed). The pass is gated on
// the bundle never observing method names dynamically:
//
//   * Any `obj[expr]` with a non-static index — we can't know
//     which method name is referenced.
//   * Reflection ops over a class shape: `Object.getOwnProperty
//     Names`, `Object.getOwnPropertyDescriptors`,
//     `Reflect.ownKeys`, `Reflect.getOwnPropertyDescriptor`.
//   * `delete obj.method` — we can't drop a name the program
//     was already trying to remove at runtime.
//   * `Object.keys / entries / values / assign / fromEntries`
//     and spread (`...x`) — these also enumerate object
//     properties (and may include methods on plain objects;
//     class methods live on the prototype but the analyzer
//     can't always tell instances from plain objects apart).
//
// When the bundle clears those, drop every method whose name
// doesn't appear in the bundle's syntactic access set. The
// `constructor` is always kept (it's the body of `new C(...)`).

///|
pub fn class_method_dce_block(block : @ast.TsBlock) -> @ast.TsBlock {
  // 1. Cheap exit when neither shape of class is present: no
  //    NativeClassStmt/Expr AND no IIFE-lowered class. (The IIFE
  //    pattern is `let X = function () { … return X; }();`.)
  let iife_classes = collect_iife_class_names(block)
  if not(has_any_native_class(block)) && iife_classes.is_empty() {
    return block
  }
  // 2. Bundle-wide reflection / dynamic-access scan. Any hit aborts.
  if block_has_method_sniff(block) {
    return block
  }
  // 3. Collect the set of statically-accessed property names. Any
  //    `e.NAME` or `e["NAME"]` adds NAME, except names assigned
  //    inside an IIFE class body as `ClassName.prototype.NAME = …`
  //    — those are definitions, not uses, and counting them would
  //    defeat the DCE on the IIFE-lowered form.
  let accessed : Map[String, Bool] = {}
  collect_static_accesses_block_skipping_iife(block, iife_classes, accessed)
  // 4. Rewrite native class statements, filtering their method lists.
  let new_stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    new_stmts.push(dce_stmt(s, accessed))
  }
  { stmts: new_stmts, stmt_positions: block.stmt_positions }
}

// -- Step 1: cheap "has any class" check ------------------------------

///|
/// Returns the set of class names defined via the IIFE-lowered
/// shape at the top level.
fn collect_iife_class_names(block : @ast.TsBlock) -> Map[String, Bool] {
  let out : Map[String, Bool] = {}
  for s in block.stmts {
    match s {
      Var(
        @ast.TsBinding::Ident(n),
        _,
        @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(_), args)
      )
      | Let(
        @ast.TsBinding::Ident(n),
        _,
        @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(_), args)
      )
      | Const(
        @ast.TsBinding::Ident(n),
        _,
        @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(_), args)
      ) => if args.length() == 0 { out[n] = true }
      _ => ()
    }
  }
  out
}

///|
/// Variant of `collect_static_accesses_block` that walks the top
/// level normally but, when it descends into the IIFE body of a
/// known IIFE class, skips `ClassName.prototype.METHOD = …`
/// PropAssigns (definitions, not uses).
fn collect_static_accesses_block_skipping_iife(
  block : @ast.TsBlock,
  iife_classes : Map[String, Bool],
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    match s {
      Var(
        @ast.TsBinding::Ident(n),
        _,
        @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), args)
      )
      | Let(
        @ast.TsBinding::Ident(n),
        _,
        @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), args)
      )
      | Const(
        @ast.TsBinding::Ident(n),
        _,
        @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), args)
      ) =>
        if args.length() == 0 && iife_classes.contains(n) {
          // IIFE class body: skip prototype-assignment LHS reads.
          collect_iife_body_accesses(f.body, n, out)
        } else {
          collect_static_accesses_stmt(s, out)
        }
      _ => collect_static_accesses_stmt(s, out)
    }
  }
}

///|
/// Walk an IIFE class body, treating `ClassName.prototype.X = …`
/// (and chained `.X.SUB = …`) as definitions — don't add `X` to
/// `out` via the LHS. Method-body content still counts: a method
/// internally calling `this.helper()` keeps `helper` alive.
fn collect_iife_body_accesses(
  body : @ast.TsBlock,
  class_name : String,
  out : Map[String, Bool],
) -> Unit {
  for s in body.stmts {
    match s {
      // `ClassName.prototype.X = value;` — only walk `value`.
      PropAssign(
        @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
        _,
        v
      ) =>
        if n == class_name {
          collect_static_accesses_expr(v, out)
        } else {
          collect_static_accesses_stmt(s, out)
        }
      // `ClassName.prototype.X.Y = value;` — only walk `value`.
      PropAssign(
        @ast.TsExpr::PropAccess(
          @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
          _
        ),
        _,
        v
      ) =>
        if n == class_name {
          collect_static_accesses_expr(v, out)
        } else {
          collect_static_accesses_stmt(s, out)
        }
      _ => collect_static_accesses_stmt(s, out)
    }
  }
}

///|
/// Detects the IIFE-lowered class shape at the top level:
///   `let X = function () { … return X; }();`
fn has_any_iife_class(block : @ast.TsBlock) -> Bool {
  for s in block.stmts {
    match s {
      Var(
        @ast.TsBinding::Ident(_),
        _,
        @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(_), args)
      )
      | Let(
        @ast.TsBinding::Ident(_),
        _,
        @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(_), args)
      )
      | Const(
        @ast.TsBinding::Ident(_),
        _,
        @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(_), args)
      ) => if args.length() == 0 { return true }
      _ => ()
    }
  }
  false
}

///|
fn has_any_native_class(block : @ast.TsBlock) -> Bool {
  for s in block.stmts {
    if stmt_has_native_class(s) {
      return true
    }
  }
  false
}

///|
fn stmt_has_native_class(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    NativeClassStmt(_, _) => true
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Throw(e) => expr_has_native_class(e)
    Return(Some(e)) => expr_has_native_class(e)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => false
    IndexAssign(t, idx, v) =>
      expr_has_native_class(t) ||
      expr_has_native_class(idx) ||
      expr_has_native_class(v)
    PropAssign(t, _, v) => expr_has_native_class(t) || expr_has_native_class(v)
    If(c, t, e) => {
      if expr_has_native_class(c) {
        return true
      }
      if has_any_native_class(t) {
        return true
      }
      match e {
        Some(b) => has_any_native_class(b)
        None => false
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) =>
      expr_has_native_class(c) || has_any_native_class(body)
    For(init, cond, update, body) => {
      let init_bad = match init {
        Some(s) => stmt_has_native_class(s)
        None => false
      }
      if init_bad {
        return true
      }
      let cond_bad = match cond {
        Some(e) => expr_has_native_class(e)
        None => false
      }
      if cond_bad {
        return true
      }
      let upd_bad = match update {
        Some(s) => stmt_has_native_class(s)
        None => false
      }
      if upd_bad {
        return true
      }
      has_any_native_class(body)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) =>
      expr_has_native_class(iter) || has_any_native_class(body)
    Switch(e, cases) => {
      if expr_has_native_class(e) {
        return true
      }
      for c in cases {
        match c.test_expr {
          Some(te) => if expr_has_native_class(te) { return true }
          None => ()
        }
        if has_any_native_class(c.body) {
          return true
        }
      }
      false
    }
    Try(b, _, cb, fb) => {
      if has_any_native_class(b) {
        return true
      }
      let cb_bad = match cb {
        Some(blk) => has_any_native_class(blk)
        None => false
      }
      if cb_bad {
        return true
      }
      match fb {
        Some(blk) => has_any_native_class(blk)
        None => false
      }
    }
    Label(_, inner) => stmt_has_native_class(inner)
    Block(b) => has_any_native_class(b)
  }
}

///|
fn expr_has_native_class(expr : @ast.TsExpr) -> Bool {
  match expr {
    NativeClassExpr(_, _) => true
    FuncExpr(f) => has_any_native_class(f.body)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => expr_has_native_class(e)
        ArrowBlock(b) => has_any_native_class(b)
      }
    BinOp(_, l, r) | Seq(l, r) =>
      expr_has_native_class(l) || expr_has_native_class(r)
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | YieldStar(inner) => expr_has_native_class(inner)
    Cond(c, t, e) =>
      expr_has_native_class(c) ||
      expr_has_native_class(t) ||
      expr_has_native_class(e)
    PropAccess(recv, _) => expr_has_native_class(recv)
    IndexAccess(recv, idx) =>
      expr_has_native_class(recv) || expr_has_native_class(idx)
    Call(_, args) | New(_, args) => {
      for a in args {
        if expr_has_native_class(a) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if expr_has_native_class(callee) {
        return true
      }
      for a in args {
        if expr_has_native_class(a) {
          return true
        }
      }
      false
    }
    MethodCall(recv, _, args) => {
      if expr_has_native_class(recv) {
        return true
      }
      for a in args {
        if expr_has_native_class(a) {
          return true
        }
      }
      false
    }
    ArrayLit(items) => {
      for i in items {
        if expr_has_native_class(i) {
          return true
        }
      }
      false
    }
    ObjectLit(entries) => {
      for ent in entries {
        if expr_has_native_class(ent.1) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

// -- Step 2: reflection / dynamic-access sink scan --------------------

///|
let method_sniff_methods : Array[String] = [
  // Reflective method-name observation.
  "getOwnPropertyNames", "getOwnPropertyDescriptors", "ownKeys", "getOwnPropertyDescriptor",
  // Property enumeration (likely fine for class methods, but the
  // analyzer can't always distinguish instances from plain objects).
   "keys", "entries", "values", "assign", "fromEntries",
]

///|
fn block_has_method_sniff(block : @ast.TsBlock) -> Bool {
  for s in block.stmts {
    if stmt_has_method_sniff(s) {
      return true
    }
  }
  false
}

///|
fn stmt_has_method_sniff(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    // for-in iterates property names — sink.
    ForIn(_, _, _, _, _) => true
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Throw(e) => expr_has_method_sniff(e)
    Return(Some(e)) => expr_has_method_sniff(e)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => false
    IndexAssign(t, idx, v) => {
      // Computed assignment with non-static index is a sink UNLESS the
      // receiver is `this`: `this[key] = val` writes to the INSTANCE,
      // not to the prototype, so prototype-method DCE is still safe.
      // `Foo.prototype[key] = val` (dynamic prototype augmentation) IS
      // a sink and correctly falls through to `return true`.
      if not(is_static_index_for_method_dce(idx)) {
        match t {
          @ast.TsExpr::Var("this") => ()
          _ => return true
        }
      }
      expr_has_method_sniff(t) ||
      expr_has_method_sniff(idx) ||
      expr_has_method_sniff(v)
    }
    PropAssign(t, _, v) => expr_has_method_sniff(t) || expr_has_method_sniff(v)
    If(c, t, e) => {
      if expr_has_method_sniff(c) {
        return true
      }
      if block_has_method_sniff(t) {
        return true
      }
      match e {
        Some(b) => block_has_method_sniff(b)
        None => false
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) =>
      expr_has_method_sniff(c) || block_has_method_sniff(body)
    For(init, cond, update, body) => {
      let init_bad = match init {
        Some(s) => stmt_has_method_sniff(s)
        None => false
      }
      if init_bad {
        return true
      }
      let cond_bad = match cond {
        Some(e) => expr_has_method_sniff(e)
        None => false
      }
      if cond_bad {
        return true
      }
      let upd_bad = match update {
        Some(s) => stmt_has_method_sniff(s)
        None => false
      }
      if upd_bad {
        return true
      }
      block_has_method_sniff(body)
    }
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body) =>
      expr_has_method_sniff(iter) || block_has_method_sniff(body)
    Switch(e, cases) => {
      if expr_has_method_sniff(e) {
        return true
      }
      for c in cases {
        match c.test_expr {
          Some(te) => if expr_has_method_sniff(te) { return true }
          None => ()
        }
        if block_has_method_sniff(c.body) {
          return true
        }
      }
      false
    }
    Try(b, _, cb, fb) => {
      if block_has_method_sniff(b) {
        return true
      }
      let cb_bad = match cb {
        Some(blk) => block_has_method_sniff(blk)
        None => false
      }
      if cb_bad {
        return true
      }
      match fb {
        Some(blk) => block_has_method_sniff(blk)
        None => false
      }
    }
    Label(_, inner) => stmt_has_method_sniff(inner)
    Block(b) => block_has_method_sniff(b)
    NativeClassStmt(decl, ctor_body) => {
      // Walk the methods' bodies too — internal reflection on
      // `this` (e.g. `Object.keys(this)`) counts as a sink.
      for m in decl.methods {
        match m.body {
          Some(b) => if block_has_method_sniff(b) { return true }
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        if expr_has_method_sniff(sf.1) {
          return true
        }
      }
      match ctor_body {
        Some(f) => block_has_method_sniff(f.body)
        None => false
      }
    }
  }
}

///|
fn expr_has_method_sniff(expr : @ast.TsExpr) -> Bool {
  match expr {
    // `Object.foo(...)` / `Reflect.foo(...)` reflection sink.
    MethodCall(@ast.TsExpr::Var(recv), m, args) => {
      let recv_is_reflective = recv == "Object" || recv == "Reflect"
      if recv_is_reflective && method_sniff_methods.contains(m) {
        return true
      }
      for a in args {
        if expr_has_method_sniff(a) {
          return true
        }
      }
      false
    }
    // Spread of an object literal is fine, but spread of an
    // arbitrary expression `{...x}` enumerates whatever `x` is.
    Spread(_) => true
    // `delete x.method` (statement form is `Expr(UnaryOp(Delete, _))`).
    UnaryOp(@ast.TsUnaryOp::Delete, _) => true
    // Computed-key access with a non-static index.
    IndexAccess(recv, idx) => {
      if not(is_static_index_for_method_dce(idx)) {
        return true
      }
      expr_has_method_sniff(recv) || expr_has_method_sniff(idx)
    }
    IndexAssignExpr(recv, idx, v) => {
      if not(is_static_index_for_method_dce(idx)) {
        match recv {
          @ast.TsExpr::Var("this") => ()
          _ => return true
        }
      }
      expr_has_method_sniff(recv) ||
      expr_has_method_sniff(idx) ||
      expr_has_method_sniff(v)
    }
    Call(name, args) => {
      // Bare `Object.keys` style isn't here (that's MethodCall).
      // But common globals named after sinks shouldn't slip
      // through — be conservative when seeing them by name.
      if name == "Object" || name == "Reflect" {
        // `Object(x)` / `Reflect(x)` — let's just play safe.
        return true
      }
      for a in args {
        if expr_has_method_sniff(a) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if expr_has_method_sniff(callee) {
        return true
      }
      for a in args {
        if expr_has_method_sniff(a) {
          return true
        }
      }
      false
    }
    MethodCall(recv, _, args) => {
      if expr_has_method_sniff(recv) {
        return true
      }
      for a in args {
        if expr_has_method_sniff(a) {
          return true
        }
      }
      false
    }
    New(_, args) => {
      for a in args {
        if expr_has_method_sniff(a) {
          return true
        }
      }
      false
    }
    BinOp(_, l, r) | Seq(l, r) =>
      expr_has_method_sniff(l) || expr_has_method_sniff(r)
    UnaryOp(_, inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | YieldStar(inner) => expr_has_method_sniff(inner)
    Cond(c, t, e) =>
      expr_has_method_sniff(c) ||
      expr_has_method_sniff(t) ||
      expr_has_method_sniff(e)
    PropAccess(recv, _) => expr_has_method_sniff(recv)
    ArrayLit(items) => {
      for i in items {
        if expr_has_method_sniff(i) {
          return true
        }
      }
      false
    }
    ObjectLit(entries) => {
      for ent in entries {
        if expr_has_method_sniff(ent.1) {
          return true
        }
      }
      false
    }
    ComputedProp(k, v) => expr_has_method_sniff(k) || expr_has_method_sniff(v)
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      expr_has_method_sniff(v)
    CompoundAssignExpr(t, _, v) =>
      expr_has_method_sniff(t) || expr_has_method_sniff(v)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => expr_has_method_sniff(e)
        ArrowBlock(b) => block_has_method_sniff(b)
      }
    FuncExpr(f) => block_has_method_sniff(f.body)
    DynamicImport(spec, opts) => {
      if expr_has_method_sniff(spec) {
        return true
      }
      match opts {
        Some(o) => expr_has_method_sniff(o)
        None => false
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      if expr_has_method_sniff(tag) {
        return true
      }
      for e in exprs {
        if expr_has_method_sniff(e) {
          return true
        }
      }
      false
    }
    TemplateLiteral(_, exprs) => {
      for e in exprs {
        if expr_has_method_sniff(e) {
          return true
        }
      }
      false
    }
    As(inner, _) | Satisfies(inner, _) => expr_has_method_sniff(inner)
    Yield(Some(inner)) => expr_has_method_sniff(inner)
    NativeClassExpr(decl, ctor_body) => {
      for m in decl.methods {
        match m.body {
          Some(b) => if block_has_method_sniff(b) { return true }
          None => ()
        }
      }
      match ctor_body {
        Some(f) => block_has_method_sniff(f.body)
        None => false
      }
    }
    _ => false
  }
}

///|
fn is_static_index_for_method_dce(idx : @ast.TsExpr) -> Bool {
  match idx {
    StringLit(_) | NumberLit(_) | IntLit(_) => true
    _ => false
  }
}

// -- Step 3: collect statically-accessed property names ---------------

///|
fn collect_static_accesses_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_static_accesses_stmt(s, out)
  }
}

///|
fn collect_static_accesses_stmt(
  stmt : @ast.TsStmt,
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Throw(e) => collect_static_accesses_expr(e, out)
    Return(Some(e)) => collect_static_accesses_expr(e, out)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => ()
    IndexAssign(t, idx, v) => {
      // Assignment writes; the prop name on the LHS isn't a read.
      // Walk the receiver and value for reads they may contain.
      collect_static_accesses_expr(t, out)
      collect_static_accesses_expr(idx, out)
      collect_static_accesses_expr(v, out)
    }
    PropAssign(t, _, v) => {
      collect_static_accesses_expr(t, out)
      collect_static_accesses_expr(v, out)
    }
    If(c, t, e) => {
      collect_static_accesses_expr(c, out)
      collect_static_accesses_block(t, out)
      match e {
        Some(b) => collect_static_accesses_block(b, out)
        None => ()
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      collect_static_accesses_expr(c, out)
      collect_static_accesses_block(body, out)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_static_accesses_stmt(s, out)
        None => ()
      }
      match cond {
        Some(e) => collect_static_accesses_expr(e, out)
        None => ()
      }
      match update {
        Some(s) => collect_static_accesses_stmt(s, out)
        None => ()
      }
      collect_static_accesses_block(body, out)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_static_accesses_expr(iter, out)
      collect_static_accesses_block(body, out)
    }
    Switch(e, cases) => {
      collect_static_accesses_expr(e, out)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_static_accesses_expr(te, out)
          None => ()
        }
        collect_static_accesses_block(c.body, out)
      }
    }
    Try(b, _, cb, fb) => {
      collect_static_accesses_block(b, out)
      match cb {
        Some(blk) => collect_static_accesses_block(blk, out)
        None => ()
      }
      match fb {
        Some(blk) => collect_static_accesses_block(blk, out)
        None => ()
      }
    }
    Label(_, inner) => collect_static_accesses_stmt(inner, out)
    Block(b) => collect_static_accesses_block(b, out)
    NativeClassStmt(decl, ctor_body) => {
      // Walk method bodies so internal references count
      // (`this.foo()` from one method keeps `foo` alive).
      for m in decl.methods {
        match m.body {
          Some(b) => collect_static_accesses_block(b, out)
          None => ()
        }
      }
      match ctor_body {
        Some(f) => collect_static_accesses_block(f.body, out)
        None => ()
      }
      // Static field inits may access method names via `this.method`.
      for sf in decl.static_field_inits {
        collect_static_accesses_expr(sf.1, out)
      }
    }
  }
}

///|
fn collect_static_accesses_expr(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    PropAccess(recv, prop) => {
      out[prop] = true
      collect_static_accesses_expr(recv, out)
    }
    IndexAccess(recv, @ast.TsExpr::StringLit(name)) => {
      out[name] = true
      collect_static_accesses_expr(recv, out)
    }
    IndexAccess(recv, idx) => {
      collect_static_accesses_expr(recv, out)
      collect_static_accesses_expr(idx, out)
    }
    // MethodCall does both: marks the method name AND walks the
    // args. (The recv is also walked.)
    MethodCall(recv, m, args) => {
      out[m] = true
      collect_static_accesses_expr(recv, out)
      for a in args {
        collect_static_accesses_expr(a, out)
      }
    }
    PropAssignExpr(recv, _, v) => {
      collect_static_accesses_expr(recv, out)
      collect_static_accesses_expr(v, out)
    }
    IndexAssignExpr(recv, @ast.TsExpr::StringLit(_), v) => {
      collect_static_accesses_expr(recv, out)
      collect_static_accesses_expr(v, out)
    }
    IndexAssignExpr(recv, idx, v) => {
      collect_static_accesses_expr(recv, out)
      collect_static_accesses_expr(idx, out)
      collect_static_accesses_expr(v, out)
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_static_accesses_expr(a, out)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_static_accesses_expr(callee, out)
      for a in args {
        collect_static_accesses_expr(a, out)
      }
    }
    BinOp(_, l, r) | Seq(l, r) => {
      collect_static_accesses_expr(l, out)
      collect_static_accesses_expr(r, out)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | YieldStar(inner) => collect_static_accesses_expr(inner, out)
    Cond(c, t, e) => {
      collect_static_accesses_expr(c, out)
      collect_static_accesses_expr(t, out)
      collect_static_accesses_expr(e, out)
    }
    ArrayLit(items) =>
      for i in items {
        collect_static_accesses_expr(i, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        // Object-literal key names don't count as method accesses.
        collect_static_accesses_expr(ent.1, out)
      }
    ComputedProp(k, v) => {
      collect_static_accesses_expr(k, out)
      collect_static_accesses_expr(v, out)
    }
    AssignExpr(_, v) | AssignPattern(_, v) =>
      collect_static_accesses_expr(v, out)
    CompoundAssignExpr(t, _, v) => {
      collect_static_accesses_expr(t, out)
      collect_static_accesses_expr(v, out)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_static_accesses_expr(e, out)
        ArrowBlock(b) => collect_static_accesses_block(b, out)
      }
    FuncExpr(f) => collect_static_accesses_block(f.body, out)
    DynamicImport(spec, opts) => {
      collect_static_accesses_expr(spec, out)
      match opts {
        Some(o) => collect_static_accesses_expr(o, out)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_static_accesses_expr(tag, out)
      for e in exprs {
        collect_static_accesses_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_static_accesses_expr(e, out)
      }
    As(inner, _) | Satisfies(inner, _) =>
      collect_static_accesses_expr(inner, out)
    Yield(Some(inner)) => collect_static_accesses_expr(inner, out)
    NativeClassExpr(decl, ctor_body) => {
      for m in decl.methods {
        match m.body {
          Some(b) => collect_static_accesses_block(b, out)
          None => ()
        }
      }
      match ctor_body {
        Some(f) => collect_static_accesses_block(f.body, out)
        None => ()
      }
    }
    _ => ()
  }
}

// -- Step 4: rewrite native classes, filtering methods ----------------

///|

///|
/// IIFE-lowered class shape:
///
///   let Foo = function () {
///     function Foo() { ... }                    // constructor
///     Foo.prototype.start = function start() {} // method
///     Foo.prototype.start.__super_proto = ...   // metadata
///     ...
///     return Foo;
///   }();
///
/// Drop every `Foo.prototype.METHOD = …` (and the chained
/// `Foo.prototype.METHOD.X = …` setup that immediately follows)
/// when METHOD doesn't appear in the bundle's access set.
/// `constructor` doesn't appear here; the inner `function Foo() {…}`
/// stays as-is.
fn prune_iife_methods(
  body : @ast.TsBlock,
  class_name : String,
  accessed : Map[String, Bool],
) -> @ast.TsBlock {
  let new_stmts : Array[@ast.TsStmt] = []
  let new_positions : Array[Int] = []
  let has_positions = body.stmt_positions.length() == body.stmts.length()
  for i, s in body.stmts {
    if iife_method_assignment_is_dead(s, class_name, accessed) {
      continue
    }
    new_stmts.push(s)
    if has_positions {
      new_positions.push(body.stmt_positions[i])
    }
  }
  { stmts: new_stmts, stmt_positions: new_positions }
}

///|
/// Returns `true` when this statement is an assignment whose left-
/// hand side mentions `<class_name>.prototype.METHOD` (either as
/// the direct property assigned, or as a sub-property of an
/// already-dead method).
fn iife_method_assignment_is_dead(
  stmt : @ast.TsStmt,
  class_name : String,
  accessed : Map[String, Bool],
) -> Bool {
  match stmt {
    // `Foo.prototype.METHOD = …;`
    PropAssign(
      @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
      method_name,
      _
    ) =>
      if n == class_name &&
        method_name != "constructor" &&
        not(accessed.contains(method_name)) {
        true
      } else {
        false
      }
    // `Foo.prototype.METHOD.SUBKEY = …;` — chained setup for an
    // already-dead method.
    PropAssign(
      @ast.TsExpr::PropAccess(
        @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
        method_name
      ),
      _,
      _
    ) =>
      if n == class_name &&
        method_name != "constructor" &&
        not(accessed.contains(method_name)) {
        true
      } else {
        false
      }
    // `Foo.prototype.METHOD = …;` in expression-statement form.
    Expr(
      @ast.TsExpr::PropAssignExpr(
        @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
        method_name,
        _
      )
    ) =>
      if n == class_name &&
        method_name != "constructor" &&
        not(accessed.contains(method_name)) {
        true
      } else {
        false
      }
    Expr(
      @ast.TsExpr::PropAssignExpr(
        @ast.TsExpr::PropAccess(
          @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
          method_name
        ),
        _,
        _
      )
    ) =>
      if n == class_name &&
        method_name != "constructor" &&
        not(accessed.contains(method_name)) {
        true
      } else {
        false
      }
    _ => false
  }
}

///|
fn dce_stmt(stmt : @ast.TsStmt, accessed : Map[String, Bool]) -> @ast.TsStmt {
  match stmt {
    NativeClassStmt(decl, ctor_body) => {
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        if m.name == "constructor" || accessed.contains(m.name) {
          new_methods.push(m)
        }
      }
      NativeClassStmt({ ..decl, methods: new_methods }, ctor_body)
    }
    // IIFE-lowered class: `let Name = function () { … }();`.
    // Strip unused `Name.prototype.METHOD = …` assignments (and
    // any `Name.prototype.METHOD.subprop = …` chained setup) from
    // the inner function body. Each binder form is handled
    // separately so the rebuild knows which variant to produce.
    Var(b, t, e) =>
      match (b, e) {
        (
          @ast.TsBinding::Ident(n),
          @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), args),
        ) =>
          if args.length() == 0 {
            let pruned_body = prune_iife_methods(f.body, n, accessed)
            let new_fn = @ast.TsExpr::FuncExpr({ ..f, body: pruned_body })
            Var(b, t, @ast.TsExpr::CallExpr(new_fn, []))
          } else {
            Var(b, t, dce_expr(e, accessed))
          }
        _ => Var(b, t, dce_expr(e, accessed))
      }
    Let(b, t, e) =>
      match (b, e) {
        (
          @ast.TsBinding::Ident(n),
          @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), args),
        ) =>
          if args.length() == 0 {
            let pruned_body = prune_iife_methods(f.body, n, accessed)
            let new_fn = @ast.TsExpr::FuncExpr({ ..f, body: pruned_body })
            Let(b, t, @ast.TsExpr::CallExpr(new_fn, []))
          } else {
            Let(b, t, dce_expr(e, accessed))
          }
        _ => Let(b, t, dce_expr(e, accessed))
      }
    Const(b, t, e) =>
      match (b, e) {
        (
          @ast.TsBinding::Ident(n),
          @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), args),
        ) =>
          if args.length() == 0 {
            let pruned_body = prune_iife_methods(f.body, n, accessed)
            let new_fn = @ast.TsExpr::FuncExpr({ ..f, body: pruned_body })
            Const(b, t, @ast.TsExpr::CallExpr(new_fn, []))
          } else {
            Const(b, t, dce_expr(e, accessed))
          }
        _ => Const(b, t, dce_expr(e, accessed))
      }
    Assign(n, e) => Assign(n, dce_expr(e, accessed))
    CompoundAssign(n, op, e) => CompoundAssign(n, op, dce_expr(e, accessed))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        dce_expr(t, accessed),
        dce_expr(idx, accessed),
        dce_expr(v, accessed),
      )
    PropAssign(t, p, v) =>
      PropAssign(dce_expr(t, accessed), p, dce_expr(v, accessed))
    Expr(e) => Expr(dce_expr(e, accessed))
    Return(Some(e)) => Return(Some(dce_expr(e, accessed)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(dce_expr(e, accessed))
    If(c, t, e) =>
      If(
        dce_expr(c, accessed),
        dce_block(t, accessed),
        match e {
          Some(b) => Some(dce_block(b, accessed))
          None => None
        },
      )
    While(c, body) => While(dce_expr(c, accessed), dce_block(body, accessed))
    DoWhile(c, body) =>
      DoWhile(dce_expr(c, accessed), dce_block(body, accessed))
    With(c, body) => With(dce_expr(c, accessed), dce_block(body, accessed))
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(dce_stmt(s, accessed))
          None => None
        },
        match cond {
          Some(e) => Some(dce_expr(e, accessed))
          None => None
        },
        match update {
          Some(s) => Some(dce_stmt(s, accessed))
          None => None
        },
        dce_block(body, accessed),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(k, b, t, dce_expr(iter, accessed), dce_block(body, accessed))
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(k, b, t, dce_expr(iter, accessed), dce_block(body, accessed))
    ForIn(k, b, t, iter, body) =>
      ForIn(k, b, t, dce_expr(iter, accessed), dce_block(body, accessed))
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(dce_expr(te, accessed))
            None => None
          },
          body: dce_block(c.body, accessed),
        })
      }
      Switch(dce_expr(e, accessed), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        dce_block(b, accessed),
        bnd,
        match cb {
          Some(blk) => Some(dce_block(blk, accessed))
          None => None
        },
        match fb {
          Some(blk) => Some(dce_block(blk, accessed))
          None => None
        },
      )
    Label(name, inner) => Label(name, dce_stmt(inner, accessed))
    Block(b) => Block(dce_block(b, accessed))
  }
}

///|
fn dce_block(
  block : @ast.TsBlock,
  accessed : Map[String, Bool],
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(dce_stmt(s, accessed))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn dce_expr(expr : @ast.TsExpr, accessed : Map[String, Bool]) -> @ast.TsExpr {
  match expr {
    NativeClassExpr(decl, ctor_body) => {
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        if m.name == "constructor" || accessed.contains(m.name) {
          new_methods.push(m)
        }
      }
      NativeClassExpr({ ..decl, methods: new_methods }, ctor_body)
    }
    BinOp(op, l, r) => BinOp(op, dce_expr(l, accessed), dce_expr(r, accessed))
    UnaryOp(op, inner) => UnaryOp(op, dce_expr(inner, accessed))
    Cond(c, t, e) =>
      Cond(dce_expr(c, accessed), dce_expr(t, accessed), dce_expr(e, accessed))
    PropAccess(recv, p) => PropAccess(dce_expr(recv, accessed), p)
    IndexAccess(recv, idx) =>
      IndexAccess(dce_expr(recv, accessed), dce_expr(idx, accessed))
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(dce_expr(a, accessed))
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(dce_expr(a, accessed))
      }
      CallExpr(dce_expr(callee, accessed), new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(dce_expr(a, accessed))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(dce_expr(a, accessed))
      }
      NewExpr(dce_expr(callee, accessed), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(dce_expr(a, accessed))
      }
      MethodCall(dce_expr(recv, accessed), m, new_args)
    }
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(dce_expr(i, accessed))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, dce_expr(ent.1, accessed)))
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(dce_expr(inner, accessed))
    Yield(Some(inner)) => Yield(Some(dce_expr(inner, accessed)))
    YieldStar(inner) => YieldStar(dce_expr(inner, accessed))
    Await(inner) => Await(dce_expr(inner, accessed))
    Seq(a, b) => Seq(dce_expr(a, accessed), dce_expr(b, accessed))
    AssignExpr(n, v) => AssignExpr(n, dce_expr(v, accessed))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(dce_expr(t, accessed), op, dce_expr(v, accessed))
    AssignPattern(b, v) => AssignPattern(b, dce_expr(v, accessed))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(dce_expr(recv, accessed), p, dce_expr(v, accessed))
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        dce_expr(recv, accessed),
        dce_expr(idx, accessed),
        dce_expr(v, accessed),
      )
    ComputedProp(k, v) =>
      ComputedProp(dce_expr(k, accessed), dce_expr(v, accessed))
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(dce_expr(e, accessed))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(dce_block(b, accessed))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => FuncExpr({ ..f, body: dce_block(f.body, accessed) })
    DynamicImport(spec, opts) =>
      DynamicImport(
        dce_expr(spec, accessed),
        match opts {
          Some(o) => Some(dce_expr(o, accessed))
          None => None
        },
      )
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(dce_expr(e, accessed))
      }
      TaggedTemplate(dce_expr(tag, accessed), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(dce_expr(e, accessed))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(dce_expr(inner, accessed), ty)
    Satisfies(inner, ty) => Satisfies(dce_expr(inner, accessed), ty)
    NonNull(inner) => NonNull(dce_expr(inner, accessed))
    OptionalChain(inner) => OptionalChain(dce_expr(inner, accessed))
    PureCall(inner) => PureCall(dce_expr(inner, accessed))
    _ => expr
  }
}
