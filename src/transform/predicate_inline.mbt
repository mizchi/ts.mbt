// Type-predicate function inlining.
//
// User-defined type guards like `function isFoo(x): x is Foo { … }`
// almost always have a trivial body (`return cond;`). At every
// call site `isFoo(value)`, the body's `cond` — with the
// parameter substituted by the actual argument — is equivalent
// to the call. Inlining trades a function call for a few extra
// bytes of the substituted expression; in minify mode the bytes
// shrink even further, and the unused-after-inline predicate
// declaration falls out via treeshake.
//
// Constraints (conservative for now):
//   - The function has exactly one parameter (most type guards
//     do; multi-arg cases are rare and harder to substitute
//     safely without alpha-renaming).
//   - The return type is `TypePredicate(_, _)` (i.e. the
//     `x is T` form). Functions that happen to return bool but
//     aren't tagged as type guards are NOT inlined — those
//     might have side effects, and the user didn't claim
//     purity.
//   - The body is exactly `{ return <expr>; }`. Multi-statement
//     bodies bail out: even if pure, mangling at inlining
//     time is risky.

///|
/// Pre-built predicate-inlining table. Keys are the function
/// names; values carry the single parameter name + the body
/// expression to substitute.
pub(all) struct PredicateTable {
  entries : Map[String, PredicateEntry]
}

///|
pub(all) struct PredicateEntry {
  param_name : String
  body_expr : @ast.TsExpr
}

///|
/// Build the substitution table from a flat block of top-level
/// declarations. Only `Let / Const / Var(Ident(name), _,
/// FuncExpr({…}))` shapes with a `TypePredicate` return type and
/// a one-statement `Return(Some(_))` body qualify.
pub fn build_predicate_table(block : @ast.TsBlock) -> PredicateTable {
  let entries : Map[String, PredicateEntry] = {}
  for stmt in block.stmts {
    match stmt {
      Let(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Const(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Var(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f)) =>
        match try_extract_predicate(f) {
          Some(entry) => entries[name] = entry
          None => ()
        }
      _ => ()
    }
  }
  { entries, }
}

///|
fn try_extract_predicate(f : @ast.TsFunc) -> PredicateEntry? {
  // Return type must be `TypePredicate(_, _)`.
  match f.return_type {
    TypePredicate(_, _) => ()
    _ => return None
  }
  if f.params.length() != 1 {
    return None
  }
  // Body must be a single `return EXPR;` stmt.
  if f.body.stmts.length() != 1 {
    return None
  }
  let return_expr = match f.body.stmts[0] {
    Return(Some(e)) => e
    _ => return None
  }
  let param = f.params[0]
  // The param is always a simple `name` for the type-guard
  // shape; destructuring as the lone param is rare and we
  // don't try to support it.
  let name = match param.binding {
    Some(@ast.TsBinding::Ident(n)) => n
    Some(_) => return None
    None => param.name
  }
  Some({ param_name: name, body_expr: return_expr })
}

///|
/// Walk `block`, substituting every call to a known predicate
/// with the inlined body expression (with the parameter
/// substituted by the actual argument).
pub fn inline_predicates(
  block : @ast.TsBlock,
  table : PredicateTable,
) -> @ast.TsBlock {
  if table.entries.is_empty() {
    return block
  }
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(inline_predicates_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn inline_predicates_stmt(
  stmt : @ast.TsStmt,
  table : PredicateTable,
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, inline_predicates_expr(e, table))
    Let(b, t, e) => Let(b, t, inline_predicates_expr(e, table))
    Const(b, t, e) => Const(b, t, inline_predicates_expr(e, table))
    Assign(n, e) => Assign(n, inline_predicates_expr(e, table))
    CompoundAssign(n, op, e) =>
      CompoundAssign(n, op, inline_predicates_expr(e, table))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        inline_predicates_expr(t, table),
        inline_predicates_expr(idx, table),
        inline_predicates_expr(v, table),
      )
    PropAssign(t, prop, v) =>
      PropAssign(
        inline_predicates_expr(t, table),
        prop,
        inline_predicates_expr(v, table),
      )
    Expr(e) => Expr(inline_predicates_expr(e, table))
    Return(Some(e)) => Return(Some(inline_predicates_expr(e, table)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(inline_predicates_expr(e, table))
    If(c, t, e) =>
      If(
        inline_predicates_expr(c, table),
        inline_predicates_block(t, table),
        match e {
          Some(b) => Some(inline_predicates_block(b, table))
          None => None
        },
      )
    While(c, body) =>
      While(
        inline_predicates_expr(c, table),
        inline_predicates_block(body, table),
      )
    DoWhile(c, body) =>
      DoWhile(
        inline_predicates_expr(c, table),
        inline_predicates_block(body, table),
      )
    With(c, body) =>
      With(
        inline_predicates_expr(c, table),
        inline_predicates_block(body, table),
      )
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(inline_predicates_stmt(s, table))
          None => None
        },
        match cond {
          Some(e) => Some(inline_predicates_expr(e, table))
          None => None
        },
        match update {
          Some(s) => Some(inline_predicates_stmt(s, table))
          None => None
        },
        inline_predicates_block(body, table),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        b,
        t,
        inline_predicates_expr(iter, table),
        inline_predicates_block(body, table),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        inline_predicates_expr(iter, table),
        inline_predicates_block(body, table),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        inline_predicates_expr(iter, table),
        inline_predicates_block(body, table),
      )
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(inline_predicates_expr(te, table))
            None => None
          },
          body: inline_predicates_block(c.body, table),
        })
      }
      Switch(inline_predicates_expr(e, table), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        inline_predicates_block(b, table),
        bnd,
        match cb {
          Some(blk) => Some(inline_predicates_block(blk, table))
          None => None
        },
        match fb {
          Some(blk) => Some(inline_predicates_block(blk, table))
          None => None
        },
      )
    Label(name, inner) => Label(name, inline_predicates_stmt(inner, table))
    Block(b) => Block(inline_predicates_block(b, table))
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: inline_predicates_block(f.body, table) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(inline_predicates_block(b, table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, inline_predicates_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(inline_predicates_expr(b, table))
        None => None
      }
      NativeClassStmt(
        {
          ..decl,
          base_expr: new_base_expr,
          methods: new_methods,
          static_field_inits: new_static_fields,
        },
        new_ctor,
      )
    }
  }
}

///|
fn inline_predicates_block(
  block : @ast.TsBlock,
  table : PredicateTable,
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(inline_predicates_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn inline_predicates_expr(
  expr : @ast.TsExpr,
  table : PredicateTable,
) -> @ast.TsExpr {
  match expr {
    // The pattern we care about — `predicate(arg)` where
    // `predicate` is in the table.
    Call(name, args) =>
      match table.entries.get(name) {
        Some(entry) =>
          if args.length() == 1 {
            substitute_param_with_arg(
              entry.body_expr,
              entry.param_name,
              args[0],
            )
          } else {
            // Different arity than expected — fall back to the
            // original Call. (Type-guards always take one arg in
            // the shape we accept.)
            let new_args : Array[@ast.TsExpr] = []
            for a in args {
              new_args.push(inline_predicates_expr(a, table))
            }
            Call(name, new_args)
          }
        None => {
          let new_args : Array[@ast.TsExpr] = []
          for a in args {
            new_args.push(inline_predicates_expr(a, table))
          }
          Call(name, new_args)
        }
      }
    CallExpr(callee, args) => {
      // `CallExpr(Var(name), [arg])` — try the predicate rewrite
      // the same as the `Call(name, [arg])` form above.
      match callee {
        @ast.TsExpr::Var(name) =>
          match table.entries.get(name) {
            Some(entry) =>
              if args.length() == 1 {
                return substitute_param_with_arg(
                  entry.body_expr,
                  entry.param_name,
                  args[0],
                )
              }
            None => ()
          }
        _ => ()
      }
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_predicates_expr(a, table))
      }
      CallExpr(inline_predicates_expr(callee, table), new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_predicates_expr(a, table))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_predicates_expr(a, table))
      }
      NewExpr(inline_predicates_expr(callee, table), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_predicates_expr(a, table))
      }
      MethodCall(inline_predicates_expr(recv, table), m, new_args)
    }
    BinOp(op, l, r) =>
      BinOp(
        op,
        inline_predicates_expr(l, table),
        inline_predicates_expr(r, table),
      )
    UnaryOp(op, inner) => UnaryOp(op, inline_predicates_expr(inner, table))
    Cond(c, t, e) =>
      Cond(
        inline_predicates_expr(c, table),
        inline_predicates_expr(t, table),
        inline_predicates_expr(e, table),
      )
    PropAccess(recv, p) => PropAccess(inline_predicates_expr(recv, table), p)
    IndexAccess(recv, idx) =>
      IndexAccess(
        inline_predicates_expr(recv, table),
        inline_predicates_expr(idx, table),
      )
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(inline_predicates_expr(i, table))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, inline_predicates_expr(ent.1, table)))
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(inline_predicates_expr(inner, table))
    Yield(Some(inner)) => Yield(Some(inline_predicates_expr(inner, table)))
    YieldStar(inner) => YieldStar(inline_predicates_expr(inner, table))
    Await(inner) => Await(inline_predicates_expr(inner, table))
    Seq(a, b) =>
      Seq(inline_predicates_expr(a, table), inline_predicates_expr(b, table))
    AssignExpr(n, v) => AssignExpr(n, inline_predicates_expr(v, table))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        inline_predicates_expr(t, table),
        op,
        inline_predicates_expr(v, table),
      )
    AssignPattern(b, v) => AssignPattern(b, inline_predicates_expr(v, table))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(
        inline_predicates_expr(recv, table),
        p,
        inline_predicates_expr(v, table),
      )
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        inline_predicates_expr(recv, table),
        inline_predicates_expr(idx, table),
        inline_predicates_expr(v, table),
      )
    ComputedProp(k, v) =>
      ComputedProp(
        inline_predicates_expr(k, table),
        inline_predicates_expr(v, table),
      )
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) =>
          @ast.TsArrowBody::ArrowExpr(inline_predicates_expr(e, table))
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(inline_predicates_block(b, table))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let new_body = inline_predicates_block(f.body, table)
      FuncExpr({ ..f, body: new_body })
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(inline_predicates_expr(o, table))
        None => None
      }
      DynamicImport(inline_predicates_expr(spec, table), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(inline_predicates_expr(e, table))
      }
      TaggedTemplate(inline_predicates_expr(tag, table), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(inline_predicates_expr(e, table))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(inline_predicates_expr(inner, table), ty)
    Satisfies(inner, ty) => Satisfies(inline_predicates_expr(inner, table), ty)
    NonNull(inner) => NonNull(inline_predicates_expr(inner, table))
    OptionalChain(inner) => OptionalChain(inline_predicates_expr(inner, table))
    PureCall(inner) => PureCall(inline_predicates_expr(inner, table))
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: inline_predicates_block(f.body, table) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(inline_predicates_block(b, table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, inline_predicates_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(inline_predicates_expr(b, table))
        None => None
      }
      NativeClassExpr(
        {
          ..decl,
          base_expr: new_base_expr,
          methods: new_methods,
          static_field_inits: new_static_fields,
        },
        new_ctor,
      )
    }
    _ => expr
  }
}

///|
/// Substitute every `Var(param_name)` reference inside `expr`
/// with `arg`. Inner function bodies create a new scope that
/// might shadow the parameter, but for the simple type-guard
/// shape we support (`return <cond>;`) closures inside the
/// expression are vanishingly rare; if seen, we still
/// substitute — at worst the inner closure was capturing the
/// outer param.
fn substitute_param_with_arg(
  expr : @ast.TsExpr,
  param_name : String,
  arg : @ast.TsExpr,
) -> @ast.TsExpr {
  match expr {
    Var(n) => if n == param_name { arg } else { expr }
    BinOp(op, l, r) =>
      BinOp(
        op,
        substitute_param_with_arg(l, param_name, arg),
        substitute_param_with_arg(r, param_name, arg),
      )
    UnaryOp(op, inner) =>
      UnaryOp(op, substitute_param_with_arg(inner, param_name, arg))
    Cond(c, t, e) =>
      Cond(
        substitute_param_with_arg(c, param_name, arg),
        substitute_param_with_arg(t, param_name, arg),
        substitute_param_with_arg(e, param_name, arg),
      )
    Call(n, args) =>
      if n == param_name {
        // Parameter being called — substitute through CallExpr.
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(substitute_param_with_arg(a, param_name, arg))
        }
        CallExpr(arg, new_args)
      } else {
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(substitute_param_with_arg(a, param_name, arg))
        }
        Call(n, new_args)
      }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_param_with_arg(a, param_name, arg))
      }
      CallExpr(substitute_param_with_arg(callee, param_name, arg), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_param_with_arg(a, param_name, arg))
      }
      MethodCall(substitute_param_with_arg(recv, param_name, arg), m, new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_param_with_arg(a, param_name, arg))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_param_with_arg(a, param_name, arg))
      }
      NewExpr(substitute_param_with_arg(callee, param_name, arg), new_args)
    }
    PropAccess(recv, p) =>
      PropAccess(substitute_param_with_arg(recv, param_name, arg), p)
    IndexAccess(recv, idx) =>
      IndexAccess(
        substitute_param_with_arg(recv, param_name, arg),
        substitute_param_with_arg(idx, param_name, arg),
      )
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(substitute_param_with_arg(i, param_name, arg))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push(
          (ent.0, substitute_param_with_arg(ent.1, param_name, arg)),
        )
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(substitute_param_with_arg(inner, param_name, arg))
    Await(inner) => Await(substitute_param_with_arg(inner, param_name, arg))
    NonNull(inner) => NonNull(substitute_param_with_arg(inner, param_name, arg))
    OptionalChain(inner) =>
      OptionalChain(substitute_param_with_arg(inner, param_name, arg))
    As(inner, ty) => As(substitute_param_with_arg(inner, param_name, arg), ty)
    Satisfies(inner, ty) =>
      Satisfies(substitute_param_with_arg(inner, param_name, arg), ty)
    _ => expr
  }
}
