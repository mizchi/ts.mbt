// Type-driven constant folding.
//
// Looks for two specific patterns where TS type annotations let
// us decide a runtime check at compile time:
//
//   typeof x === "type" / typeof x !== "type"
//   x === null / x !== null  (and `=== undefined` / `!== undefined`)
//
// When `x` has a static, single-primitive type annotation in
// scope (a `let x: number`, a function parameter `x: string`,
// etc.), the result is statically `true` / `false` and the
// surrounding fold pass folds it further.
//
// Scope tracking is intentionally simple: a chain of layers that
// grows as we enter blocks, function / arrow bodies (for
// parameters) and Let / Const / Var declarations. We do NOT do
// narrowing across `if (typeof x === "string")` branches — that's
// full flow-sensitive analysis and out of scope for this pass.

///|
/// One lexical layer of the fold's type environment, pointing at its
/// parent rather than copying it.
///
/// This used to be a plain `Map[String, TsType]` that every block and
/// every function body copied entry by entry. The copy is what made the
/// pass expensive on deeply nested code: `checker.ts` spent roughly a
/// tenth of the whole compile inserting into and re-hashing those
/// copies (callgrind put ~1M scope-entry copies in `type_fold_block_in`
/// alone, plus the `String::hash` on each insert). A layer costs two
/// empty maps regardless of how large the enclosing scope is.
///
/// The semantics are the ones copying gave: a write lands in the
/// innermost layer, so it is visible to the rest of that block and to
/// blocks nested inside it, and invisible to the parent and to
/// siblings. `hidden` carries the one thing a copy could express and a
/// bare parent chain cannot — a parameter with no useful annotation
/// shadowing an outer binding of the same name, which must read as
/// "unknown" inside the body rather than falling through to the outer
/// type.
priv struct TypeScope {
  own : Map[String, @ast.TsType]
  hidden : Map[String, Bool]
  parent : TypeScope?
}

///|
fn TypeScope::root() -> TypeScope {
  { own: {}, hidden: {}, parent: None }
}

///|
fn TypeScope::child(self : TypeScope) -> TypeScope {
  { own: {}, hidden: {}, parent: Some(self) }
}

///|
fn TypeScope::set(self : TypeScope, name : String, ty : @ast.TsType) -> Unit {
  let _ = self.hidden.remove(name)
  self.own[name] = ty
}

///|
/// Shadow `name` in this layer with no type — the layered form of the
/// `remove` a copied map used to do.
fn TypeScope::hide(self : TypeScope, name : String) -> Unit {
  let _ = self.own.remove(name)
  self.hidden[name] = true
}

///|
fn TypeScope::get(self : TypeScope, name : String) -> @ast.TsType? {
  let mut cur : TypeScope? = Some(self)
  while true {
    match cur {
      Some(layer) => {
        match layer.own.get(name) {
          Some(t) => return Some(t)
          None => ()
        }
        if layer.hidden.contains(name) {
          return None
        }
        cur = layer.parent
      }
      None => break
    }
  }
  None
}

///|
pub fn type_fold_block(
  block : @ast.TsBlock,
  type_aliases? : Array[@ast.TsTypeAlias] = [],
) -> @ast.TsBlock {
  // Cheap pre-scan: type-fold only does work when something it can
  // act on appears in the block — `typeof` comparisons, `=== null`
  // checks, or a switch on a literal-string union. If none of those
  // are present, the full recursive walk would do nothing useful;
  // skip it and avoid the cost on bundles that don't need it.
  if !block_needs_type_fold(block) {
    return block
  }
  let scope = TypeScope::root()
  let alias_table : Map[String, @ast.TsType] = {}
  // Cross-module bundles can contribute multiple aliases sharing one
  // name (e.g. two modules each declaring `type Shape = …`). Keying by
  // bare name picks the last writer wholesale and could narrow an
  // earlier module's switch, dropping a reachable `default` arm. When
  // names collide with different bodies, drop the entry so resolution
  // falls back to `Named(n)` and the folder stays conservative.
  let ambiguous_alias : Map[String, Unit] = {}
  for ta in type_aliases {
    // Only non-generic aliases participate in eager Named-resolution.
    // Generic ones (`Foo<T> = …`) need parameter substitution that the
    // simpler type_fold path doesn't model — they stay as `Named(…)`
    // and the existing fallbacks apply.
    if ta.type_params.length() != 0 {
      continue
    }
    if ambiguous_alias.contains(ta.name) {
      continue
    }
    match alias_table.get(ta.name) {
      Some(existing) =>
        if existing != ta.type_ {
          let _ = alias_table.remove(ta.name)
          ambiguous_alias[ta.name] = ()
        }
      None => alias_table[ta.name] = ta.type_
    }
  }
  type_fold_block_in(block, scope, alias_table)
}

///|
// Resolve a `Named(name)` against the type-alias table, chasing one
// level deep. Returns the alias body when the lookup succeeds, the
// original type otherwise. Used at scope-insertion sites so the
// downstream walkers see the structural form of user-declared
// discriminated unions / interfaces.
fn resolve_alias(
  ty : @ast.TsType,
  aliases : Map[String, @ast.TsType],
) -> @ast.TsType {
  match ty {
    Named(name) =>
      match aliases.get(name) {
        Some(body) => body
        None => ty
      }
    _ => ty
  }
}

///|
fn block_needs_type_fold(block : @ast.TsBlock) -> Bool {
  for s in block.stmts {
    if stmt_needs_type_fold(s) {
      return true
    }
  }
  false
}

///|
fn stmt_needs_type_fold(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Throw(e) => expr_needs_type_fold(e)
    Return(Some(e)) => expr_needs_type_fold(e)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => false
    IndexAssign(t, idx, v) =>
      expr_needs_type_fold(t) ||
      expr_needs_type_fold(idx) ||
      expr_needs_type_fold(v)
    PropAssign(t, _, v) => expr_needs_type_fold(t) || expr_needs_type_fold(v)
    If(c, t, e) => {
      if expr_needs_type_fold(c) {
        return true
      }
      if block_needs_type_fold(t) {
        return true
      }
      match e {
        Some(b) => block_needs_type_fold(b)
        None => false
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) =>
      expr_needs_type_fold(c) || block_needs_type_fold(body)
    For(init, cond, update, body) => {
      let init_b = match init {
        Some(s) => stmt_needs_type_fold(s)
        None => false
      }
      if init_b {
        return true
      }
      let cond_b = match cond {
        Some(e) => expr_needs_type_fold(e)
        None => false
      }
      if cond_b {
        return true
      }
      let upd_b = match update {
        Some(s) => stmt_needs_type_fold(s)
        None => false
      }
      if upd_b {
        return true
      }
      block_needs_type_fold(body)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) =>
      expr_needs_type_fold(iter) || block_needs_type_fold(body)
    // Switch with an exhaustive default-drop target counts.
    Switch(e, cases) => {
      if expr_needs_type_fold(e) {
        return true
      }
      // Default arm with `throw …` is the drop-target shape.
      for c in cases {
        match c.test_expr {
          None =>
            if c.body.stmts.length() == 1 {
              match c.body.stmts[0] {
                Throw(_) => return true
                _ => ()
              }
            }
          Some(te) => if expr_needs_type_fold(te) { return true }
        }
        if block_needs_type_fold(c.body) {
          return true
        }
      }
      false
    }
    Try(b, _, cb, fb) => {
      if block_needs_type_fold(b) {
        return true
      }
      let cb_b = match cb {
        Some(blk) => block_needs_type_fold(blk)
        None => false
      }
      if cb_b {
        return true
      }
      match fb {
        Some(blk) => block_needs_type_fold(blk)
        None => false
      }
    }
    Label(_, inner) => stmt_needs_type_fold(inner)
    Block(b) => block_needs_type_fold(b)
    NativeClassStmt(decl, ctor_body) => {
      match decl.base_expr {
        Some(b) => if expr_needs_type_fold(b) { return true }
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => if block_needs_type_fold(b) { return true }
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        if expr_needs_type_fold(sf.1) {
          return true
        }
      }
      match ctor_body {
        Some(f) => block_needs_type_fold(f.body)
        None => false
      }
    }
  }
}

///|
fn expr_needs_type_fold(expr : @ast.TsExpr) -> Bool {
  match expr {
    // `typeof x === "lit"` — discriminant we can fold.
    BinOp(op, l, r) => {
      let is_eq_op = match op {
        BinEq | BinNe | AbstractEq | AbstractNe => true
        _ => false
      }
      if is_eq_op {
        match (l, r) {
          (
            @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Typeof, _),
            @ast.TsExpr::StringLit(_),
          )
          | (
            @ast.TsExpr::StringLit(_),
            @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Typeof, _),
          ) => return true
          // `x === null` / `x === undefined`.
          (@ast.TsExpr::Var(_), @ast.TsExpr::NullLit)
          | (@ast.TsExpr::NullLit, @ast.TsExpr::Var(_)) => return true
          (@ast.TsExpr::Var(_), @ast.TsExpr::Var("undefined"))
          | (@ast.TsExpr::Var("undefined"), @ast.TsExpr::Var(_)) => return true
          _ => ()
        }
      }
      // `x + ""` / `"" + x` — foldable when x is string-typed.
      match (op, l, r) {
        (Add, @ast.TsExpr::Var(_), @ast.TsExpr::StringLit(""))
        | (Add, @ast.TsExpr::StringLit(""), @ast.TsExpr::Var(_)) => return true
        _ => ()
      }
      expr_needs_type_fold(l) || expr_needs_type_fold(r)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner)
    | YieldStar(inner) => expr_needs_type_fold(inner)
    Cond(c, t, e) =>
      expr_needs_type_fold(c) ||
      expr_needs_type_fold(t) ||
      expr_needs_type_fold(e)
    Seq(l, r) => expr_needs_type_fold(l) || expr_needs_type_fold(r)
    PropAccess(recv, _) => expr_needs_type_fold(recv)
    IndexAccess(recv, idx) =>
      expr_needs_type_fold(recv) || expr_needs_type_fold(idx)
    Call(_, args) | New(_, args) => {
      for a in args {
        if expr_needs_type_fold(a) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if expr_needs_type_fold(callee) {
        return true
      }
      for a in args {
        if expr_needs_type_fold(a) {
          return true
        }
      }
      false
    }
    MethodCall(recv, _, args) => {
      if expr_needs_type_fold(recv) {
        return true
      }
      for a in args {
        if expr_needs_type_fold(a) {
          return true
        }
      }
      false
    }
    ArrayLit(items) => {
      for i in items {
        if expr_needs_type_fold(i) {
          return true
        }
      }
      false
    }
    ObjectLit(entries) => {
      for ent in entries {
        if expr_needs_type_fold(ent.1) {
          return true
        }
      }
      false
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => expr_needs_type_fold(e)
        ArrowBlock(b) => block_needs_type_fold(b)
      }
    FuncExpr(f) => block_needs_type_fold(f.body)
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      expr_needs_type_fold(v)
    CompoundAssignExpr(t, _, v) =>
      expr_needs_type_fold(t) || expr_needs_type_fold(v)
    IndexAssignExpr(recv, idx, v) =>
      expr_needs_type_fold(recv) ||
      expr_needs_type_fold(idx) ||
      expr_needs_type_fold(v)
    ComputedProp(k, v) => expr_needs_type_fold(k) || expr_needs_type_fold(v)
    As(inner, _) | Satisfies(inner, _) => expr_needs_type_fold(inner)
    Yield(Some(inner)) => expr_needs_type_fold(inner)
    TaggedTemplate(tag, _, _, exprs) => {
      if expr_needs_type_fold(tag) {
        return true
      }
      for e in exprs {
        if expr_needs_type_fold(e) {
          return true
        }
      }
      false
    }
    TemplateLiteral(_, exprs) => {
      for e in exprs {
        if expr_needs_type_fold(e) {
          return true
        }
      }
      false
    }
    DynamicImport(spec, opts) => {
      if expr_needs_type_fold(spec) {
        return true
      }
      match opts {
        Some(o) => expr_needs_type_fold(o)
        None => false
      }
    }
    _ => false
  }
}

///|
fn type_fold_block_in(
  block : @ast.TsBlock,
  scope : TypeScope,
  aliases : Map[String, @ast.TsType],
) -> @ast.TsBlock {
  // Each block introduces a fresh layer over the parent, so writes
  // inside it don't pollute siblings.
  let local_ = scope.child()
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(type_fold_stmt(s, local_, aliases))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn type_fold_stmt(
  stmt : @ast.TsStmt,
  scope : TypeScope,
  aliases : Map[String, @ast.TsType],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) | Let(b, t, e) | Const(b, t, e) => {
      let new_init = type_fold_expr(e, scope, aliases)
      // Record the binding's type if it's a simple identifier
      // and the annotation is one we can reason about.
      // When there's no annotation (Any), infer from the RHS literal.
      match b {
        @ast.TsBinding::Ident(name) => {
          let effective_type = if is_useful_type(t) {
            t
          } else {
            infer_type_from_literal(new_init)
          }
          match effective_type {
            // No useful type for this binding — but it IS a binding,
            // so the name must read as unknown from here on rather
            // than falling through to whatever an OUTER binding of the
            // same name was annotated as. `hide` is what the parameter
            // path already does (see `TypeScope`'s comment); the
            // declaration path let the outer type stay visible, so
            //
            //     function f(s: string) {
            //       { const s = 5 as unknown; return typeof s === "string"; }
            //     }
            //
            // folded to `!0` on the strength of the PARAMETER's type.
            // A wrong value, not a crash.
            @ast.TsType::Any => scope.hide(name)
            ty => scope.set(name, ty)
          }
        }
        _ => ()
      }
      match stmt {
        Var(_, _, _) => Var(b, t, new_init)
        Let(_, _, _) => Let(b, t, new_init)
        Const(_, _, _) => Const(b, t, new_init)
        _ => stmt
      }
    }
    Assign(n, e) => Assign(n, type_fold_expr(e, scope, aliases))
    CompoundAssign(n, op, e) =>
      CompoundAssign(n, op, type_fold_expr(e, scope, aliases))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        type_fold_expr(t, scope, aliases),
        type_fold_expr(idx, scope, aliases),
        type_fold_expr(v, scope, aliases),
      )
    PropAssign(t, p, v) =>
      PropAssign(
        type_fold_expr(t, scope, aliases),
        p,
        type_fold_expr(v, scope, aliases),
      )
    Expr(e) => Expr(type_fold_expr(e, scope, aliases))
    Return(Some(e)) => Return(Some(type_fold_expr(e, scope, aliases)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(type_fold_expr(e, scope, aliases))
    If(c, t, e) =>
      If(
        type_fold_expr(c, scope, aliases),
        type_fold_block_in(t, scope, aliases),
        match e {
          Some(b) => Some(type_fold_block_in(b, scope, aliases))
          None => None
        },
      )
    While(c, body) =>
      While(
        type_fold_expr(c, scope, aliases),
        type_fold_block_in(body, scope, aliases),
      )
    DoWhile(c, body) =>
      DoWhile(
        type_fold_expr(c, scope, aliases),
        type_fold_block_in(body, scope, aliases),
      )
    With(c, body) =>
      With(
        type_fold_expr(c, scope, aliases),
        type_fold_block_in(body, scope, aliases),
      )
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(type_fold_stmt(s, scope, aliases))
          None => None
        },
        match cond {
          Some(e) => Some(type_fold_expr(e, scope, aliases))
          None => None
        },
        match update {
          Some(s) => Some(type_fold_stmt(s, scope, aliases))
          None => None
        },
        type_fold_block_in(body, scope, aliases),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        b,
        t,
        type_fold_expr(iter, scope, aliases),
        type_fold_block_in(body, scope, aliases),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        type_fold_expr(iter, scope, aliases),
        type_fold_block_in(body, scope, aliases),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        type_fold_expr(iter, scope, aliases),
        type_fold_block_in(body, scope, aliases),
      )
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(type_fold_expr(te, scope, aliases))
            None => None
          },
          body: type_fold_block_in(c.body, scope, aliases),
        })
      }
      let folded_e = type_fold_expr(e, scope, aliases)
      // Exhaustive-default drop: when the discriminant's static
      // type is a closed string-literal union, every literal is
      // covered by a `case`, and the `default:` body is the
      // unreachable-assertion shape (`[Throw(...)]`), the default
      // can be dropped — TS guarantees it never fires.
      let pruned_cases = drop_exhaustive_default(
        folded_e, new_cases, scope, aliases,
      )
      Switch(folded_e, pruned_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        type_fold_block_in(b, scope, aliases),
        bnd,
        match cb {
          Some(blk) => Some(type_fold_block_in(blk, scope, aliases))
          None => None
        },
        match fb {
          Some(blk) => Some(type_fold_block_in(blk, scope, aliases))
          None => None
        },
      )
    Label(name, inner) => Label(name, type_fold_stmt(inner, scope, aliases))
    Block(b) => Block(type_fold_block_in(b, scope, aliases))
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) =>
          Some({ ..f, body: type_fold_block_in(f.body, scope, aliases) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(type_fold_block_in(b, scope, aliases))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, type_fold_expr(sf.1, scope, aliases)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(type_fold_expr(b, scope, aliases))
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
fn type_fold_expr(
  expr : @ast.TsExpr,
  scope : TypeScope,
  aliases : Map[String, @ast.TsType],
) -> @ast.TsExpr {
  match expr {
    // typeof X === "literal" / typeof X !== "literal"
    BinOp(op, UnaryOp(Typeof, Var(x_name)), StringLit(ty_lit)) =>
      match try_typeof_fold(op, x_name, ty_lit, scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    BinOp(op, StringLit(ty_lit), UnaryOp(Typeof, Var(x_name))) =>
      match try_typeof_fold(op, x_name, ty_lit, scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    // x === null / x !== null / x === undefined / x !== undefined
    BinOp(op, Var(x_name), NullLit) =>
      match try_null_check_fold(op, x_name, "null", scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    BinOp(op, NullLit, Var(x_name)) =>
      match try_null_check_fold(op, x_name, "null", scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    BinOp(op, Var(x_name), Var("undefined")) =>
      match try_null_check_fold(op, x_name, "undefined", scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    BinOp(op, Var("undefined"), Var(x_name)) =>
      match try_null_check_fold(op, x_name, "undefined", scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    // `x + ""` → `x` when x is statically typed as string (saves 4 bytes).
    // `"" + x` → `x` similarly. Both are no-op string concatenations.
    BinOp(@ast.TsBinOp::Add, Var(x_name), StringLit("")) =>
      match scope.get(x_name) {
        Some(ty) if typeof_of_type(ty) == Some("string") => Var(x_name)
        _ => BinOp(@ast.TsBinOp::Add, Var(x_name), StringLit(""))
      }
    BinOp(@ast.TsBinOp::Add, StringLit(""), Var(x_name)) =>
      match scope.get(x_name) {
        Some(ty) if typeof_of_type(ty) == Some("string") => Var(x_name)
        _ => BinOp(@ast.TsBinOp::Add, StringLit(""), Var(x_name))
      }
    BinOp(op, l, r) =>
      BinOp(
        op,
        type_fold_expr(l, scope, aliases),
        type_fold_expr(r, scope, aliases),
      )
    UnaryOp(op, inner) => UnaryOp(op, type_fold_expr(inner, scope, aliases))
    Cond(c, t, e) =>
      Cond(
        type_fold_expr(c, scope, aliases),
        type_fold_expr(t, scope, aliases),
        type_fold_expr(e, scope, aliases),
      )
    Call(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(type_fold_expr(a, scope, aliases))
      }
      Call(n, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(type_fold_expr(a, scope, aliases))
      }
      CallExpr(type_fold_expr(callee, scope, aliases), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(type_fold_expr(a, scope, aliases))
      }
      MethodCall(type_fold_expr(recv, scope, aliases), m, new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(type_fold_expr(a, scope, aliases))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(type_fold_expr(a, scope, aliases))
      }
      NewExpr(type_fold_expr(callee, scope, aliases), new_args)
    }
    PropAccess(recv, p) => PropAccess(type_fold_expr(recv, scope, aliases), p)
    IndexAccess(recv, idx) =>
      IndexAccess(
        type_fold_expr(recv, scope, aliases),
        type_fold_expr(idx, scope, aliases),
      )
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(type_fold_expr(i, scope, aliases))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, type_fold_expr(ent.1, scope, aliases)))
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(type_fold_expr(inner, scope, aliases))
    Yield(Some(inner)) => Yield(Some(type_fold_expr(inner, scope, aliases)))
    YieldStar(inner) => YieldStar(type_fold_expr(inner, scope, aliases))
    Await(inner) => Await(type_fold_expr(inner, scope, aliases))
    Seq(a, b) =>
      Seq(type_fold_expr(a, scope, aliases), type_fold_expr(b, scope, aliases))
    AssignExpr(n, v) => AssignExpr(n, type_fold_expr(v, scope, aliases))
    AssignPattern(b, v) => AssignPattern(b, type_fold_expr(v, scope, aliases))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(
        type_fold_expr(recv, scope, aliases),
        p,
        type_fold_expr(v, scope, aliases),
      )
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        type_fold_expr(recv, scope, aliases),
        type_fold_expr(idx, scope, aliases),
        type_fold_expr(v, scope, aliases),
      )
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        type_fold_expr(t, scope, aliases),
        op,
        type_fold_expr(v, scope, aliases),
      )
    ComputedProp(k, v) =>
      ComputedProp(
        type_fold_expr(k, scope, aliases),
        type_fold_expr(v, scope, aliases),
      )
    ArrowFunc(params, ret, body, is_async) => {
      let local_ = scope.child()
      for p in params {
        // Parameters always shadow outer bindings with the same name.
        // Remove any outer type first so the outer type is not used
        // inside the function body when the param has no annotation.
        local_.hide(p.name)
        if is_useful_type(p.type_) {
          local_.set(p.name, p.type_)
        }
      }
      let new_body = match body {
        ArrowExpr(e) =>
          @ast.TsArrowBody::ArrowExpr(type_fold_expr(e, local_, aliases))
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(type_fold_block_in(b, local_, aliases))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let local_ = scope.child()
      for p in f.params {
        // Parameters always shadow outer bindings with the same name.
        // Remove any outer type first so the outer type is not used
        // inside the function body when the param has no annotation.
        local_.hide(p.name)
        if is_useful_type(p.type_) {
          local_.set(p.name, p.type_)
        }
      }
      FuncExpr({ ..f, body: type_fold_block_in(f.body, local_, aliases) })
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(type_fold_expr(o, scope, aliases))
        None => None
      }
      DynamicImport(type_fold_expr(spec, scope, aliases), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(type_fold_expr(e, scope, aliases))
      }
      TaggedTemplate(
        type_fold_expr(tag, scope, aliases),
        raw,
        cooked,
        new_exprs,
      )
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(type_fold_expr(e, scope, aliases))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(type_fold_expr(inner, scope, aliases), ty)
    Satisfies(inner, ty) => Satisfies(type_fold_expr(inner, scope, aliases), ty)
    NonNull(inner) => NonNull(type_fold_expr(inner, scope, aliases))
    TypeArgs(tys, inner) => TypeArgs(tys, type_fold_expr(inner, scope, aliases))
    OptionalChain(inner) => OptionalChain(type_fold_expr(inner, scope, aliases))
    PureCall(inner) => PureCall(type_fold_expr(inner, scope, aliases))
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) =>
          Some({ ..f, body: type_fold_block_in(f.body, scope, aliases) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(type_fold_block_in(b, scope, aliases))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, type_fold_expr(sf.1, scope, aliases)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(type_fold_expr(b, scope, aliases))
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
/// `is_useful_type` is the gate: we only record types we know
/// how to reason about. `Any`, generic refs, unions, and
/// complex shapes don't tell us a primitive `typeof`, so we
/// skip them.
fn is_useful_type(ty : @ast.TsType) -> Bool {
  match ty {
    Number | Int | String_ | Boolean | BigInt | Symbol => true
    Undefined | Void => true
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) => true
    // Closed string-literal unions feed `drop_exhaustive_default`.
    Union(parts) => {
      if parts.length() == 0 {
        return false
      }
      for p in parts {
        match p {
          Literal(_) => ()
          _ => return false
        }
      }
      true
    }
    // Object / Struct / Named shapes power the PropAccess
    // discriminant path in `drop_exhaustive_default`. Func /
    // Constructor / Array / Tuple / Null also flow into
    // `typeof_of_type` so `typeof callback === "function"` /
    // `typeof arr === "object"` fold against typed bindings.
    // The non-typeof foldings (null-check, `+ ""`, etc.) check
    // specific primitive shapes and bail on these structurally.
    Object(_)
    | Struct(_, _)
    | Named(_)
    | Func(_, _)
    | Constructor(_, _, _)
    | Array(_)
    | Tuple(_)
    | Null => true
    _ => false
  }
}

///|
/// Infer a primitive TsType from an RHS expression.
/// Returns `Any` when the type can't be determined statically.
fn infer_type_from_literal(expr : @ast.TsExpr) -> @ast.TsType {
  match expr {
    IntLit(_) | NumberLit(_) => @ast.TsType::Number
    StringLit(_) => @ast.TsType::String_
    BoolLit(_) => @ast.TsType::Boolean
    BigIntLit(_) => @ast.TsType::BigInt
    // `typeof x` always produces a string.
    UnaryOp(@ast.TsUnaryOp::Typeof, _) => @ast.TsType::String_
    // `.length` on arrays/strings is always a number.
    PropAccess(_, "length") => @ast.TsType::Number
    // `.indexOf(...)` / `.lastIndexOf(...)` / `.findIndex(...)` always return number.
    MethodCall(_, "indexOf", _)
    | MethodCall(_, "lastIndexOf", _)
    | MethodCall(_, "findIndex", _)
    | MethodCall(_, "search", _) => @ast.TsType::Number
    // `.toString()` / `.toUpperCase()` etc. always return string.
    MethodCall(_, "toString", _)
    | MethodCall(_, "toUpperCase", _)
    | MethodCall(_, "toLowerCase", _)
    | MethodCall(_, "trim", _)
    | MethodCall(_, "trimStart", _)
    | MethodCall(_, "trimEnd", _)
    | MethodCall(_, "slice", _)
    | MethodCall(_, "substring", _)
    | MethodCall(_, "replace", _)
    | MethodCall(_, "replaceAll", _) => @ast.TsType::String_
    // Arithmetic operators on two numbers yield number.
    BinOp(@ast.TsBinOp::Add, l, r)
    | BinOp(@ast.TsBinOp::Sub, l, r)
    | BinOp(@ast.TsBinOp::Mul, l, r)
    | BinOp(@ast.TsBinOp::Div, l, r)
    | BinOp(@ast.TsBinOp::Mod, l, r) =>
      match (infer_type_from_literal(l), infer_type_from_literal(r)) {
        (@ast.TsType::Number, @ast.TsType::Number) => @ast.TsType::Number
        _ => @ast.TsType::Any
      }
    _ => @ast.TsType::Any
  }
}

///|
/// Map a primitive type to its `typeof` JavaScript string.
fn typeof_of_type(ty : @ast.TsType) -> String? {
  match ty {
    Number | Int | NumberLiteral(_) => Some("number")
    String_ | Literal(_) => Some("string")
    Boolean | BooleanLiteral(_) => Some("boolean")
    BigInt | BigIntLiteral(_) => Some("bigint")
    Symbol => Some("symbol")
    // `typeof undefined` is "undefined" at runtime.
    Undefined | Void => Some("undefined")
    // Plain object shapes are uniformly "object" at runtime. A
    // `Func` would be "function" but we don't see those as
    // value-side annotations here.
    Object(_) | Struct(_, _) => Some("object")
    Func(_, _) | Constructor(_, _, _) => Some("function")
    // `null` is special: `typeof null === "object"` (the original
    // JS bug we honour). `Array` is `"object"` too.
    Null => Some("object")
    Array(_) | Tuple(_) => Some("object")
    _ => None
  }
}

///|
/// Fold `typeof x op "lit"` when x's static type lets us decide
/// the comparison. Returns `Some(b)` for the folded literal,
/// `None` to leave the expression untouched.
fn try_typeof_fold(
  op : @ast.TsBinOp,
  x_name : String,
  lit : String,
  scope : TypeScope,
) -> Bool? {
  let ty = match scope.get(x_name) {
    Some(t) => t
    None => return None
  }
  let actual = match typeof_of_type(ty) {
    Some(s) => s
    None => return None
  }
  let equal = actual == lit
  match op {
    BinEq | AbstractEq => Some(equal)
    BinNe | AbstractNe => Some(!equal)
    _ => None
  }
}

///|
/// Drop the trailing `default:` arm of a `switch` when the
/// discriminant's static type is a closed string-literal union,
/// every literal is covered by a `case`, and the default body is
/// the unreachable-assertion shape (`[Throw(...)]`).
fn drop_exhaustive_default(
  disc : @ast.TsExpr,
  cases : Array[@ast.TsSwitchCase],
  scope : TypeScope,
  aliases : Map[String, @ast.TsType],
) -> Array[@ast.TsSwitchCase] {
  if cases.length() == 0 {
    return cases
  }
  // Default must be the final arm to be a safe drop.
  let last = cases[cases.length() - 1]
  let default_block = match last.test_expr {
    None => last.body
    Some(_) => return cases
  }
  // Default body must be a single `throw <expr>;` to keep this
  // safe — any other statement could carry observable behavior
  // we can't preserve.
  if default_block.stmts.length() != 1 {
    return cases
  }
  match default_block.stmts[0] {
    Throw(_) => ()
    _ => return cases
  }
  // Discriminant types we can decide on:
  //   - `Var(name)` with name carrying a literal-string union
  //     annotation (the original "tag variable" case).
  //   - `PropAccess(Var(name), field)` where name's annotation is
  //     a discriminated union and `field` is the tag — the new
  //     checker's `simplify_indexed_access` distributes over the
  //     union to produce the exact literal set after resolving the
  //     binding's `Named` annotation through the alias table.
  let raw_ty = match disc {
    Var(n) =>
      match scope.get(n) {
        Some(t) => resolve_alias(t, aliases)
        None => return cases
      }
    PropAccess(Var(n), field) =>
      match scope.get(n) {
        Some(t) => {
          let resolved = resolve_alias(t, aliases)
          @checker.simplify_type(
            @ast.TsType::IndexedAccess(resolved, Literal(field)),
          )
        }
        None => return cases
      }
    _ => return cases
  }
  let literals = match raw_ty {
    Literal(s) => [s]
    Union(parts) => {
      let out : Array[String] = []
      for p in parts {
        match p {
          Literal(s) => out.push(s)
          _ => return cases
        }
      }
      out
    }
    _ => return cases
  }
  // Every literal in the union must be matched by a case.
  let covered : Map[String, Bool] = {}
  for c in cases {
    match c.test_expr {
      Some(@ast.TsExpr::StringLit(s)) => covered[s] = true
      _ => ()
    }
  }
  for l in literals {
    if !covered.contains(l) {
      return cases
    }
  }
  // All literals covered — drop the default.
  let pruned : Array[@ast.TsSwitchCase] = []
  for i in 0..<(cases.length() - 1) {
    pruned.push(cases[i])
  }
  pruned
}

///|
/// Fold `x op null` / `x op undefined` for non-nullable
/// primitive types. (`number` can't be `null`, etc.)
fn try_null_check_fold(
  op : @ast.TsBinOp,
  x_name : String,
  rhs_kind : String,
  scope : TypeScope,
) -> Bool? {
  let ty = match scope.get(x_name) {
    Some(t) => t
    None => return None
  }
  // `x: undefined` — x IS undefined; null-check folds with exact semantics.
  // `x === undefined` → true; `x !== undefined` → false.
  // `x === null` → false (undefined !== null under strict equality).
  // `x !== null` → true.
  match ty {
    Undefined | Void => {
      let is_equal = rhs_kind == "undefined"
      return match op {
        BinEq | AbstractEq => Some(is_equal)
        BinNe | AbstractNe => Some(!is_equal)
        _ => None
      }
    }
    _ => ()
  }
  // The types we cleared in `is_useful_type` are all non-
  // nullable primitives — a `: number` parameter / binding
  // can't be `null` or `undefined` in a well-typed program.
  let can_be_null = match ty {
    Number | Int | String_ | Boolean | BigInt | Symbol => false
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) =>
      false
    _ => return None
  }
  // `x === null` for non-nullable x → false; `x !== null` → true.
  let _ = can_be_null
  match op {
    BinEq | AbstractEq => Some(false)
    BinNe | AbstractNe => Some(true)
    _ => None
  }
}
