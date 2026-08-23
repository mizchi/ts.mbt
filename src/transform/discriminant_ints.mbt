// Discriminant string literals to integers.
//
//   type Shape =
//     | { kind: "circle"; r: number }
//     | { kind: "square"; s: number };
//
//   function area(x: Shape) {
//     switch (x.kind) {
//       case "circle": return x.r * x.r * 3;
//       case "square": return x.s * x.s;
//     }
//   }
//
// `"circle"` is eight bytes every time it appears; `0` is one. Property
// mangling can't touch it — it renames keys, not values — so the tag
// strings survive minification untouched even though nothing outside the
// bundle ever sees them.
//
// The proof is about the property's VALUE, not its name, and that is a
// different question from the one the observability lattice answers (it
// is per-binding: "can anything observe this value's property names?").
// Two conditions together settle it without needing a finer lattice:
//
//   1. The name is not in the escape set. That covers every way the
//      whole object can leave — serialization, enumeration, an `in`
//      probe, a foreign call, the export surface — because any of those
//      reserves the name.
//   2. Every direct read of the property is an equality comparison or a
//      `switch` discriminant against a literal from the same closed set.
//      That covers the remaining path: a read whose VALUE escapes while
//      the NAME doesn't (`return shape.kind` out of an exported
//      function).
//
// Plus the obvious third: every write of the property is a plain string
// literal, so the closed set is actually closed.
//
// A read in any other position — a template literal, an argument, a
// truthiness test (`if (shape.kind)`, where `"circle"` is truthy and `0`
// is not) — blocks the name outright.

///|
/// Per-property numbering: property name -> (string literal -> integer).
pub(all) struct DiscriminantPlan {
  maps : Map[String, Map[String, Int]]
}

///|
priv struct DiscScan {
  // Literal values written to each name, in first-seen order.
  writes : Map[String, Array[String]]
  // Literals the name is compared against.
  compared : Map[String, Array[String]]
  // Names disqualified outright: a non-literal write, or a read in a
  // position that isn't a literal comparison.
  blocked : Map[String, Bool]
  // Names that have at least one approved read, so a candidate with
  // writes but no reads at all isn't renumbered for nothing.
  read_count : Map[String, Int]
}

///|
fn disc_note_write(scan : DiscScan, name : String, value : @ast.TsExpr) -> Unit {
  match value {
    @ast.TsExpr::StringLit(s) =>
      match scan.writes.get(name) {
        Some(arr) => if !arr.contains(s) { arr.push(s) }
        None => scan.writes[name] = [s]
      }
    _ => scan.blocked[name] = true
  }
}

///|
fn disc_note_compared(scan : DiscScan, name : String, lit : String) -> Unit {
  match scan.compared.get(name) {
    Some(arr) => if !arr.contains(lit) { arr.push(lit) }
    None => scan.compared[name] = [lit]
  }
  scan.read_count[name] = scan.read_count.get(name).unwrap_or(0) + 1
}

///|
/// Work out which property names can have their tag strings renumbered.
///
/// `reserved` is the escape analysis's output — the names something
/// outside the bundle can see. A wildcard entry disables the pass
/// entirely, exactly as it disables property mangling.
pub fn plan_discriminant_ints(
  block : @ast.TsBlock,
  reserved : Map[String, Bool],
  declines? : Array[String] = [],
) -> DiscriminantPlan {
  if reserved.contains("*") {
    declines.push(
      "every tag: the escape analysis reserved the wildcard, which suppresses this pass along with property mangling",
    )
    return { maps: {} }
  }
  let scan : DiscScan = {
    writes: {},
    compared: {},
    blocked: {},
    read_count: {},
  }
  disc_scan_block(scan, block)
  let maps : Map[String, Map[String, Int]] = {}
  for entry in scan.writes {
    let (name, literals) = entry
    if scan.blocked.contains(name) {
      declines.push(
        "`" +
        name +
        "`: read somewhere other than an equality comparison or a `switch` discriminant — interpolated, passed on, compared relationally, or used for truthiness (a tag string is truthy and 0 is not) — or written with something other than a plain string literal",
      )
      continue
    }
    if reserved.contains(name) {
      declines.push(
        "`" +
        name +
        "`: the name is in the escape set, so the whole object can be seen from outside (serialized, enumerated, probed, handed to a foreign callee, or exported)",
      )
      continue
    }
    if is_internal_marker_prop(name) {
      continue
    }
    // Nobody reads it — nothing to gain, and `dead_props` is the pass
    // that should be dealing with it.
    if scan.read_count.get(name).unwrap_or(0) == 0 {
      declines.push(
        "`" +
        name +
        "`: written but never read — a matter for the dead-property pass",
      )
      continue
    }
    // Every literal the code compares against has to be one the code can
    // actually write. A comparison against an outsider is always false
    // today, and renumbering would have to invent a number to keep it
    // false — simpler to decline.
    let mut closed = true
    match scan.compared.get(name) {
      Some(cmps) =>
        for c in cmps {
          if !literals.contains(c) {
            closed = false
          }
        }
      None => ()
    }
    if !closed {
      declines.push(
        "`" +
        name +
        "`: compared against a literal the code never writes, so that comparison is always false and renumbering would have to invent a value to keep it false",
      )
      continue
    }
    let numbering : Map[String, Int] = {}
    for i, lit in literals {
      numbering[lit] = i
    }
    maps[name] = numbering
  }
  { maps, }
}

///|
/// Renumber the planned tag strings.
pub fn apply_discriminant_ints(
  block : @ast.TsBlock,
  plan : DiscriminantPlan,
) -> @ast.TsBlock {
  if plan.maps.is_empty() {
    return block
  }
  disc_rewrite_block(block, plan)
}

// ---------------------------------------------------------------------------
// Analysis walk
// ---------------------------------------------------------------------------
//
// The walk is parent-aware on purpose. A `PropAccess(_, k)` reached the
// ordinary way is a bare read and blocks `k`; the two approved shapes
// (an equality comparison, a `switch` discriminant) recognise the access
// from above and descend into its RECEIVER instead, so the access is
// never counted as bare.

///|
fn disc_scan_block(scan : DiscScan, block : @ast.TsBlock) -> Unit {
  for s in block.stmts {
    disc_scan_stmt(scan, s)
  }
}

///|
fn is_equality_op(op : @ast.TsBinOp) -> Bool {
  // `==` behaves the same as `===` here: both operands become numbers
  // together, and the compared literal is required to be one of the
  // written ones, so every comparison keeps its result.
  op is (BinEq | BinNe | AbstractEq | AbstractNe)
}

///|
/// A `switch` whose discriminant is `x.k` and whose every case tests a
/// string literal. Returns the property name.
fn disc_switch_name(
  discriminant : @ast.TsExpr,
  cases : Array[@ast.TsSwitchCase],
) -> String? {
  let name = match discriminant {
    @ast.TsExpr::PropAccess(_, k) => k
    _ => return None
  }
  for c in cases {
    match c.test_expr {
      // `default` carries no test.
      None => ()
      Some(@ast.TsExpr::StringLit(_)) => ()
      Some(_) => return None
    }
  }
  Some(name)
}

///|
fn disc_scan_stmt(scan : DiscScan, stmt : @ast.TsStmt) -> Unit {
  match stmt {
    PropAssign(target, name, value) => {
      disc_note_write(scan, name, value)
      disc_scan_expr(scan, target)
      disc_scan_expr(scan, value)
    }
    Switch(discriminant, cases) => {
      match disc_switch_name(discriminant, cases) {
        Some(name) => {
          for c in cases {
            match c.test_expr {
              Some(@ast.TsExpr::StringLit(s)) =>
                disc_note_compared(scan, name, s)
              _ => ()
            }
          }
          // Descend into the receiver, not the access itself.
          match discriminant {
            @ast.TsExpr::PropAccess(recv, _) => disc_scan_expr(scan, recv)
            _ => ()
          }
        }
        None => disc_scan_expr(scan, discriminant)
      }
      for c in cases {
        disc_scan_block(scan, c.body)
      }
    }
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) => disc_scan_expr(scan, e)
    Assign(_, e) | CompoundAssign(_, _, e) | Expr(e) | Throw(e) =>
      disc_scan_expr(scan, e)
    Return(Some(e)) => disc_scan_expr(scan, e)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => ()
    IndexAssign(a, b, c) => {
      disc_scan_expr(scan, a)
      disc_scan_expr(scan, b)
      disc_scan_expr(scan, c)
    }
    If(c, t, e) => {
      disc_scan_expr(scan, c)
      disc_scan_block(scan, t)
      match e {
        Some(b) => disc_scan_block(scan, b)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      disc_scan_expr(scan, c)
      disc_scan_block(scan, b)
    }
    For(init, cond, upd, b) => {
      match init {
        Some(s) => disc_scan_stmt(scan, s)
        None => ()
      }
      match cond {
        Some(e) => disc_scan_expr(scan, e)
        None => ()
      }
      match upd {
        Some(s) => disc_scan_stmt(scan, s)
        None => ()
      }
      disc_scan_block(scan, b)
    }
    ForOf(_, _, _, iter, b)
    | ForAwaitOf(_, _, _, iter, b)
    | ForIn(_, _, _, iter, b) => {
      disc_scan_expr(scan, iter)
      disc_scan_block(scan, b)
    }
    Try(b, _, c, f) => {
      disc_scan_block(scan, b)
      match c {
        Some(cb) => disc_scan_block(scan, cb)
        None => ()
      }
      match f {
        Some(fb) => disc_scan_block(scan, fb)
        None => ()
      }
    }
    Label(_, inner) => disc_scan_stmt(scan, inner)
    Block(b) => disc_scan_block(scan, b)
    NativeClassStmt(decl, ctor) => {
      match decl.base_expr {
        Some(b) => disc_scan_expr(scan, b)
        None => ()
      }
      match ctor {
        Some(f) => disc_scan_block(scan, f.body)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => disc_scan_block(scan, b)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        disc_scan_expr(scan, sf.1)
      }
    }
  }
}

///|
fn disc_scan_expr(scan : DiscScan, expr : @ast.TsExpr) -> Unit {
  match expr {
    // The approved read: `x.k === "lit"` in either order.
    BinOp(op, @ast.TsExpr::PropAccess(recv, k), @ast.TsExpr::StringLit(s)) =>
      if is_equality_op(op) {
        disc_note_compared(scan, k, s)
        disc_scan_expr(scan, recv)
      } else {
        scan.blocked[k] = true
        disc_scan_expr(scan, recv)
      }
    BinOp(op, @ast.TsExpr::StringLit(s), @ast.TsExpr::PropAccess(recv, k)) =>
      if is_equality_op(op) {
        disc_note_compared(scan, k, s)
        disc_scan_expr(scan, recv)
      } else {
        scan.blocked[k] = true
        disc_scan_expr(scan, recv)
      }
    // Any other read of a property is a use we can't account for.
    PropAccess(recv, k) => {
      scan.blocked[k] = true
      disc_scan_expr(scan, recv)
    }
    ObjectLit(entries) =>
      for ent in entries {
        if !is_opaque_object_key(ent.0) {
          disc_note_write(scan, ent.0, ent.1)
        }
        disc_scan_expr(scan, ent.1)
      }
    PropAssignExpr(target, name, value) => {
      disc_note_write(scan, name, value)
      disc_scan_expr(scan, target)
      disc_scan_expr(scan, value)
    }
    // `obj["k"]` is a read the plan can't see through consistently, so
    // treat the literal key as blocked.
    IndexAccess(recv, idx) => {
      match idx {
        @ast.TsExpr::StringLit(k) => scan.blocked[k] = true
        _ => ()
      }
      disc_scan_expr(scan, recv)
      disc_scan_expr(scan, idx)
    }
    IndexAssignExpr(target, idx, value) => {
      match idx {
        @ast.TsExpr::StringLit(k) => scan.blocked[k] = true
        _ => ()
      }
      disc_scan_expr(scan, target)
      disc_scan_expr(scan, idx)
      disc_scan_expr(scan, value)
    }
    MethodCall(recv, m, args) => {
      // A method call is a read of `m`.
      scan.blocked[m] = true
      disc_scan_expr(scan, recv)
      for a in args {
        disc_scan_expr(scan, a)
      }
    }
    BinOp(_, a, b) | Seq(a, b) | ComputedProp(a, b) => {
      disc_scan_expr(scan, a)
      disc_scan_expr(scan, b)
    }
    UnaryOp(_, i)
    | Spread(i)
    | Await(i)
    | YieldStar(i)
    | As(i, _)
    | Satisfies(i, _)
    | NonNull(i)
    | OptionalChain(i)
    | PureCall(i)
    | TypeArgs(_, i) => disc_scan_expr(scan, i)
    Yield(Some(i)) => disc_scan_expr(scan, i)
    Cond(c, t, e) => {
      disc_scan_expr(scan, c)
      disc_scan_expr(scan, t)
      disc_scan_expr(scan, e)
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        disc_scan_expr(scan, a)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      disc_scan_expr(scan, callee)
      for a in args {
        disc_scan_expr(scan, a)
      }
    }
    ArrayLit(items) =>
      for i in items {
        disc_scan_expr(scan, i)
      }
    AssignExpr(_, v) | AssignPattern(_, v) => disc_scan_expr(scan, v)
    CompoundAssignExpr(t, _, v) => {
      disc_scan_expr(scan, t)
      disc_scan_expr(scan, v)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => disc_scan_expr(scan, e)
        ArrowBlock(b) => disc_scan_block(scan, b)
      }
    FuncExpr(f) => disc_scan_block(scan, f.body)
    NativeClassExpr(decl, ctor) => {
      match ctor {
        Some(f) => disc_scan_block(scan, f.body)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => disc_scan_block(scan, b)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        disc_scan_expr(scan, sf.1)
      }
    }
    DynamicImport(spec, opts) => {
      disc_scan_expr(scan, spec)
      match opts {
        Some(o) => disc_scan_expr(scan, o)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      disc_scan_expr(scan, tag)
      for e in exprs {
        disc_scan_expr(scan, e)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        disc_scan_expr(scan, e)
      }
    JsxElement(_, attrs, children) => {
      for a in attrs {
        match a.1 {
          Some(v) => disc_scan_expr(scan, v)
          None => ()
        }
      }
      for c in children {
        disc_scan_expr(scan, c)
      }
    }
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// Rewrite
// ---------------------------------------------------------------------------

///|
fn disc_number(
  plan : DiscriminantPlan,
  name : String,
  lit : String,
) -> @ast.TsExpr? {
  match plan.maps.get(name) {
    Some(numbering) =>
      match numbering.get(lit) {
        Some(n) => Some(@ast.TsExpr::IntLit(n))
        None => None
      }
    None => None
  }
}

///|
fn disc_rewrite_block(
  block : @ast.TsBlock,
  plan : DiscriminantPlan,
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(disc_rewrite_stmt(s, plan))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn disc_rewrite_stmt(
  stmt : @ast.TsStmt,
  plan : DiscriminantPlan,
) -> @ast.TsStmt {
  match stmt {
    PropAssign(target, name, @ast.TsExpr::StringLit(s)) =>
      match disc_number(plan, name, s) {
        Some(n) => PropAssign(disc_rewrite_expr(target, plan), name, n)
        None =>
          PropAssign(
            disc_rewrite_expr(target, plan),
            name,
            @ast.TsExpr::StringLit(s),
          )
      }
    PropAssign(target, name, value) =>
      PropAssign(
        disc_rewrite_expr(target, plan),
        name,
        disc_rewrite_expr(value, plan),
      )
    Switch(discriminant, cases) => {
      let name = disc_switch_name(discriminant, cases)
      let out : Array[@ast.TsSwitchCase] = []
      for c in cases {
        let new_test = match (name, c.test_expr) {
          (Some(k), Some(@ast.TsExpr::StringLit(s))) =>
            match disc_number(plan, k, s) {
              Some(n) => Some(n)
              None => c.test_expr
            }
          _ =>
            match c.test_expr {
              Some(e) => Some(disc_rewrite_expr(e, plan))
              None => None
            }
        }
        out.push({
          ..c,
          test_expr: new_test,
          body: disc_rewrite_block(c.body, plan),
        })
      }
      Switch(disc_rewrite_expr(discriminant, plan), out)
    }
    Var(b, t, e) => Var(b, t, disc_rewrite_expr(e, plan))
    Let(b, t, e) => Let(b, t, disc_rewrite_expr(e, plan))
    Const(b, t, e) => Const(b, t, disc_rewrite_expr(e, plan))
    Assign(n, e) => Assign(n, disc_rewrite_expr(e, plan))
    CompoundAssign(n, op, e) =>
      CompoundAssign(n, op, disc_rewrite_expr(e, plan))
    Expr(e) => Expr(disc_rewrite_expr(e, plan))
    Throw(e) => Throw(disc_rewrite_expr(e, plan))
    Return(Some(e)) => Return(Some(disc_rewrite_expr(e, plan)))
    IndexAssign(a, b, c) =>
      IndexAssign(
        disc_rewrite_expr(a, plan),
        disc_rewrite_expr(b, plan),
        disc_rewrite_expr(c, plan),
      )
    If(c, t, e) =>
      If(
        disc_rewrite_expr(c, plan),
        disc_rewrite_block(t, plan),
        match e {
          Some(b) => Some(disc_rewrite_block(b, plan))
          None => None
        },
      )
    While(c, b) =>
      While(disc_rewrite_expr(c, plan), disc_rewrite_block(b, plan))
    DoWhile(c, b) =>
      DoWhile(disc_rewrite_expr(c, plan), disc_rewrite_block(b, plan))
    With(c, b) => With(disc_rewrite_expr(c, plan), disc_rewrite_block(b, plan))
    For(init, cond, upd, b) =>
      For(
        match init {
          Some(s) => Some(disc_rewrite_stmt(s, plan))
          None => None
        },
        match cond {
          Some(e) => Some(disc_rewrite_expr(e, plan))
          None => None
        },
        match upd {
          Some(s) => Some(disc_rewrite_stmt(s, plan))
          None => None
        },
        disc_rewrite_block(b, plan),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        b,
        t,
        disc_rewrite_expr(iter, plan),
        disc_rewrite_block(body, plan),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        disc_rewrite_expr(iter, plan),
        disc_rewrite_block(body, plan),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        disc_rewrite_expr(iter, plan),
        disc_rewrite_block(body, plan),
      )
    Try(b, bind, c, f) =>
      Try(
        disc_rewrite_block(b, plan),
        bind,
        match c {
          Some(cb) => Some(disc_rewrite_block(cb, plan))
          None => None
        },
        match f {
          Some(fb) => Some(disc_rewrite_block(fb, plan))
          None => None
        },
      )
    Label(l, inner) => Label(l, disc_rewrite_stmt(inner, plan))
    Block(b) => Block(disc_rewrite_block(b, plan))
    NativeClassStmt(decl, ctor) => {
      let methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        methods.push({
          ..m,
          body: match m.body {
            Some(b) => Some(disc_rewrite_block(b, plan))
            None => None
          },
        })
      }
      let statics : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        statics.push((sf.0, disc_rewrite_expr(sf.1, plan)))
      }
      NativeClassStmt(
        { ..decl, methods, static_field_inits: statics },
        match ctor {
          Some(f) => Some({ ..f, body: disc_rewrite_block(f.body, plan) })
          None => None
        },
      )
    }
    _ => stmt
  }
}

///|
fn disc_rewrite_expr(
  expr : @ast.TsExpr,
  plan : DiscriminantPlan,
) -> @ast.TsExpr {
  match expr {
    BinOp(op, @ast.TsExpr::PropAccess(recv, k), @ast.TsExpr::StringLit(s)) =>
      if is_equality_op(op) && disc_number(plan, k, s) is Some(n) {
        BinOp(op, PropAccess(disc_rewrite_expr(recv, plan), k), n)
      } else {
        BinOp(
          op,
          PropAccess(disc_rewrite_expr(recv, plan), k),
          @ast.TsExpr::StringLit(s),
        )
      }
    BinOp(op, @ast.TsExpr::StringLit(s), @ast.TsExpr::PropAccess(recv, k)) =>
      if is_equality_op(op) && disc_number(plan, k, s) is Some(n) {
        BinOp(op, n, PropAccess(disc_rewrite_expr(recv, plan), k))
      } else {
        BinOp(
          op,
          @ast.TsExpr::StringLit(s),
          PropAccess(disc_rewrite_expr(recv, plan), k),
        )
      }
    ObjectLit(entries) => {
      let out : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        let value = match ent.1 {
          @ast.TsExpr::StringLit(s) =>
            match disc_number(plan, ent.0, s) {
              Some(n) => n
              None => @ast.TsExpr::StringLit(s)
            }
          other => disc_rewrite_expr(other, plan)
        }
        out.push((ent.0, value))
      }
      ObjectLit(out)
    }
    PropAssignExpr(target, name, @ast.TsExpr::StringLit(s)) =>
      match disc_number(plan, name, s) {
        Some(n) => PropAssignExpr(disc_rewrite_expr(target, plan), name, n)
        None =>
          PropAssignExpr(
            disc_rewrite_expr(target, plan),
            name,
            @ast.TsExpr::StringLit(s),
          )
      }
    BinOp(op, a, b) =>
      BinOp(op, disc_rewrite_expr(a, plan), disc_rewrite_expr(b, plan))
    Seq(a, b) => Seq(disc_rewrite_expr(a, plan), disc_rewrite_expr(b, plan))
    ComputedProp(a, b) =>
      ComputedProp(disc_rewrite_expr(a, plan), disc_rewrite_expr(b, plan))
    UnaryOp(op, i) => UnaryOp(op, disc_rewrite_expr(i, plan))
    Spread(i) => Spread(disc_rewrite_expr(i, plan))
    Await(i) => Await(disc_rewrite_expr(i, plan))
    YieldStar(i) => YieldStar(disc_rewrite_expr(i, plan))
    Yield(Some(i)) => Yield(Some(disc_rewrite_expr(i, plan)))
    As(i, t) => As(disc_rewrite_expr(i, plan), t)
    Satisfies(i, t) => Satisfies(disc_rewrite_expr(i, plan), t)
    NonNull(i) => NonNull(disc_rewrite_expr(i, plan))
    OptionalChain(i) => OptionalChain(disc_rewrite_expr(i, plan))
    PureCall(i) => PureCall(disc_rewrite_expr(i, plan))
    TypeArgs(t, i) => TypeArgs(t, disc_rewrite_expr(i, plan))
    Cond(c, t, e) =>
      Cond(
        disc_rewrite_expr(c, plan),
        disc_rewrite_expr(t, plan),
        disc_rewrite_expr(e, plan),
      )
    PropAccess(recv, k) => PropAccess(disc_rewrite_expr(recv, plan), k)
    IndexAccess(recv, idx) =>
      IndexAccess(disc_rewrite_expr(recv, plan), disc_rewrite_expr(idx, plan))
    MethodCall(recv, m, args) => {
      let out : Array[@ast.TsExpr] = []
      for a in args {
        out.push(disc_rewrite_expr(a, plan))
      }
      MethodCall(disc_rewrite_expr(recv, plan), m, out)
    }
    Call(n, args) => {
      let out : Array[@ast.TsExpr] = []
      for a in args {
        out.push(disc_rewrite_expr(a, plan))
      }
      Call(n, out)
    }
    New(n, args) => {
      let out : Array[@ast.TsExpr] = []
      for a in args {
        out.push(disc_rewrite_expr(a, plan))
      }
      New(n, out)
    }
    CallExpr(callee, args) => {
      let out : Array[@ast.TsExpr] = []
      for a in args {
        out.push(disc_rewrite_expr(a, plan))
      }
      CallExpr(disc_rewrite_expr(callee, plan), out)
    }
    NewExpr(callee, args) => {
      let out : Array[@ast.TsExpr] = []
      for a in args {
        out.push(disc_rewrite_expr(a, plan))
      }
      NewExpr(disc_rewrite_expr(callee, plan), out)
    }
    ArrayLit(items) => {
      let out : Array[@ast.TsExpr] = []
      for i in items {
        out.push(disc_rewrite_expr(i, plan))
      }
      ArrayLit(out)
    }
    AssignExpr(n, v) => AssignExpr(n, disc_rewrite_expr(v, plan))
    AssignPattern(b, v) => AssignPattern(b, disc_rewrite_expr(v, plan))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        disc_rewrite_expr(t, plan),
        op,
        disc_rewrite_expr(v, plan),
      )
    IndexAssignExpr(t, idx, v) =>
      IndexAssignExpr(
        disc_rewrite_expr(t, plan),
        disc_rewrite_expr(idx, plan),
        disc_rewrite_expr(v, plan),
      )
    ArrowFunc(params, ret, body, is_async) =>
      ArrowFunc(
        params,
        ret,
        match body {
          ArrowExpr(e) => ArrowExpr(disc_rewrite_expr(e, plan))
          ArrowBlock(b) => ArrowBlock(disc_rewrite_block(b, plan))
        },
        is_async,
      )
    FuncExpr(f) => FuncExpr({ ..f, body: disc_rewrite_block(f.body, plan) })
    NativeClassExpr(decl, ctor) => {
      let methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        methods.push({
          ..m,
          body: match m.body {
            Some(b) => Some(disc_rewrite_block(b, plan))
            None => None
          },
        })
      }
      NativeClassExpr(
        { ..decl, methods, },
        match ctor {
          Some(f) => Some({ ..f, body: disc_rewrite_block(f.body, plan) })
          None => None
        },
      )
    }
    TemplateLiteral(parts, exprs) => {
      let out : Array[@ast.TsExpr] = []
      for e in exprs {
        out.push(disc_rewrite_expr(e, plan))
      }
      TemplateLiteral(parts, out)
    }
    _ => expr
  }
}
