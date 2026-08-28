// Scalar-`const` propagation — terser's `reduce_vars`, for the case
// that is only about primitives.
//
//   const K = 5;
//   export function f() { return K * 2; }
//   // ->
//   export function f() { return 10; }
//
// The declaration then has no readers and treeshake takes it. The
// substitution itself is close to free — the mangler would have called
// `K` something one byte long — so the win is the declaration
// disappearing PLUS whatever `fold` can now do with a literal in place
// of a name. In the example above that is the whole of it: `K * 2` is
// not foldable and `5 * 2` is.
//
// Why this is a separate pass from `as_const_inline.mbt` when it shares
// that file's walker:
//
//   * The shapes are different (a scalar has no members to read) and so
//     is the disqualification rule. `as_const_inline` disqualifies a
//     candidate the moment it sees a bare `Var(NAME)`, because for an
//     array or object that is the identity escaping. For a scalar a
//     bare read is exactly what we came to rewrite.
//   * `--phases` prices each phase by switching it off, and folding two
//     rules into one phase makes that number uninterpretable.
//
// What it shares is the part that had a bug: the walker's scope
// narrowing. See the top of `call_inline.mbt`.
//
// One accepted behaviour change, the same one terser accepts: a read
// that runs BEFORE the declaration is initialised throws (`const` has a
// temporal dead zone), and after substitution it produces the value
// instead. Reaching that requires calling a function before its own
// module's top-level consts are evaluated, which is already broken code.

///|
/// Printed length of a literal in minify mode, used to price the
/// substitution. Only the shapes `scalar_inline_value` admits appear
/// here; anything else returns a length that fails every budget.
fn scalar_literal_bytes(e : @ast.TsExpr) -> Int {
  match e {
    // `true` / `false` emit as `!0` / `!1`.
    BoolLit(_) => 2
    NullLit => 4
    IntLit(n) => n.to_string().length()
    NumberLit(n) => {
      let s = n.to_string()
      // MoonBit prints `5` as `5.0`; the emitter does not.
      if s.has_suffix(".0") {
        s.length() - 2
      } else {
        s.length()
      }
    }
    StringLit(s) => s.length() + 2
    BigIntLit(s) => s.length() + 1
    _ => 1000
  }
}

///|
/// The literal a scalar candidate stands for, or `None` when the
/// initializer is not one.
fn scalar_inline_value(e : @ast.TsExpr) -> @ast.TsExpr? {
  // `as const` leaves no wrapper, but a plain `as T` does.
  let inner = match e {
    As(x, _) | Satisfies(x, _) | TypeArgs(_, x) => x
    _ => e
  }
  match inner {
    StringLit(_)
    | NumberLit(_)
    | IntLit(_)
    | BoolLit(_)
    | NullLit
    | BigIntLit(_) => Some(inner)
    _ => None
  }
}

///|
/// Is substituting worth it?
///
/// The comparison is against the name AFTER mangling, which is where
/// the bytes are actually decided and which is one character for
/// anything this pass sees on a real bundle. So each site costs
/// `bytes - 1`, and deleting `const a=<lit>,` saves about `4 + bytes`.
/// Assuming one character is the conservative direction: a longer name
/// only makes substituting better.
///
/// This deliberately prices the substitution alone and claims nothing
/// about what `fold` will do with it — an unpriced upside, not a
/// justification for a bigger budget.
fn scalar_inline_pays(bytes : Int, refs : Int) -> Bool {
  if refs == 0 {
    return false
  }
  refs * (bytes - 1) <= 4 + bytes
}

///|
/// Names this block writes to, anywhere at any depth. A `const` cannot
/// be assigned in valid TypeScript, so this is a backstop rather than a
/// rule — but the pass replaces reads with a fixed value, and one write
/// it did not see would make every one of them wrong.
fn scalar_assigned_names(block : @ast.TsBlock, out : Map[String, Bool]) -> Unit {
  for s in block.stmts {
    scalar_assigned_in_stmt(s, out)
  }
}

///|
fn scalar_assigned_in_stmt(stmt : @ast.TsStmt, out : Map[String, Bool]) -> Unit {
  match stmt {
    Assign(n, _) | CompoundAssign(n, _, _) => out[n] = true
    _ => ()
  }
  // Nested statements are reached through the generic walker below;
  // this arm only has to catch the statement-level assignment forms,
  // which the expression walker cannot see.
  match stmt {
    If(_, t, e) => {
      scalar_assigned_names(t, out)
      match e {
        Some(b) => scalar_assigned_names(b, out)
        None => ()
      }
    }
    While(_, b) | DoWhile(_, b) | With(_, b) | Block(b) =>
      scalar_assigned_names(b, out)
    For(init, _, update, b) => {
      match init {
        Some(s) => scalar_assigned_in_stmt(s, out)
        None => ()
      }
      match update {
        Some(s) => scalar_assigned_in_stmt(s, out)
        None => ()
      }
      scalar_assigned_names(b, out)
    }
    ForOf(_, _, _, _, b) | ForAwaitOf(_, _, _, _, b) | ForIn(_, _, _, _, b) =>
      scalar_assigned_names(b, out)
    Switch(_, cases) =>
      for c in cases {
        scalar_assigned_names(c.body, out)
      }
    Try(b, _, cb, fb) => {
      scalar_assigned_names(b, out)
      match cb {
        Some(x) => scalar_assigned_names(x, out)
        None => ()
      }
      match fb {
        Some(x) => scalar_assigned_names(x, out)
        None => ()
      }
    }
    Label(_, inner) => scalar_assigned_in_stmt(inner, out)
    NativeClassStmt(decl, ctor) => {
      match ctor {
        Some(f) => scalar_assigned_names(f.body, out)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => scalar_assigned_names(b, out)
          None => ()
        }
      }
    }
    _ => ()
  }
}

///|
/// Propagate top-level scalar `const` bindings to their read sites.
pub fn const_scalar_inline_block(block : @ast.TsBlock) -> @ast.TsBlock {
  let values : Map[String, @ast.TsExpr] = {}
  let bytes : Map[String, Int] = {}
  for stmt in block.stmts {
    match stmt {
      Const(@ast.TsBinding::Ident(name), _, e) =>
        match scalar_inline_value(e) {
          Some(lit) => {
            values[name] = lit
            bytes[name] = scalar_literal_bytes(lit)
          }
          None => ()
        }
      _ => ()
    }
  }
  if values.is_empty() {
    return block
  }
  // Reads, and writes that rule a candidate out.
  let refs : Map[String, Int] = {}
  surface_visit_exprs_block(block, e => {
    match e {
      Var(n) => if values.contains(n) { refs[n] = refs.get(n).unwrap_or(0) + 1 }
      // `Call(n, args)` names its callee without a `Var` node. A scalar
      // is not callable, so this is dead code in a correct program — but
      // it is also the difference between "no references" and "one
      // reference we cannot see", and the pass must not read the first
      // when the second is true.
      Call(n, _) =>
        if values.contains(n) {
          refs[n] = refs.get(n).unwrap_or(0) + 1
        }
      AssignExpr(n, _) => if values.contains(n) { values.remove(n) }
      _ => ()
    }
  })
  let assigned : Map[String, Bool] = {}
  scalar_assigned_names(block, assigned)
  let chosen : Map[String, @ast.TsExpr] = {}
  for name, lit in values {
    if assigned.contains(name) {
      continue
    }
    if scalar_inline_pays(
        bytes.get(name).unwrap_or(1000),
        refs.get(name).unwrap_or(0),
      ) {
      chosen[name] = lit
    }
  }
  if chosen.is_empty() {
    return block
  }
  // The declaration's own initializer is a literal, so rewriting it is
  // a no-op; the top-level statements are walked directly (not through
  // `rewrite_block`) because narrowing by the top-level block's own
  // bindings would drop every candidate.
  let tables : AsConstTables = { shapes: Map::new(), scalars: chosen }
  let out : Array[@ast.TsStmt] = []
  for s in block.stmts {
    out.push(rewrite_stmt(s, tables))
  }
  { stmts: out, stmt_positions: block.stmt_positions }
}
