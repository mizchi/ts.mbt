// Class-method DCE — drop instance / static methods (and accessors)
// whose name is never read anywhere in the bundle.
//
// The parser desugars `class Foo { method() { … } }` into an IIFE
// that emits a sequence of `PropAssign(target, "@@define:method",
// FuncExpr(…))` (and `@@get:` / `@@set:` for accessors). Those
// markers are the seam this pass keys off of: they identify a method
// installation site without being confused with a user-written
// `obj.foo = ...` assignment, which we leave alone for safety.
//
// Reachability is purely *name-based*: if the bundle anywhere reads
// `x.method`, calls `x.method(…)`, declares an object literal
// `{ method: … }`, or assigns through `x.method = …`, then every
// `@@define:method` PropAssign survives. That's the same coarseness
// terser uses — we can't tell which class's `method` is being
// touched without full type info, so any reference protects every
// installation.
//
// The pass only drops PropAssigns whose RHS is *pure* (a function
// expression / arrow / literal / Var). Method bodies are always
// `FuncExpr`, so every legitimate desugar pattern is safe. Anything
// with a possibly-impure RHS (a `Call`, `New`, …) survives even if
// the name is dead.

///|
pub fn drop_unused_methods_in_blocks(
  blocks : Array[@ast.TsBlock],
  extra_reserved_props : Array[String],
) -> Array[@ast.TsBlock] {
  // 1. Build the global "referenced clean property name" set. Marker-
  //    prefixed names are *definitions*; we skip them so a method
  //    that only ever shows up at its own install site still counts
  //    as dead. Reserved properties (caller-supplied or built-in)
  //    are added directly so DOM / Promise / prototype names stay.
  let referenced : Map[String, Bool] = {}
  for b in blocks {
    collect_referenced_method_names_in_block(b, referenced)
  }
  for n in extra_reserved_props {
    referenced[n] = true
  }
  // 2. Rewrite each block. We have to recurse into IIFE / nested
  //    function bodies because the class desugar buries the
  //    PropAssigns under `Let(name, _, CallExpr(FuncExpr(body), []))`.
  let out : Array[@ast.TsBlock] = []
  for b in blocks {
    out.push(rewrite_block(b, referenced))
  }
  out
}

// ---------------------------------------------------------------------------
// Reference collection — same shape as `collect_props_in_*` in
// `mangle.mbt`, except it skips marker-prefixed names (those are
// definitions, not uses) and recurses into nested function bodies.
// ---------------------------------------------------------------------------

///|
fn collect_referenced_method_names_in_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_refs_method_in_stmt(s, out)
  }
}

///|
fn add_if_not_marker(name : String, out : Map[String, Bool]) -> Unit {
  if name.has_prefix("@@define:") ||
    name.has_prefix("@@get:") ||
    name.has_prefix("@@set:") {
    return
  }
  out[name] = true
}

///|
fn collect_refs_method_in_stmt(
  stmt : @ast.TsStmt,
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) =>
      collect_refs_method_in_expr(e, out)
    Expr(e) | Throw(e) => collect_refs_method_in_expr(e, out)
    Return(opt) =>
      match opt {
        Some(e) => collect_refs_method_in_expr(e, out)
        None => ()
      }
    Assign(_, e) | CompoundAssign(_, _, e) =>
      collect_refs_method_in_expr(e, out)
    PropAssign(recv, prop, value) => {
      // The install-site marker is a *definition*, not a reference —
      // skip it. User-written `obj.foo = …` (no marker) does count.
      add_if_not_marker(prop, out)
      // The class desugar emits `C.prototype.X.__super_proto = …`
      // right after each method install. That `PropAccess(_, X)` is
      // an internal back-reference, not a user-visible read — if we
      // counted it the method's own install would protect itself.
      if prop == "__super_proto" {
        match recv {
          PropAccess(inner_recv, _) => collect_refs_method_in_expr(inner_recv, out)
          _ => collect_refs_method_in_expr(recv, out)
        }
      } else {
        collect_refs_method_in_expr(recv, out)
      }
      collect_refs_method_in_expr(value, out)
    }
    IndexAssign(recv, idx, value) => {
      collect_refs_method_in_expr(recv, out)
      collect_refs_method_in_expr(idx, out)
      collect_refs_method_in_expr(value, out)
    }
    If(c, t, e_opt) => {
      collect_refs_method_in_expr(c, out)
      collect_referenced_method_names_in_block(t, out)
      match e_opt {
        Some(b) => collect_referenced_method_names_in_block(b, out)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      collect_refs_method_in_expr(c, out)
      collect_referenced_method_names_in_block(b, out)
    }
    For(init_opt, cond_opt, update_opt, body) => {
      match init_opt {
        Some(s) => collect_refs_method_in_stmt(s, out)
        None => ()
      }
      match cond_opt {
        Some(c) => collect_refs_method_in_expr(c, out)
        None => ()
      }
      match update_opt {
        Some(s) => collect_refs_method_in_stmt(s, out)
        None => ()
      }
      collect_referenced_method_names_in_block(body, out)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_refs_method_in_expr(iter, out)
      collect_referenced_method_names_in_block(body, out)
    }
    Switch(scrut, cases) => {
      collect_refs_method_in_expr(scrut, out)
      for c in cases {
        match c.test_expr {
          Some(t) => collect_refs_method_in_expr(t, out)
          None => ()
        }
        collect_referenced_method_names_in_block(c.body, out)
      }
    }
    Try(t, _, c, f) => {
      collect_referenced_method_names_in_block(t, out)
      match c {
        Some(b) => collect_referenced_method_names_in_block(b, out)
        None => ()
      }
      match f {
        Some(b) => collect_referenced_method_names_in_block(b, out)
        None => ()
      }
    }
    Block(b) => collect_referenced_method_names_in_block(b, out)
    Label(_, inner) => collect_refs_method_in_stmt(inner, out)
    With(target, body) => {
      collect_refs_method_in_expr(target, out)
      collect_referenced_method_names_in_block(body, out)
    }
    Break(_) | Continue(_) | Empty | Debugger => ()
  }
}

///|
fn collect_refs_method_in_expr(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    PropAccess(recv, name) => {
      out[name] = true
      collect_refs_method_in_expr(recv, out)
    }
    MethodCall(recv, m, args) => {
      out[m] = true
      collect_refs_method_in_expr(recv, out)
      for a in args {
        collect_refs_method_in_expr(a, out)
      }
    }
    ObjectLit(entries) =>
      for ent in entries {
        if ent.0 != "..." {
          add_if_not_marker(ent.0, out)
        }
        collect_refs_method_in_expr(ent.1, out)
      }
    PropAssignExpr(recv, prop, value) => {
      add_if_not_marker(prop, out)
      // Same desugar-artifact skip as the stmt form above.
      if prop == "__super_proto" {
        match recv {
          PropAccess(inner_recv, _) => collect_refs_method_in_expr(inner_recv, out)
          _ => collect_refs_method_in_expr(recv, out)
        }
      } else {
        collect_refs_method_in_expr(recv, out)
      }
      collect_refs_method_in_expr(value, out)
    }
    IndexAssignExpr(recv, idx, value) => {
      collect_refs_method_in_expr(recv, out)
      collect_refs_method_in_expr(idx, out)
      collect_refs_method_in_expr(value, out)
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_refs_method_in_expr(a, out)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_refs_method_in_expr(callee, out)
      for a in args {
        collect_refs_method_in_expr(a, out)
      }
    }
    IndexAccess(recv, idx) => {
      // `obj["foo"]` — surface the string key just like `obj.foo`.
      match idx {
        StringLit(s) => out[s] = true
        _ => ()
      }
      collect_refs_method_in_expr(recv, out)
      collect_refs_method_in_expr(idx, out)
    }
    BinOp(_, l, r) | Seq(l, r) => {
      collect_refs_method_in_expr(l, out)
      collect_refs_method_in_expr(r, out)
    }
    UnaryOp(_, e) | Spread(e) | Await(e) | YieldStar(e) | NonNull(e) =>
      collect_refs_method_in_expr(e, out)
    OptionalChain(e) => collect_refs_method_in_expr(e, out)
    Yield(opt) =>
      match opt {
        Some(e) => collect_refs_method_in_expr(e, out)
        None => ()
      }
    Cond(c, t, f) => {
      collect_refs_method_in_expr(c, out)
      collect_refs_method_in_expr(t, out)
      collect_refs_method_in_expr(f, out)
    }
    ArrayLit(items) =>
      for it in items {
        collect_refs_method_in_expr(it, out)
      }
    ComputedProp(k, v) => {
      collect_refs_method_in_expr(k, out)
      collect_refs_method_in_expr(v, out)
    }
    AssignExpr(_, e) => collect_refs_method_in_expr(e, out)
    AssignPattern(_, e) => collect_refs_method_in_expr(e, out)
    CompoundAssignExpr(target, _, e) => {
      collect_refs_method_in_expr(target, out)
      collect_refs_method_in_expr(e, out)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_refs_method_in_expr(e, out)
        ArrowBlock(b) => collect_referenced_method_names_in_block(b, out)
      }
    FuncExpr(f) => collect_referenced_method_names_in_block(f.body, out)
    TaggedTemplate(tag, _, _, exprs) => {
      collect_refs_method_in_expr(tag, out)
      for e in exprs {
        collect_refs_method_in_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_refs_method_in_expr(e, out)
      }
    As(e, _) | Satisfies(e, _) => collect_refs_method_in_expr(e, out)
    DynamicImport(spec, opt) => {
      collect_refs_method_in_expr(spec, out)
      match opt {
        Some(o) => collect_refs_method_in_expr(o, out)
        None => ()
      }
    }
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// Rewriter — strip dead install-site PropAssigns. Recurses into
// nested function bodies (where class IIFE PropAssigns live).
// ---------------------------------------------------------------------------

///|
fn strip_method_marker(name : String) -> String? {
  if name.has_prefix("@@define:") {
    Some(name.substring(start=9, end=name.length()).to_string())
  } else if name.has_prefix("@@get:") {
    Some(name.substring(start=6, end=name.length()).to_string())
  } else if name.has_prefix("@@set:") {
    Some(name.substring(start=6, end=name.length()).to_string())
  } else {
    None
  }
}

///|
/// `true` when dropping a `PropAssign(_, _, value)` is provably safe
/// — its RHS evaluation has no observable side effects, so removing
/// the statement preserves program behavior. Conservatively false
/// for anything we can't trivially classify.
fn rhs_is_pure(expr : @ast.TsExpr) -> Bool {
  match expr {
    FuncExpr(_) | ArrowFunc(_, _, _, _) => true
    NumberLit(_) | IntLit(_) | BigIntLit(_) | BoolLit(_) | StringLit(_)
    | NullLit => true
    Var(_) => true
    _ => false
  }
}

///|
fn rewrite_block(
  block : @ast.TsBlock,
  referenced : Map[String, Bool],
) -> @ast.TsBlock {
  let new_stmts : Array[@ast.TsStmt] = []
  let new_positions : Array[Int] = []
  let has_positions = block.stmt_positions.length() == block.stmts.length()
  let n = block.stmts.length()
  let mut i = 0
  while i < n {
    let s = block.stmts[i]
    match try_drop_method_stmt(s, referenced) {
      Drop => {
        // The class desugar follows every `@@define:foo` install
        // with `PropAssign(PropAccess(target, "foo"), "__super_proto",
        // …)`. When we drop the install, that setter becomes a write
        // to an undefined property; nuke it as a pair.
        let dropped_name = method_name_of(s)
        if i + 1 < n && is_super_proto_setter(block.stmts[i + 1], dropped_name) {
          i = i + 2
        } else {
          i = i + 1
        }
      }
      Keep(new_stmt) => {
        new_stmts.push(new_stmt)
        if has_positions {
          new_positions.push(block.stmt_positions[i])
        }
        i = i + 1
      }
    }
  }
  { stmts: new_stmts, stmt_positions: new_positions }
}

///|
/// Return the clean method name embedded in a method-install
/// `PropAssign` / `PropAssignExpr` (whichever marker prefix was on
/// it). Used to match the install with its companion
/// `__super_proto` setter.
fn method_name_of(stmt : @ast.TsStmt) -> String? {
  match stmt {
    PropAssign(_, prop, _) => strip_method_marker(prop)
    Expr(PropAssignExpr(_, prop, _)) => strip_method_marker(prop)
    _ => None
  }
}

///|
/// `true` when `stmt` is the `PropAssign(PropAccess(_, name),
/// "__super_proto", …)` companion that the class desugar emits
/// right after a method install. Matches both the stmt form and
/// the `Expr(PropAssignExpr(...))` form.
fn is_super_proto_setter(stmt : @ast.TsStmt, name : String?) -> Bool {
  let target_name = match name {
    Some(n) => n
    None => return false
  }
  fn matches(recv : @ast.TsExpr, prop : String) -> Bool {
    if prop != "__super_proto" {
      return false
    }
    match recv {
      PropAccess(_, member) => member == target_name
      _ => false
    }
  }

  match stmt {
    PropAssign(recv, prop, _) => matches(recv, prop)
    Expr(PropAssignExpr(recv, prop, _)) => matches(recv, prop)
    _ => false
  }
}

///|
priv enum DceResult {
  Drop
  Keep(@ast.TsStmt)
}

///|
fn try_drop_method_stmt(
  stmt : @ast.TsStmt,
  referenced : Map[String, Bool],
) -> DceResult {
  match stmt {
    PropAssign(_, prop, value) =>
      match strip_method_marker(prop) {
        Some(clean) =>
          if !referenced.contains(clean) && rhs_is_pure(value) {
            return Drop
          }
        None => ()
      }
    Expr(PropAssignExpr(_, prop, value)) =>
      match strip_method_marker(prop) {
        Some(clean) =>
          if !referenced.contains(clean) && rhs_is_pure(value) {
            return Drop
          }
        None => ()
      }
    _ => ()
  }
  Keep(rewrite_stmt(stmt, referenced))
}

///|
/// Walk a stmt and recurse into expressions / blocks so nested
/// class IIFEs inside (say) function bodies also get pruned. The
/// stmt shape itself is unchanged except for the rewritten inner
/// blocks / expressions.
fn rewrite_stmt(
  stmt : @ast.TsStmt,
  referenced : Map[String, Bool],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, rewrite_expr(e, referenced))
    Let(b, t, e) => Let(b, t, rewrite_expr(e, referenced))
    Const(b, t, e) => Const(b, t, rewrite_expr(e, referenced))
    Expr(e) => Expr(rewrite_expr(e, referenced))
    Return(opt) =>
      match opt {
        Some(e) => Return(Some(rewrite_expr(e, referenced)))
        None => stmt
      }
    Throw(e) => Throw(rewrite_expr(e, referenced))
    Assign(name, e) => Assign(name, rewrite_expr(e, referenced))
    CompoundAssign(name, op, e) =>
      CompoundAssign(name, op, rewrite_expr(e, referenced))
    PropAssign(recv, prop, value) =>
      PropAssign(
        rewrite_expr(recv, referenced),
        prop,
        rewrite_expr(value, referenced),
      )
    IndexAssign(recv, idx, value) =>
      IndexAssign(
        rewrite_expr(recv, referenced),
        rewrite_expr(idx, referenced),
        rewrite_expr(value, referenced),
      )
    If(c, t, e_opt) =>
      If(
        rewrite_expr(c, referenced),
        rewrite_block(t, referenced),
        match e_opt {
          Some(b) => Some(rewrite_block(b, referenced))
          None => None
        },
      )
    While(c, b) => While(rewrite_expr(c, referenced), rewrite_block(b, referenced))
    DoWhile(c, b) =>
      DoWhile(rewrite_expr(c, referenced), rewrite_block(b, referenced))
    For(init_opt, cond_opt, update_opt, body) =>
      For(
        match init_opt {
          Some(s) => Some(rewrite_stmt(s, referenced))
          None => None
        },
        match cond_opt {
          Some(c) => Some(rewrite_expr(c, referenced))
          None => None
        },
        match update_opt {
          Some(s) => Some(rewrite_stmt(s, referenced))
          None => None
        },
        rewrite_block(body, referenced),
      )
    ForOf(kind, b, t, iter, body) =>
      ForOf(
        kind,
        b,
        t,
        rewrite_expr(iter, referenced),
        rewrite_block(body, referenced),
      )
    ForAwaitOf(kind, b, t, iter, body) =>
      ForAwaitOf(
        kind,
        b,
        t,
        rewrite_expr(iter, referenced),
        rewrite_block(body, referenced),
      )
    ForIn(kind, b, t, iter, body) =>
      ForIn(
        kind,
        b,
        t,
        rewrite_expr(iter, referenced),
        rewrite_block(body, referenced),
      )
    Switch(scrut, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(t) => Some(rewrite_expr(t, referenced))
            None => None
          },
          body: rewrite_block(c.body, referenced),
        })
      }
      Switch(rewrite_expr(scrut, referenced), new_cases)
    }
    Try(t, b, c, f) =>
      Try(
        rewrite_block(t, referenced),
        b,
        match c {
          Some(blk) => Some(rewrite_block(blk, referenced))
          None => None
        },
        match f {
          Some(blk) => Some(rewrite_block(blk, referenced))
          None => None
        },
      )
    Block(b) => Block(rewrite_block(b, referenced))
    Label(name, inner) => Label(name, rewrite_stmt(inner, referenced))
    With(target, body) =>
      With(rewrite_expr(target, referenced), rewrite_block(body, referenced))
    Break(_) | Continue(_) | Empty | Debugger => stmt
  }
}

///|
fn rewrite_expr(
  expr : @ast.TsExpr,
  referenced : Map[String, Bool],
) -> @ast.TsExpr {
  match expr {
    FuncExpr(f) => {
      let new_body = rewrite_block(f.body, referenced)
      FuncExpr({ ..f, body: new_body })
    }
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(rewrite_expr(e, referenced))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(rewrite_block(b, referenced))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rewrite_expr(a, referenced))
      }
      CallExpr(rewrite_expr(callee, referenced), new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rewrite_expr(a, referenced))
      }
      NewExpr(rewrite_expr(callee, referenced), new_args)
    }
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rewrite_expr(a, referenced))
      }
      Call(name, new_args)
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rewrite_expr(a, referenced))
      }
      New(name, new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rewrite_expr(a, referenced))
      }
      MethodCall(rewrite_expr(recv, referenced), m, new_args)
    }
    PropAccess(recv, n) => PropAccess(rewrite_expr(recv, referenced), n)
    IndexAccess(recv, idx) =>
      IndexAccess(
        rewrite_expr(recv, referenced),
        rewrite_expr(idx, referenced),
      )
    BinOp(op, l, r) =>
      BinOp(op, rewrite_expr(l, referenced), rewrite_expr(r, referenced))
    UnaryOp(op, e) => UnaryOp(op, rewrite_expr(e, referenced))
    Cond(c, t, f) =>
      Cond(
        rewrite_expr(c, referenced),
        rewrite_expr(t, referenced),
        rewrite_expr(f, referenced),
      )
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(rewrite_expr(i, referenced))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, rewrite_expr(ent.1, referenced)))
      }
      ObjectLit(new_entries)
    }
    Spread(e) => Spread(rewrite_expr(e, referenced))
    Await(e) => Await(rewrite_expr(e, referenced))
    YieldStar(e) => YieldStar(rewrite_expr(e, referenced))
    NonNull(e) => NonNull(rewrite_expr(e, referenced))
    OptionalChain(e) => OptionalChain(rewrite_expr(e, referenced))
    Yield(opt) =>
      Yield(match opt {
        Some(e) => Some(rewrite_expr(e, referenced))
        None => None
      })
    Seq(l, r) => Seq(rewrite_expr(l, referenced), rewrite_expr(r, referenced))
    AssignExpr(name, e) => AssignExpr(name, rewrite_expr(e, referenced))
    AssignPattern(b, e) => AssignPattern(b, rewrite_expr(e, referenced))
    CompoundAssignExpr(target, op, e) =>
      CompoundAssignExpr(
        rewrite_expr(target, referenced),
        op,
        rewrite_expr(e, referenced),
      )
    PropAssignExpr(recv, prop, value) =>
      PropAssignExpr(
        rewrite_expr(recv, referenced),
        prop,
        rewrite_expr(value, referenced),
      )
    IndexAssignExpr(recv, idx, value) =>
      IndexAssignExpr(
        rewrite_expr(recv, referenced),
        rewrite_expr(idx, referenced),
        rewrite_expr(value, referenced),
      )
    ComputedProp(k, v) =>
      ComputedProp(rewrite_expr(k, referenced), rewrite_expr(v, referenced))
    TaggedTemplate(tag, strs, raws, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(rewrite_expr(e, referenced))
      }
      TaggedTemplate(rewrite_expr(tag, referenced), strs, raws, new_exprs)
    }
    TemplateLiteral(strs, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(rewrite_expr(e, referenced))
      }
      TemplateLiteral(strs, new_exprs)
    }
    As(e, t) => As(rewrite_expr(e, referenced), t)
    Satisfies(e, t) => Satisfies(rewrite_expr(e, referenced), t)
    DynamicImport(spec, opt) =>
      DynamicImport(
        rewrite_expr(spec, referenced),
        match opt {
          Some(o) => Some(rewrite_expr(o, referenced))
          None => None
        },
      )
    _ => expr
  }
}
