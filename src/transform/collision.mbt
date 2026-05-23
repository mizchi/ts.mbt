// Bundle-level name-collision resolution.
//
// When two modules each declare a top-level binding with the same
// name (e.g. each has a private `helper` function), concatenating
// them into one global scope produces a runtime
// `SyntaxError: Identifier 'X' has already been declared`. The
// bundler walks modules in topological order, tracks which names
// have been claimed at top level, and for each subsequent module
// renames any colliding binding (plus every reference to it
// within that module) to a fresh `<name>$<n>` slot.
//
// Renaming is purely local to the module being rewritten —
// references that cross module boundaries already go through the
// import-aliasing layer the bundler emits, so renaming the source
// side of a binding doesn't require touching the consumer.

///|
/// Walk every block in `order`, collect each module's top-level
/// identifier names, and rewrite any collisions. The first module
/// to claim a name keeps it; later modules get suffix-renamed.
/// Mutates the passed-in module blocks in place.
pub fn resolve_top_level_collisions(
  blocks : Array[@ast.TsBlock],
) -> Array[@ast.TsBlock] {
  let claimed : Map[String, Bool] = {}
  let out : Array[@ast.TsBlock] = []
  for b in blocks {
    let local_names = collect_top_level_names(b)
    let rename_map : Map[String, String] = {}
    for name in local_names {
      if claimed.contains(name) {
        // Allocate a unique suffix. `<name>$<n>` for the smallest
        // `n` not yet claimed in either the global set or the
        // module's own renamed namespace.
        let mut n = 1
        let mut candidate = name + "$" + n.to_string()
        while claimed.contains(candidate) || rename_map.contains(candidate) {
          n = n + 1
          candidate = name + "$" + n.to_string()
        }
        rename_map[name] = candidate
        claimed[candidate] = true
      } else {
        claimed[name] = true
      }
    }
    if rename_map.size() == 0 {
      out.push(b)
    } else {
      out.push(rename_block_top(b, rename_map))
    }
  }
  out
}

///|
/// Gather the names of every top-level `Let` / `Const` / `Var`
/// binding that introduces a single Ident. Destructuring patterns
/// at top level contribute every name they bind.
fn collect_top_level_names(block : @ast.TsBlock) -> Array[String] {
  let out : Array[String] = []
  for s in block.stmts {
    match s {
      Var(@ast.TsBinding::Ident(n), _, _)
      | Let(@ast.TsBinding::Ident(n), _, _)
      | Const(@ast.TsBinding::Ident(n), _, _) => out.push(n)
      Var(b, _, _) | Let(b, _, _) | Const(b, _, _) =>
        collect_binding_idents(b, out)
      _ => ()
    }
  }
  out
}

///|
fn collect_binding_idents(b : @ast.TsBinding, out : Array[String]) -> Unit {
  match b {
    Ident(n) => out.push(n)
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => collect_binding_idents(be.binding, out)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_binding_idents(r, out)
        None => ()
      }
    }
    Object(ob) => {
      for p in ob.props {
        collect_binding_idents(p.binding, out)
      }
      match ob.rest {
        Some(n) => out.push(n)
        None => ()
      }
    }
    Target(_) => ()
  }
}

// ---------------------------------------------------------------------------
// Renamer — walk every stmt / expr in the block and substitute the
// renamed names on both the binding side and the reference side.
// ---------------------------------------------------------------------------

///|
fn rename_block_top(
  block : @ast.TsBlock,
  rename : Map[String, String],
) -> @ast.TsBlock {
  let new_stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    new_stmts.push(rename_stmt_top(s, rename))
  }
  { stmts: new_stmts, stmt_positions: block.stmt_positions }
}

///|
fn rename_top(name : String, rename : Map[String, String]) -> String {
  match rename.get(name) {
    Some(n) => n
    None => name
  }
}

///|
fn rename_binding_top(
  b : @ast.TsBinding,
  rename : Map[String, String],
) -> @ast.TsBinding {
  match b {
    Ident(n) => Ident(rename_top(n, rename))
    Array(ab) => {
      let new_items : Array[@ast.TsBindingElem?] = []
      for elem in ab.items {
        match elem {
          Some(be) => {
            let new_inner = rename_binding_top(be.binding, rename)
            let new_default = match be.default {
              Some(d) => Some(rename_expr_top(d, rename))
              None => None
            }
            new_items.push(Some({ binding: new_inner, default: new_default }))
          }
          None => new_items.push(None)
        }
      }
      let new_rest = match ab.rest {
        Some(r) => Some(rename_binding_top(r, rename))
        None => None
      }
      Array({ items: new_items, rest: new_rest })
    }
    Object(ob) => {
      let new_props : Array[@ast.TsObjectBindingProp] = []
      for p in ob.props {
        new_props.push({
          key: p.key,
          key_expr: p.key_expr,
          binding: rename_binding_top(p.binding, rename),
          default: match p.default {
            Some(d) => Some(rename_expr_top(d, rename))
            None => None
          },
        })
      }
      let new_rest : String? = match ob.rest {
        Some(n) => Some(rename_top(n, rename))
        None => None
      }
      Object({ props: new_props, rest: new_rest })
    }
    Target(e) => Target(rename_expr_top(e, rename))
  }
}

///|
fn rename_stmt_top(
  stmt : @ast.TsStmt,
  rename : Map[String, String],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) =>
      Var(rename_binding_top(b, rename), t, rename_expr_top(e, rename))
    Let(b, t, e) =>
      Let(rename_binding_top(b, rename), t, rename_expr_top(e, rename))
    Const(b, t, e) =>
      Const(rename_binding_top(b, rename), t, rename_expr_top(e, rename))
    Expr(e) => Expr(rename_expr_top(e, rename))
    Return(opt) =>
      match opt {
        Some(e) => Return(Some(rename_expr_top(e, rename)))
        None => stmt
      }
    Throw(e) => Throw(rename_expr_top(e, rename))
    Assign(name, e) =>
      Assign(rename_top(name, rename), rename_expr_top(e, rename))
    CompoundAssign(name, op, e) =>
      CompoundAssign(rename_top(name, rename), op, rename_expr_top(e, rename))
    PropAssign(recv, prop, value) =>
      PropAssign(
        rename_expr_top(recv, rename),
        prop,
        rename_expr_top(value, rename),
      )
    IndexAssign(recv, idx, value) =>
      IndexAssign(
        rename_expr_top(recv, rename),
        rename_expr_top(idx, rename),
        rename_expr_top(value, rename),
      )
    If(c, t, e_opt) =>
      If(
        rename_expr_top(c, rename),
        rename_block_top(t, rename),
        match e_opt {
          Some(b) => Some(rename_block_top(b, rename))
          None => None
        },
      )
    While(c, b) => While(rename_expr_top(c, rename), rename_block_top(b, rename))
    DoWhile(c, b) =>
      DoWhile(rename_expr_top(c, rename), rename_block_top(b, rename))
    For(init_opt, cond_opt, update_opt, body) =>
      For(
        match init_opt {
          Some(s) => Some(rename_stmt_top(s, rename))
          None => None
        },
        match cond_opt {
          Some(c) => Some(rename_expr_top(c, rename))
          None => None
        },
        match update_opt {
          Some(s) => Some(rename_stmt_top(s, rename))
          None => None
        },
        rename_block_top(body, rename),
      )
    ForOf(kind, b, t, iter, body) =>
      ForOf(
        kind,
        rename_binding_top(b, rename),
        t,
        rename_expr_top(iter, rename),
        rename_block_top(body, rename),
      )
    ForAwaitOf(kind, b, t, iter, body) =>
      ForAwaitOf(
        kind,
        rename_binding_top(b, rename),
        t,
        rename_expr_top(iter, rename),
        rename_block_top(body, rename),
      )
    ForIn(kind, b, t, iter, body) =>
      ForIn(
        kind,
        rename_binding_top(b, rename),
        t,
        rename_expr_top(iter, rename),
        rename_block_top(body, rename),
      )
    Switch(scrut, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(t) => Some(rename_expr_top(t, rename))
            None => None
          },
          body: rename_block_top(c.body, rename),
        })
      }
      Switch(rename_expr_top(scrut, rename), new_cases)
    }
    Try(t, b, c, f) =>
      Try(
        rename_block_top(t, rename),
        match b {
          Some(bb) => Some(rename_binding_top(bb, rename))
          None => None
        },
        match c {
          Some(blk) => Some(rename_block_top(blk, rename))
          None => None
        },
        match f {
          Some(blk) => Some(rename_block_top(blk, rename))
          None => None
        },
      )
    Block(b) => Block(rename_block_top(b, rename))
    Label(name, inner) => Label(name, rename_stmt_top(inner, rename))
    With(target, body) =>
      With(rename_expr_top(target, rename), rename_block_top(body, rename))
    Break(_) | Continue(_) | Empty | Debugger => stmt
  }
}

///|
fn rename_expr_top(
  expr : @ast.TsExpr,
  rename : Map[String, String],
) -> @ast.TsExpr {
  match expr {
    Var(n) => Var(rename_top(n, rename))
    Call(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr_top(a, rename))
      }
      Call(rename_top(n, rename), new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr_top(a, rename))
      }
      New(rename_top(n, rename), new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr_top(a, rename))
      }
      CallExpr(rename_expr_top(callee, rename), new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr_top(a, rename))
      }
      NewExpr(rename_expr_top(callee, rename), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr_top(a, rename))
      }
      MethodCall(rename_expr_top(recv, rename), m, new_args)
    }
    PropAccess(recv, name) => PropAccess(rename_expr_top(recv, rename), name)
    IndexAccess(recv, idx) =>
      IndexAccess(rename_expr_top(recv, rename), rename_expr_top(idx, rename))
    BinOp(op, l, r) =>
      BinOp(op, rename_expr_top(l, rename), rename_expr_top(r, rename))
    UnaryOp(op, e) => UnaryOp(op, rename_expr_top(e, rename))
    Cond(c, t, f) =>
      Cond(
        rename_expr_top(c, rename),
        rename_expr_top(t, rename),
        rename_expr_top(f, rename),
      )
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for it in items {
        new_items.push(rename_expr_top(it, rename))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, rename_expr_top(ent.1, rename)))
      }
      ObjectLit(new_entries)
    }
    Spread(e) => Spread(rename_expr_top(e, rename))
    Await(e) => Await(rename_expr_top(e, rename))
    YieldStar(e) => YieldStar(rename_expr_top(e, rename))
    NonNull(e) => NonNull(rename_expr_top(e, rename))
    OptionalChain(e) => OptionalChain(rename_expr_top(e, rename))
    Yield(opt) =>
      Yield(match opt {
        Some(e) => Some(rename_expr_top(e, rename))
        None => None
      })
    Seq(l, r) => Seq(rename_expr_top(l, rename), rename_expr_top(r, rename))
    AssignExpr(n, e) =>
      AssignExpr(rename_top(n, rename), rename_expr_top(e, rename))
    AssignPattern(b, e) =>
      AssignPattern(rename_binding_top(b, rename), rename_expr_top(e, rename))
    CompoundAssignExpr(t, op, e) =>
      CompoundAssignExpr(
        rename_expr_top(t, rename),
        op,
        rename_expr_top(e, rename),
      )
    PropAssignExpr(recv, prop, value) =>
      PropAssignExpr(
        rename_expr_top(recv, rename),
        prop,
        rename_expr_top(value, rename),
      )
    IndexAssignExpr(recv, idx, value) =>
      IndexAssignExpr(
        rename_expr_top(recv, rename),
        rename_expr_top(idx, rename),
        rename_expr_top(value, rename),
      )
    ComputedProp(k, v) =>
      ComputedProp(rename_expr_top(k, rename), rename_expr_top(v, rename))
    ArrowFunc(params, ret, body, is_async) => {
      let new_params : Array[@ast.TsParam] = []
      for p in params {
        new_params.push({
          ..p,
          binding: match p.binding {
            Some(b) => Some(rename_binding_top(b, rename))
            None => None
          },
          default: match p.default {
            Some(d) => Some(rename_expr_top(d, rename))
            None => None
          },
        })
      }
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(rename_expr_top(e, rename))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(rename_block_top(b, rename))
      }
      ArrowFunc(new_params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let new_params : Array[@ast.TsParam] = []
      for p in f.params {
        new_params.push({
          ..p,
          binding: match p.binding {
            Some(b) => Some(rename_binding_top(b, rename))
            None => None
          },
          default: match p.default {
            Some(d) => Some(rename_expr_top(d, rename))
            None => None
          },
        })
      }
      FuncExpr({
        ..f,
        params: new_params,
        body: rename_block_top(f.body, rename),
      })
    }
    TaggedTemplate(tag, strs, raws, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for ex in exprs {
        new_exprs.push(rename_expr_top(ex, rename))
      }
      TaggedTemplate(rename_expr_top(tag, rename), strs, raws, new_exprs)
    }
    TemplateLiteral(strs, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for ex in exprs {
        new_exprs.push(rename_expr_top(ex, rename))
      }
      TemplateLiteral(strs, new_exprs)
    }
    As(e, t) => As(rename_expr_top(e, rename), t)
    Satisfies(e, t) => Satisfies(rename_expr_top(e, rename), t)
    DynamicImport(spec, opt) =>
      DynamicImport(
        rename_expr_top(spec, rename),
        match opt {
          Some(o) => Some(rename_expr_top(o, rename))
          None => None
        },
      )
    _ => expr
  }
}
