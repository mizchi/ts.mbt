// Discriminant-tag string → number rewrite (whole-program).
//
// When a closed discriminated-union type alias has every variant
// tag as a string literal, and the bundle uses the discriminant
// property ONLY in `switch` heads and equality comparisons, the
// string-typed tag can be replaced by a small integer:
//
//   type Shape = { kind: "circle", r: number }
//              | { kind: "square", side: number };
//
//   const s: Shape = { kind: "circle", r: 3 };
//   switch (s.kind) {
//     case "circle": return Math.PI * s.r ** 2;
//     case "square": return s.side ** 2;
//   }
//
// becomes
//
//   const s = { kind: 0, r: 3 };
//   switch (s.kind) {
//     case 0: return Math.PI * s.r ** 2;
//     case 1: return s.side ** 2;
//   }
//
// Wins: small-integer comparison fast-paths, smaller output.
//
// Safety (whole-program). The rewrite is gated on the bundle
// containing NONE of these escape sinks anywhere — any of them
// could observe the original string value at runtime:
//
//   * `JSON.stringify` / `JSON.parse` (any args)
//   * `console.<anything>(...)` (any args)
//   * `fetch(...)` (any args)
//   * `Object.keys` / `entries` / `values` / `assign` / `fromEntries`
//   * Spread (`...x`)
//   * `for-in` loops
//   * Template literals with any interpolation
//
// Per-property safety: every `PropAccess(_, K)` /
// `IndexAccess(_, StringLit(K))` must appear in one of these
// safe positions:
//
//   * Discriminant of a `switch (e.K)` head, and every case in
//     that switch must be a `StringLit` in the union's literal
//     set (or `default:`).
//   * Either side of `BinOp(BinEq | BinNe | AbstractEq |
//     AbstractNe, ..., StringLit)` where the other side's literal
//     is in the union's set.
//
// Per-K object-literal safety: every `ObjectLit` whose keys
// include `K` must give it a `StringLit` value that's in the
// union's set. (Otherwise we don't know what shape the literal
// belongs to.)
//
// When all three gates clear, the rewrite is performed in a
// single pass: each literal in the union's set gets a stable
// non-negative integer; `{ K: "lit", ... }` → `{ K: <id>, ... }`;
// `case "lit":` → `case <id>:`; and `e.K === "lit"` →
// `e.K === <id>` (similar for `!==` / `==` / `!=`).

///|
pub fn tag_rewrite_block(
  block : @ast.TsBlock,
  type_aliases : Array[@ast.TsTypeAlias],
) -> @ast.TsBlock {
  // 1. Gather discriminant property names + literal sets from
  //    closed string-literal Object-unions.
  let unions = collect_discriminated_unions(type_aliases)
  if unions.is_empty() {
    return block
  }
  // 2. Bundle-wide escape sink scan. If ANY are present, no
  //    rewrite is safe — bail.
  if block_has_escape_sink(block) {
    return block
  }
  // 3. For each candidate K, verify:
  //    - every PropAccess(_, K) / IndexAccess(_, StringLit(K))
  //      is in a safe position
  //    - every ObjectLit with key K has a StringLit value in L
  let candidates : Map[String, Map[String, Int]] = {}
  for entry in unions {
    let (k, literals) = entry
    if not(check_prop_uses_safe(block, k, literals)) {
      continue
    }
    if not(check_object_literals_safe(block, k, literals)) {
      continue
    }
    let id_map : Map[String, Int] = {}
    for i in 0..<literals.length() {
      id_map[literals[i]] = i
    }
    candidates[k] = id_map
  }
  if candidates.is_empty() {
    return block
  }
  // 4. Rewrite phase.
  let new_stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    new_stmts.push(tag_rewrite_stmt(s, candidates))
  }
  { stmts: new_stmts, stmt_positions: [] }
}

// -- Step 1: discover discriminated unions ----------------------------

///|
/// Returns a deduplicated list of `(K, ordered_literals)` pairs.
/// `K` is the common literal-property name; `ordered_literals` is
/// the union of every literal value seen across variants (insertion
/// order kept so integer IDs stay stable across runs).
fn collect_discriminated_unions(
  type_aliases : Array[@ast.TsTypeAlias],
) -> Map[String, Array[String]] {
  let out : Map[String, Array[String]] = {}
  for ta in type_aliases {
    match ta.type_ {
      Union(parts) => {
        if parts.length() < 2 {
          continue
        }
        // Find a common literal-string property across every part.
        let common = find_common_string_discriminant(parts)
        match common {
          Some((k, literals)) => {
            let existing = out.get(k).or([])
            let seen : Map[String, Bool] = {}
            for s in existing {
              seen[s] = true
            }
            for s in literals {
              if not(seen.contains(s)) {
                seen[s] = true
                existing.push(s)
              }
            }
            out[k] = existing
          }
          None => ()
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// Given the variant list of a `Union`, returns `(K, literals)`
/// when there exists a property name `K` whose value in every
/// variant is `Literal(string)`. `literals` is ordered by variant
/// (one entry per variant).
fn find_common_string_discriminant(
  parts : Array[@ast.TsType],
) -> (String, Array[String])? {
  // Each part must be an `Object(fields)` carrying at least one
  // field whose value is `Literal(string)`. Build the set of
  // candidate field names from the first part, then intersect with
  // every subsequent part.
  let first_fields = match object_string_literal_fields(parts[0]) {
    Some(m) => m
    None => return None
  }
  let mut candidate_keys : Map[String, Bool] = {}
  for entry in first_fields {
    candidate_keys[entry.0] = true
  }
  let per_part : Array[Map[String, String]] = [first_fields]
  for i in 1..<parts.length() {
    let m = match object_string_literal_fields(parts[i]) {
      Some(m) => m
      None => return None
    }
    let next_keys : Map[String, Bool] = {}
    for entry in m {
      if candidate_keys.contains(entry.0) {
        next_keys[entry.0] = true
      }
    }
    candidate_keys = next_keys
    per_part.push(m)
    if candidate_keys.is_empty() {
      return None
    }
  }
  // Pick the first remaining candidate key (typically `kind` /
  // `type` / `tag` etc.). If multiple are eligible we just pick
  // one — the rewrite always touches the chosen property name
  // independently of others.
  let k = match candidate_keys.keys().to_array().get(0) {
    Some(s) => s
    None => return None
  }
  // Collect the literal value at `k` for each variant.
  let literals : Array[String] = []
  let seen : Map[String, Bool] = {}
  for fields in per_part {
    match fields.get(k) {
      Some(lit) =>
        if not(seen.contains(lit)) {
          seen[lit] = true
          literals.push(lit)
        }
      None => return None
    }
  }
  Some((k, literals))
}

///|
/// If `ty` is `Object(fields)`, returns the subset of fields
/// whose key is `Literal(name)` and value is `Literal(s)` — i.e.
/// the candidate discriminant properties. Returns `None` for any
/// non-`Object` type.
fn object_string_literal_fields(ty : @ast.TsType) -> Map[String, String]? {
  match ty {
    Object(fields) => {
      let out : Map[String, String] = {}
      for f in fields {
        let key = match f.0 {
          Literal(s) => s
          _ => continue
        }
        let val = match f.1 {
          Literal(s) => s
          _ => continue
        }
        out[key] = val
      }
      Some(out)
    }
    _ => None
  }
}

// -- Step 2: bundle-wide escape sink scan -----------------------------

///|
/// Names whose use ANYWHERE in the bundle aborts the rewrite —
/// any of them could observe a discriminant tag as a string at
/// runtime.
let serializing_method_names : Array[String] = [
  "stringify", "parse", "log", "info", "warn", "error", "debug", "trace",
  "keys", "values", "entries", "assign", "fromEntries",
]

///|
let serializing_callable_names : Array[String] = ["fetch"]

///|
fn block_has_escape_sink(block : @ast.TsBlock) -> Bool {
  for s in block.stmts {
    if stmt_has_escape_sink(s) {
      return true
    }
  }
  false
}

///|
fn stmt_has_escape_sink(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Assign(_, e)
    | CompoundAssign(_, _, e) | Throw(e) => expr_has_escape_sink(e)
    Return(Some(e)) => expr_has_escape_sink(e)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => false
    IndexAssign(t, idx, v) =>
      expr_has_escape_sink(t) ||
          expr_has_escape_sink(idx) ||
          expr_has_escape_sink(v)
    PropAssign(t, _, v) =>
      expr_has_escape_sink(t) || expr_has_escape_sink(v)
    If(c, t, e) => {
      if expr_has_escape_sink(c) {
        return true
      }
      if block_has_escape_sink(t) {
        return true
      }
      match e {
        Some(b) => block_has_escape_sink(b)
        None => false
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) =>
      expr_has_escape_sink(c) || block_has_escape_sink(body)
    For(init, cond, update, body) => {
      let init_bad = match init {
        Some(s) => stmt_has_escape_sink(s)
        None => false
      }
      if init_bad {
        return true
      }
      let cond_bad = match cond {
        Some(e) => expr_has_escape_sink(e)
        None => false
      }
      if cond_bad {
        return true
      }
      let upd_bad = match update {
        Some(s) => stmt_has_escape_sink(s)
        None => false
      }
      if upd_bad {
        return true
      }
      block_has_escape_sink(body)
    }
    // `for-in` is itself a sink (reflects all keys).
    ForIn(_, _, _, _, _) => true
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body) =>
      expr_has_escape_sink(iter) || block_has_escape_sink(body)
    Switch(e, cases) => {
      if expr_has_escape_sink(e) {
        return true
      }
      for c in cases {
        match c.test_expr {
          Some(te) =>
            if expr_has_escape_sink(te) {
              return true
            }
          None => ()
        }
        if block_has_escape_sink(c.body) {
          return true
        }
      }
      false
    }
    Try(b, _, cb, fb) => {
      if block_has_escape_sink(b) {
        return true
      }
      let cb_bad = match cb {
        Some(blk) => block_has_escape_sink(blk)
        None => false
      }
      if cb_bad {
        return true
      }
      match fb {
        Some(blk) => block_has_escape_sink(blk)
        None => false
      }
    }
    Label(_, inner) => stmt_has_escape_sink(inner)
    Block(b) => block_has_escape_sink(b)
    NativeClassStmt(_, _) => false
  }
}

///|
fn expr_has_escape_sink(expr : @ast.TsExpr) -> Bool {
  match expr {
    // `JSON.foo(...)` / `console.foo(...)` / `Object.foo(...)`.
    MethodCall(@ast.TsExpr::Var(recv), m, args) => {
      let recv_is_dangerous = recv == "JSON" ||
            recv == "console" ||
            recv == "Object"
      if recv_is_dangerous && serializing_method_names.contains(m) {
        return true
      }
      for a in args {
        if expr_has_escape_sink(a) {
          return true
        }
      }
      false
    }
    Call(name, args) => {
      if serializing_callable_names.contains(name) {
        return true
      }
      for a in args {
        if expr_has_escape_sink(a) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) => {
      if expr_has_escape_sink(callee) {
        return true
      }
      for a in args {
        if expr_has_escape_sink(a) {
          return true
        }
      }
      false
    }
    MethodCall(recv, _, args) => {
      if expr_has_escape_sink(recv) {
        return true
      }
      for a in args {
        if expr_has_escape_sink(a) {
          return true
        }
      }
      false
    }
    New(_, args) | NewExpr(_, args) => {
      for a in args {
        if expr_has_escape_sink(a) {
          return true
        }
      }
      false
    }
    Spread(_) => true
    TemplateLiteral(_, exprs) => {
      // Template literal with interpolation might serialize a tag.
      if exprs.length() > 0 {
        return true
      }
      false
    }
    TaggedTemplate(_, _, _, _) => true
    BinOp(_, l, r) | Seq(l, r) =>
      expr_has_escape_sink(l) || expr_has_escape_sink(r)
    UnaryOp(_, inner) | Await(inner) | NonNull(inner)
    | OptionalChain(inner) | PureCall(inner) | YieldStar(inner) =>
      expr_has_escape_sink(inner)
    Cond(c, t, e) =>
      expr_has_escape_sink(c) ||
          expr_has_escape_sink(t) ||
          expr_has_escape_sink(e)
    PropAccess(recv, _) => expr_has_escape_sink(recv)
    IndexAccess(recv, idx) =>
      expr_has_escape_sink(recv) || expr_has_escape_sink(idx)
    ArrayLit(items) => {
      for i in items {
        if expr_has_escape_sink(i) {
          return true
        }
      }
      false
    }
    ObjectLit(entries) => {
      for ent in entries {
        if expr_has_escape_sink(ent.1) {
          return true
        }
      }
      false
    }
    ComputedProp(k, v) =>
      expr_has_escape_sink(k) || expr_has_escape_sink(v)
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      expr_has_escape_sink(v)
    CompoundAssignExpr(t, _, v) =>
      expr_has_escape_sink(t) || expr_has_escape_sink(v)
    IndexAssignExpr(recv, idx, v) =>
      expr_has_escape_sink(recv) ||
          expr_has_escape_sink(idx) ||
          expr_has_escape_sink(v)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => expr_has_escape_sink(e)
        ArrowBlock(b) => block_has_escape_sink(b)
      }
    FuncExpr(f) => block_has_escape_sink(f.body)
    DynamicImport(spec, opts) => {
      if expr_has_escape_sink(spec) {
        return true
      }
      match opts {
        Some(o) => expr_has_escape_sink(o)
        None => false
      }
    }
    Yield(Some(inner)) => expr_has_escape_sink(inner)
    _ => false
  }
}

// -- Step 3: per-K property-read and object-literal safety ------------

///|
/// Walk the block. Every `PropAccess(_, K)` and
/// `IndexAccess(_, StringLit(K))` must appear in a safe context.
fn check_prop_uses_safe(
  block : @ast.TsBlock,
  k : String,
  literals : Array[String],
) -> Bool {
  let lit_set : Map[String, Bool] = {}
  for s in literals {
    lit_set[s] = true
  }
  for s in block.stmts {
    if not(prop_uses_safe_stmt(s, k, lit_set, false)) {
      return false
    }
  }
  true
}

///|
fn prop_uses_safe_stmt(
  stmt : @ast.TsStmt,
  k : String,
  lits : Map[String, Bool],
  in_safe_pos : Bool,
) -> Bool {
  let _ = in_safe_pos
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Assign(_, e)
    | CompoundAssign(_, _, e) | Throw(e) => prop_uses_safe_expr(e, k, lits, false)
    Return(Some(e)) => prop_uses_safe_expr(e, k, lits, false)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => true
    IndexAssign(t, idx, v) =>
      prop_uses_safe_expr(t, k, lits, false) &&
         prop_uses_safe_expr(idx, k, lits, false) &&
         prop_uses_safe_expr(v, k, lits, false)
    PropAssign(t, _, v) =>
      prop_uses_safe_expr(t, k, lits, false) &&
         prop_uses_safe_expr(v, k, lits, false)
    If(c, t, e) => {
      if not(prop_uses_safe_expr(c, k, lits, false)) {
        return false
      }
      for s in t.stmts {
        if not(prop_uses_safe_stmt(s, k, lits, false)) {
          return false
        }
      }
      match e {
        Some(b) =>
          for s in b.stmts {
            if not(prop_uses_safe_stmt(s, k, lits, false)) {
              return false
            }
          }
        None => ()
      }
      true
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      if not(prop_uses_safe_expr(c, k, lits, false)) {
        return false
      }
      for s in body.stmts {
        if not(prop_uses_safe_stmt(s, k, lits, false)) {
          return false
        }
      }
      true
    }
    For(init, cond, update, body) => {
      let init_ok = match init {
        Some(s) => prop_uses_safe_stmt(s, k, lits, false)
        None => true
      }
      if not(init_ok) {
        return false
      }
      let cond_ok = match cond {
        Some(e) => prop_uses_safe_expr(e, k, lits, false)
        None => true
      }
      if not(cond_ok) {
        return false
      }
      let upd_ok = match update {
        Some(s) => prop_uses_safe_stmt(s, k, lits, false)
        None => true
      }
      if not(upd_ok) {
        return false
      }
      for s in body.stmts {
        if not(prop_uses_safe_stmt(s, k, lits, false)) {
          return false
        }
      }
      true
    }
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body) => {
      if not(prop_uses_safe_expr(iter, k, lits, false)) {
        return false
      }
      for s in body.stmts {
        if not(prop_uses_safe_stmt(s, k, lits, false)) {
          return false
        }
      }
      true
    }
    // for-in is already an escape sink (caught above), but stay safe.
    ForIn(_, _, _, _, _) => false
    Switch(e, cases) => {
      // A `switch (e.K) { ... }` puts `e.K` in a safe position; the
      // case labels must all be `StringLit(in_lits)` or default.
      let disc_is_k = match e {
        PropAccess(_, name) => name == k
        IndexAccess(_, @ast.TsExpr::StringLit(name)) => name == k
        _ => false
      }
      if disc_is_k {
        // The discriminant expression's receiver is checked
        // separately (e.g. `s.kind` -> the receiver `s` shouldn't
        // mention K). For the discriminant itself, K is safe.
        let recv = match e {
          PropAccess(r, _) => r
          IndexAccess(r, _) => r
          _ => return false
        }
        if not(prop_uses_safe_expr(recv, k, lits, false)) {
          return false
        }
        for c in cases {
          match c.test_expr {
            Some(@ast.TsExpr::StringLit(s)) =>
              if not(lits.contains(s)) {
                return false
              }
            // Existing int labels (idempotency) and `default:` arms
            // are also OK.
            Some(@ast.TsExpr::IntLit(_)) | Some(@ast.TsExpr::NumberLit(_)) => ()
            Some(_) => return false
            None => ()
          }
          for s in c.body.stmts {
            if not(prop_uses_safe_stmt(s, k, lits, false)) {
              return false
            }
          }
        }
        return true
      }
      if not(prop_uses_safe_expr(e, k, lits, false)) {
        return false
      }
      for c in cases {
        match c.test_expr {
          Some(te) =>
            if not(prop_uses_safe_expr(te, k, lits, false)) {
              return false
            }
          None => ()
        }
        for s in c.body.stmts {
          if not(prop_uses_safe_stmt(s, k, lits, false)) {
            return false
          }
        }
      }
      true
    }
    Try(b, _, cb, fb) => {
      for s in b.stmts {
        if not(prop_uses_safe_stmt(s, k, lits, false)) {
          return false
        }
      }
      let cb_ok = match cb {
        Some(blk) => {
          for s in blk.stmts {
            if not(prop_uses_safe_stmt(s, k, lits, false)) {
              return false
            }
          }
          true
        }
        None => true
      }
      if not(cb_ok) {
        return false
      }
      match fb {
        Some(blk) => {
          for s in blk.stmts {
            if not(prop_uses_safe_stmt(s, k, lits, false)) {
              return false
            }
          }
          true
        }
        None => true
      }
    }
    Label(_, inner) => prop_uses_safe_stmt(inner, k, lits, false)
    Block(b) =>
      for s in b.stmts {
        if not(prop_uses_safe_stmt(s, k, lits, false)) {
          return false
        }
      } else {
        true
      }
    NativeClassStmt(_, _) => true
  }
}

///|
fn prop_uses_safe_expr(
  expr : @ast.TsExpr,
  k : String,
  lits : Map[String, Bool],
  _in_safe_pos : Bool,
) -> Bool {
  match expr {
    PropAccess(recv, prop) =>
      if prop == k {
        // Bare `e.K` access is unsafe (not in a safe context). Only
        // sites we explicitly cleared in the parent (switch head /
        // comparison) are safe; we get here via fall-through, so
        // this is by definition an unsafe context.
        false
      } else {
        prop_uses_safe_expr(recv, k, lits, false)
      }
    IndexAccess(recv, @ast.TsExpr::StringLit(s)) =>
      if s == k {
        false
      } else {
        prop_uses_safe_expr(recv, k, lits, false)
      }
    IndexAccess(recv, idx) =>
      prop_uses_safe_expr(recv, k, lits, false) &&
         prop_uses_safe_expr(idx, k, lits, false)
    // Equality comparisons: when one side is `e.K` and the other is
    // a string literal in `lits`, the `.K` access is in a safe
    // position. Still walk the receiver (it shouldn't mention K
    // somewhere else).
    BinOp(op, l, r) => {
      let is_eq_op = match op {
        BinEq | BinNe | AbstractEq | AbstractNe => true
        _ => false
      }
      if is_eq_op {
        let pair = classify_eq_operand(l, r, k, lits)
        match pair {
          Some((recv, _)) =>
            // `e.K === "lit"` (or symmetric). Just verify the
            // receiver part has no further K-related issues.
            return prop_uses_safe_expr(recv, k, lits, false)
          None => ()
        }
      }
      prop_uses_safe_expr(l, k, lits, false) &&
         prop_uses_safe_expr(r, k, lits, false)
    }
    Seq(l, r) =>
      prop_uses_safe_expr(l, k, lits, false) &&
         prop_uses_safe_expr(r, k, lits, false)
    UnaryOp(_, inner) | Await(inner) | NonNull(inner)
    | OptionalChain(inner) | PureCall(inner) | YieldStar(inner) =>
      prop_uses_safe_expr(inner, k, lits, false)
    Cond(c, t, e) =>
      prop_uses_safe_expr(c, k, lits, false) &&
         prop_uses_safe_expr(t, k, lits, false) &&
         prop_uses_safe_expr(e, k, lits, false)
    Call(_, args) | New(_, args) => {
      for a in args {
        if not(prop_uses_safe_expr(a, k, lits, false)) {
          return false
        }
      }
      true
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if not(prop_uses_safe_expr(callee, k, lits, false)) {
        return false
      }
      for a in args {
        if not(prop_uses_safe_expr(a, k, lits, false)) {
          return false
        }
      }
      true
    }
    MethodCall(recv, _, args) => {
      if not(prop_uses_safe_expr(recv, k, lits, false)) {
        return false
      }
      for a in args {
        if not(prop_uses_safe_expr(a, k, lits, false)) {
          return false
        }
      }
      true
    }
    ArrayLit(items) => {
      for i in items {
        if not(prop_uses_safe_expr(i, k, lits, false)) {
          return false
        }
      }
      true
    }
    ObjectLit(entries) => {
      for ent in entries {
        if not(prop_uses_safe_expr(ent.1, k, lits, false)) {
          return false
        }
      }
      true
    }
    Spread(_) => false
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      prop_uses_safe_expr(v, k, lits, false)
    CompoundAssignExpr(t, _, v) =>
      prop_uses_safe_expr(t, k, lits, false) &&
         prop_uses_safe_expr(v, k, lits, false)
    IndexAssignExpr(recv, idx, v) =>
      prop_uses_safe_expr(recv, k, lits, false) &&
         prop_uses_safe_expr(idx, k, lits, false) &&
         prop_uses_safe_expr(v, k, lits, false)
    ComputedProp(kx, v) =>
      prop_uses_safe_expr(kx, k, lits, false) &&
         prop_uses_safe_expr(v, k, lits, false)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => prop_uses_safe_expr(e, k, lits, false)
        ArrowBlock(b) => {
          for s in b.stmts {
            if not(prop_uses_safe_stmt(s, k, lits, false)) {
              return false
            }
          }
          true
        }
      }
    FuncExpr(f) =>
      for s in f.body.stmts {
        if not(prop_uses_safe_stmt(s, k, lits, false)) {
          return false
        }
      } else {
        true
      }
    DynamicImport(spec, opts) => {
      if not(prop_uses_safe_expr(spec, k, lits, false)) {
        return false
      }
      match opts {
        Some(o) => prop_uses_safe_expr(o, k, lits, false)
        None => true
      }
    }
    TaggedTemplate(_, _, _, _) => false
    TemplateLiteral(_, _) => true
    As(inner, _) | Satisfies(inner, _) =>
      prop_uses_safe_expr(inner, k, lits, false)
    Yield(Some(inner)) => prop_uses_safe_expr(inner, k, lits, false)
    _ => true
  }
}

///|
/// Returns `Some((receiver, literal))` when `(l, r)` is the pair
/// `(e.K, StringLit(lit))` (or symmetric) with `lit` ∈ `lits`.
fn classify_eq_operand(
  l : @ast.TsExpr,
  r : @ast.TsExpr,
  k : String,
  lits : Map[String, Bool],
) -> (@ast.TsExpr, String)? {
  match (l, r) {
    (@ast.TsExpr::PropAccess(recv, name), @ast.TsExpr::StringLit(s)) =>
      if name == k && lits.contains(s) {
        Some((recv, s))
      } else {
        None
      }
    (@ast.TsExpr::StringLit(s), @ast.TsExpr::PropAccess(recv, name)) =>
      if name == k && lits.contains(s) {
        Some((recv, s))
      } else {
        None
      }
    _ => None
  }
}

///|
fn check_object_literals_safe(
  block : @ast.TsBlock,
  k : String,
  literals : Array[String],
) -> Bool {
  let lit_set : Map[String, Bool] = {}
  for s in literals {
    lit_set[s] = true
  }
  for s in block.stmts {
    if not(object_literals_safe_stmt(s, k, lit_set)) {
      return false
    }
  }
  true
}

///|
fn object_literals_safe_stmt(
  stmt : @ast.TsStmt,
  k : String,
  lits : Map[String, Bool],
) -> Bool {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Assign(_, e)
    | CompoundAssign(_, _, e) | Throw(e) => object_literals_safe_expr(e, k, lits)
    Return(Some(e)) => object_literals_safe_expr(e, k, lits)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => true
    IndexAssign(t, idx, v) =>
      object_literals_safe_expr(t, k, lits) &&
         object_literals_safe_expr(idx, k, lits) &&
         object_literals_safe_expr(v, k, lits)
    PropAssign(t, _, v) =>
      object_literals_safe_expr(t, k, lits) &&
         object_literals_safe_expr(v, k, lits)
    If(c, t, e) => {
      if not(object_literals_safe_expr(c, k, lits)) {
        return false
      }
      for s in t.stmts {
        if not(object_literals_safe_stmt(s, k, lits)) {
          return false
        }
      }
      match e {
        Some(b) =>
          for s in b.stmts {
            if not(object_literals_safe_stmt(s, k, lits)) {
              return false
            }
          }
        None => ()
      }
      true
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      if not(object_literals_safe_expr(c, k, lits)) {
        return false
      }
      for s in body.stmts {
        if not(object_literals_safe_stmt(s, k, lits)) {
          return false
        }
      }
      true
    }
    For(init, cond, update, body) => {
      let init_ok = match init {
        Some(s) => object_literals_safe_stmt(s, k, lits)
        None => true
      }
      if not(init_ok) {
        return false
      }
      let cond_ok = match cond {
        Some(e) => object_literals_safe_expr(e, k, lits)
        None => true
      }
      if not(cond_ok) {
        return false
      }
      let upd_ok = match update {
        Some(s) => object_literals_safe_stmt(s, k, lits)
        None => true
      }
      if not(upd_ok) {
        return false
      }
      for s in body.stmts {
        if not(object_literals_safe_stmt(s, k, lits)) {
          return false
        }
      }
      true
    }
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      if not(object_literals_safe_expr(iter, k, lits)) {
        return false
      }
      for s in body.stmts {
        if not(object_literals_safe_stmt(s, k, lits)) {
          return false
        }
      }
      true
    }
    Switch(e, cases) => {
      if not(object_literals_safe_expr(e, k, lits)) {
        return false
      }
      for c in cases {
        match c.test_expr {
          Some(te) =>
            if not(object_literals_safe_expr(te, k, lits)) {
              return false
            }
          None => ()
        }
        for s in c.body.stmts {
          if not(object_literals_safe_stmt(s, k, lits)) {
            return false
          }
        }
      }
      true
    }
    Try(b, _, cb, fb) => {
      for s in b.stmts {
        if not(object_literals_safe_stmt(s, k, lits)) {
          return false
        }
      }
      let cb_ok = match cb {
        Some(blk) => {
          for s in blk.stmts {
            if not(object_literals_safe_stmt(s, k, lits)) {
              return false
            }
          }
          true
        }
        None => true
      }
      if not(cb_ok) {
        return false
      }
      match fb {
        Some(blk) => {
          for s in blk.stmts {
            if not(object_literals_safe_stmt(s, k, lits)) {
              return false
            }
          }
          true
        }
        None => true
      }
    }
    Label(_, inner) => object_literals_safe_stmt(inner, k, lits)
    Block(b) =>
      for s in b.stmts {
        if not(object_literals_safe_stmt(s, k, lits)) {
          return false
        }
      } else {
        true
      }
    NativeClassStmt(_, _) => true
  }
}

///|
fn object_literals_safe_expr(
  expr : @ast.TsExpr,
  k : String,
  lits : Map[String, Bool],
) -> Bool {
  match expr {
    ObjectLit(entries) => {
      for ent in entries {
        if ent.0 == k {
          // Must be a string literal in the union's set.
          match ent.1 {
            StringLit(s) =>
              if not(lits.contains(s)) {
                return false
              }
            // Existing int form is idempotent.
            IntLit(_) | NumberLit(_) => ()
            _ => return false
          }
        }
        if not(object_literals_safe_expr(ent.1, k, lits)) {
          return false
        }
      }
      true
    }
    BinOp(_, l, r) | Seq(l, r) =>
      object_literals_safe_expr(l, k, lits) &&
         object_literals_safe_expr(r, k, lits)
    UnaryOp(_, inner) | Spread(inner) | Await(inner) | NonNull(inner)
    | OptionalChain(inner) | PureCall(inner) | YieldStar(inner) =>
      object_literals_safe_expr(inner, k, lits)
    Cond(c, t, e) =>
      object_literals_safe_expr(c, k, lits) &&
         object_literals_safe_expr(t, k, lits) &&
         object_literals_safe_expr(e, k, lits)
    PropAccess(recv, _) => object_literals_safe_expr(recv, k, lits)
    IndexAccess(recv, idx) =>
      object_literals_safe_expr(recv, k, lits) &&
         object_literals_safe_expr(idx, k, lits)
    Call(_, args) | New(_, args) => {
      for a in args {
        if not(object_literals_safe_expr(a, k, lits)) {
          return false
        }
      }
      true
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if not(object_literals_safe_expr(callee, k, lits)) {
        return false
      }
      for a in args {
        if not(object_literals_safe_expr(a, k, lits)) {
          return false
        }
      }
      true
    }
    MethodCall(recv, _, args) => {
      if not(object_literals_safe_expr(recv, k, lits)) {
        return false
      }
      for a in args {
        if not(object_literals_safe_expr(a, k, lits)) {
          return false
        }
      }
      true
    }
    ArrayLit(items) => {
      for i in items {
        if not(object_literals_safe_expr(i, k, lits)) {
          return false
        }
      }
      true
    }
    ComputedProp(kx, v) =>
      object_literals_safe_expr(kx, k, lits) &&
         object_literals_safe_expr(v, k, lits)
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      object_literals_safe_expr(v, k, lits)
    CompoundAssignExpr(t, _, v) =>
      object_literals_safe_expr(t, k, lits) &&
         object_literals_safe_expr(v, k, lits)
    IndexAssignExpr(recv, idx, v) =>
      object_literals_safe_expr(recv, k, lits) &&
         object_literals_safe_expr(idx, k, lits) &&
         object_literals_safe_expr(v, k, lits)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => object_literals_safe_expr(e, k, lits)
        ArrowBlock(b) => {
          for s in b.stmts {
            if not(object_literals_safe_stmt(s, k, lits)) {
              return false
            }
          }
          true
        }
      }
    FuncExpr(f) =>
      for s in f.body.stmts {
        if not(object_literals_safe_stmt(s, k, lits)) {
          return false
        }
      } else {
        true
      }
    DynamicImport(spec, opts) => {
      if not(object_literals_safe_expr(spec, k, lits)) {
        return false
      }
      match opts {
        Some(o) => object_literals_safe_expr(o, k, lits)
        None => true
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      if not(object_literals_safe_expr(tag, k, lits)) {
        return false
      }
      for e in exprs {
        if not(object_literals_safe_expr(e, k, lits)) {
          return false
        }
      }
      true
    }
    TemplateLiteral(_, exprs) => {
      for e in exprs {
        if not(object_literals_safe_expr(e, k, lits)) {
          return false
        }
      }
      true
    }
    As(inner, _) | Satisfies(inner, _) =>
      object_literals_safe_expr(inner, k, lits)
    Yield(Some(inner)) => object_literals_safe_expr(inner, k, lits)
    _ => true
  }
}

// -- Step 4: rewrite --------------------------------------------------

///|
fn tag_rewrite_stmt(
  stmt : @ast.TsStmt,
  table : Map[String, Map[String, Int]],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, tag_rewrite_expr(e, table))
    Let(b, t, e) => Let(b, t, tag_rewrite_expr(e, table))
    Const(b, t, e) => Const(b, t, tag_rewrite_expr(e, table))
    Assign(n, e) => Assign(n, tag_rewrite_expr(e, table))
    CompoundAssign(n, op, e) => CompoundAssign(n, op, tag_rewrite_expr(e, table))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        tag_rewrite_expr(t, table),
        tag_rewrite_expr(idx, table),
        tag_rewrite_expr(v, table),
      )
    PropAssign(t, p, v) =>
      PropAssign(tag_rewrite_expr(t, table), p, tag_rewrite_expr(v, table))
    Expr(e) => Expr(tag_rewrite_expr(e, table))
    Return(Some(e)) => Return(Some(tag_rewrite_expr(e, table)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(tag_rewrite_expr(e, table))
    If(c, t, e) =>
      If(tag_rewrite_expr(c, table), tag_rewrite_block_inner(t, table), match e {
        Some(b) => Some(tag_rewrite_block_inner(b, table))
        None => None
      })
    While(c, body) => While(tag_rewrite_expr(c, table), tag_rewrite_block_inner(body, table))
    DoWhile(c, body) =>
      DoWhile(tag_rewrite_expr(c, table), tag_rewrite_block_inner(body, table))
    With(c, body) => With(tag_rewrite_expr(c, table), tag_rewrite_block_inner(body, table))
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(tag_rewrite_stmt(s, table))
          None => None
        },
        match cond {
          Some(e) => Some(tag_rewrite_expr(e, table))
          None => None
        },
        match update {
          Some(s) => Some(tag_rewrite_stmt(s, table))
          None => None
        },
        tag_rewrite_block_inner(body, table),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(k, b, t, tag_rewrite_expr(iter, table), tag_rewrite_block_inner(body, table))
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(k, b, t, tag_rewrite_expr(iter, table), tag_rewrite_block_inner(body, table))
    ForIn(k, b, t, iter, body) =>
      ForIn(k, b, t, tag_rewrite_expr(iter, table), tag_rewrite_block_inner(body, table))
    Switch(e, cases) => {
      // Identify the K (if any) being switched on. For each
      // `case "lit":` whose K is in the table, rewrite to
      // `case <id>:`.
      let switched_on : String? = match e {
        PropAccess(_, name) => if table.contains(name) { Some(name) } else { None }
        IndexAccess(_, @ast.TsExpr::StringLit(name)) =>
          if table.contains(name) { Some(name) } else { None }
        _ => None
      }
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        let new_test = match (switched_on, c.test_expr) {
          (Some(k), Some(@ast.TsExpr::StringLit(s))) =>
            match table.get(k) {
              Some(id_map) =>
                match id_map.get(s) {
                  Some(id) => Some(@ast.TsExpr::IntLit(id))
                  None => Some(@ast.TsExpr::StringLit(s))
                }
              None => Some(@ast.TsExpr::StringLit(s))
            }
          (_, Some(te)) => Some(tag_rewrite_expr(te, table))
          (_, None) => None
        }
        new_cases.push({
          test_expr: new_test,
          body: tag_rewrite_block_inner(c.body, table),
        })
      }
      Switch(tag_rewrite_expr(e, table), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        tag_rewrite_block_inner(b, table),
        bnd,
        match cb {
          Some(blk) => Some(tag_rewrite_block_inner(blk, table))
          None => None
        },
        match fb {
          Some(blk) => Some(tag_rewrite_block_inner(blk, table))
          None => None
        },
      )
    Label(name, inner) => Label(name, tag_rewrite_stmt(inner, table))
    Block(b) => Block(tag_rewrite_block_inner(b, table))
    NativeClassStmt(_, _) => stmt
  }
}

///|
fn tag_rewrite_block_inner(
  block : @ast.TsBlock,
  table : Map[String, Map[String, Int]],
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(tag_rewrite_stmt(s, table))
  }
  { stmts, stmt_positions: [] }
}

///|
fn tag_rewrite_expr(
  expr : @ast.TsExpr,
  table : Map[String, Map[String, Int]],
) -> @ast.TsExpr {
  match expr {
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        let new_val = match (table.get(ent.0), ent.1) {
          (Some(id_map), @ast.TsExpr::StringLit(s)) =>
            match id_map.get(s) {
              Some(id) => @ast.TsExpr::IntLit(id)
              None => tag_rewrite_expr(ent.1, table)
            }
          _ => tag_rewrite_expr(ent.1, table)
        }
        new_entries.push((ent.0, new_val))
      }
      ObjectLit(new_entries)
    }
    BinOp(op, l, r) => {
      // Comparison form `e.K === "lit"` (or symmetric) — rewrite the
      // literal to the corresponding int.
      let is_eq_op = match op {
        BinEq | BinNe | AbstractEq | AbstractNe => true
        _ => false
      }
      if is_eq_op {
        match try_rewrite_eq(l, r, table) {
          Some((nl, nr)) => return BinOp(op, nl, nr)
          None => ()
        }
      }
      BinOp(op, tag_rewrite_expr(l, table), tag_rewrite_expr(r, table))
    }
    UnaryOp(op, inner) => UnaryOp(op, tag_rewrite_expr(inner, table))
    Cond(c, t, e) =>
      Cond(tag_rewrite_expr(c, table), tag_rewrite_expr(t, table), tag_rewrite_expr(e, table))
    PropAccess(recv, p) => PropAccess(tag_rewrite_expr(recv, table), p)
    IndexAccess(recv, idx) =>
      IndexAccess(tag_rewrite_expr(recv, table), tag_rewrite_expr(idx, table))
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(tag_rewrite_expr(a, table))
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(tag_rewrite_expr(a, table))
      }
      CallExpr(tag_rewrite_expr(callee, table), new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(tag_rewrite_expr(a, table))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(tag_rewrite_expr(a, table))
      }
      NewExpr(tag_rewrite_expr(callee, table), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(tag_rewrite_expr(a, table))
      }
      MethodCall(tag_rewrite_expr(recv, table), m, new_args)
    }
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(tag_rewrite_expr(i, table))
      }
      ArrayLit(new_items)
    }
    Spread(inner) => Spread(tag_rewrite_expr(inner, table))
    Yield(Some(inner)) => Yield(Some(tag_rewrite_expr(inner, table)))
    YieldStar(inner) => YieldStar(tag_rewrite_expr(inner, table))
    Await(inner) => Await(tag_rewrite_expr(inner, table))
    Seq(a, b) => Seq(tag_rewrite_expr(a, table), tag_rewrite_expr(b, table))
    AssignExpr(n, v) => AssignExpr(n, tag_rewrite_expr(v, table))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(tag_rewrite_expr(t, table), op, tag_rewrite_expr(v, table))
    AssignPattern(b, v) => AssignPattern(b, tag_rewrite_expr(v, table))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(tag_rewrite_expr(recv, table), p, tag_rewrite_expr(v, table))
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        tag_rewrite_expr(recv, table),
        tag_rewrite_expr(idx, table),
        tag_rewrite_expr(v, table),
      )
    ComputedProp(k, v) =>
      ComputedProp(tag_rewrite_expr(k, table), tag_rewrite_expr(v, table))
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(tag_rewrite_expr(e, table))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(tag_rewrite_block_inner(b, table))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => FuncExpr({ ..f, body: tag_rewrite_block_inner(f.body, table) })
    DynamicImport(spec, opts) =>
      DynamicImport(
        tag_rewrite_expr(spec, table),
        match opts {
          Some(o) => Some(tag_rewrite_expr(o, table))
          None => None
        },
      )
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(tag_rewrite_expr(e, table))
      }
      TaggedTemplate(tag_rewrite_expr(tag, table), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(tag_rewrite_expr(e, table))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(tag_rewrite_expr(inner, table), ty)
    Satisfies(inner, ty) => Satisfies(tag_rewrite_expr(inner, table), ty)
    NonNull(inner) => NonNull(tag_rewrite_expr(inner, table))
    OptionalChain(inner) => OptionalChain(tag_rewrite_expr(inner, table))
    PureCall(inner) => PureCall(tag_rewrite_expr(inner, table))
    _ => expr
  }
}

///|
fn try_rewrite_eq(
  l : @ast.TsExpr,
  r : @ast.TsExpr,
  table : Map[String, Map[String, Int]],
) -> (@ast.TsExpr, @ast.TsExpr)? {
  match (l, r) {
    (@ast.TsExpr::PropAccess(recv, name), @ast.TsExpr::StringLit(s)) =>
      match table.get(name) {
        Some(id_map) =>
          match id_map.get(s) {
            Some(id) =>
              Some(
                (
                  PropAccess(tag_rewrite_expr(recv, table), name),
                  @ast.TsExpr::IntLit(id),
                ),
              )
            None => None
          }
        None => None
      }
    (@ast.TsExpr::StringLit(s), @ast.TsExpr::PropAccess(recv, name)) =>
      match table.get(name) {
        Some(id_map) =>
          match id_map.get(s) {
            Some(id) =>
              Some(
                (
                  @ast.TsExpr::IntLit(id),
                  PropAccess(tag_rewrite_expr(recv, table), name),
                ),
              )
            None => None
          }
        None => None
      }
    _ => None
  }
}
