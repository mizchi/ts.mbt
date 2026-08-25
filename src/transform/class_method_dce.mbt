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
// Safety. The pass is gated on the bundle never *observing* a
// method name it cannot spell out. What that comes down to:
//
//   * A dynamic READ `obj[k]` whose key isn't a literal and isn't
//     provably numeric. It reaches one property under a name we
//     can't predict, so any method could be the target. `arr[i]`
//     and `arr[i + 1]` clear the gate via the numeric-variable
//     inference in `numeric_vars.mbt` — an integer key can only
//     name an integer slot.
//   * Reflection over a class shape: `Object.getOwnPropertyNames`,
//     `Object.getOwnPropertyDescriptors`, `Reflect.ownKeys`,
//     `Reflect.getOwnPropertyDescriptor`. These see
//     *non-enumerable* properties, which is exactly what a class
//     prototype method is.
//
// Three shapes that look like sinks but aren't, and so don't gate
// the pass:
//
//   * A dynamic WRITE `obj[k] = v`, at any receiver. Writing never
//     observes an existing name, and installing a new one cannot
//     resurrect a method that was deleted.
//   * `delete obj.m` / `delete obj[k]`. Prototype methods are
//     configurable, so `delete` yields `true` either way, and a
//     `delete` on an instance never reaches the prototype. (The
//     named form pins `m` through the access collector regardless.)
//   * `Object.keys / values / entries / assign / fromEntries`,
//     `for...in`, and spread (`...x`) — all of these see only OWN
//     ENUMERABLE properties, and a native class puts its methods on
//     the prototype as non-enumerable. They do reach the
//     IIFE-lowered shape's `C.prototype.m = f`, though, so when the
//     bundle enumerates anything the pass pins every IIFE-assigned
//     prototype method and prunes native classes only.
//
// When the bundle clears those, drop every method whose name
// doesn't appear in the bundle's syntactic access set. The
// `constructor` is always kept (it's the body of `new C(...)`).
//
// One more input is needed for a *library* bundle: the bundle's own
// consumer. `class C { c3() {} }` exported from the entry has a
// public `c3` even when nothing inside the bundle calls it — the
// syntactic access set says "unused" and the method would be
// deleted. `keep` carries the names the export-surface analysis
// found reachable from the entry's exports; they are never dropped.

///|
pub fn class_method_dce_block(
  block : @ast.TsBlock,
  keep? : Map[String, Bool] = {},
  // `(field name, declared type)` for every runtime class in the
  // bundle. Needed because the class lowering drops the annotation —
  // a field with an initializer becomes a constructor assignment, so
  // the `NativeClassStmt` this pass walks carries no `properties` at
  // all. Without it `this.#cache[k]` reads as an unbounded member
  // access and one such read turns the whole pass off.
  class_fields? : Array[(String, @ast.TsType)] = [],
  // `type X = …` declarations in the bundle. An alias to a keyed
  // container is one — `type MatcherMap<T> = Record<string, Matcher<T>>`
  // is how real code spells the field whose computed reads otherwise
  // gate the pass.
  type_aliases? : Array[@ast.TsTypeAlias] = [],
  explain? : Array[String]? = None,
) -> @ast.TsBlock {
  // 1. Cheap exit when neither shape of class is present: no
  //    NativeClassStmt/Expr AND no IIFE-lowered class. (The IIFE
  //    pattern is `let X = function () { … return X; }();`.)
  let iife_classes = collect_iife_class_names(block)
  if !has_any_native_class(block) && iife_classes.is_empty() {
    match explain {
      Some(out) => out.push("nothing to do — the bundle declares no classes.")
      None => ()
    }
    return block
  }
  // 2. Bundle-wide reflection / dynamic-access scan. Any hit aborts.
  //    The two name sets are what let the scan tell a harmless
  //    dynamic read from a fatal one: `arr[i]` reads an integer
  //    slot, `map[k]` reads an entry of a keyed container, and
  //    `obj[k]` on anything else could name any member at all.
  let graph = build_symbol_graph(block, {})
  let class_names = declared_class_names(block)
  let alias_bodies : Map[String, @ast.TsType] = {}
  for ta in type_aliases {
    alias_bodies[ta.name] = ta.type_
  }
  let container_facts = {
    class_names,
    this_fields: class_field_containers(
      block, class_fields, class_names, alias_bodies,
    ),
    strings: string_name_set(graph),
    aliases: alias_bodies,
  }
  let facts = {
    numeric: numeric_name_set(graph, infer_numeric_symbols(graph)),
    keyed_containers: container_name_set(
      graph,
      infer_container_symbols(graph, container_facts),
    ),
    this_fields: container_facts.this_fields,
    reasons: [],
  }
  // Deliberately not `block_has_method_sniff`, which stops at the
  // first sink: scanning every top-level statement collects a
  // reason per module instead of one for the whole bundle, so the
  // report can rank the blocking patterns. The scan still
  // short-circuits inside a statement.
  let mut blocked = false
  for s in block.stmts {
    if stmt_has_method_sniff(s, facts) {
      blocked = true
    }
  }
  // 3. Collect the set of statically-accessed property names. Any
  //    `e.NAME` or `e["NAME"]` adds NAME, except names assigned
  //    inside an IIFE class body as `ClassName.prototype.NAME = …`
  //    — those are definitions, not uses, and counting them would
  //    defeat the DCE on the IIFE-lowered form.
  let accessed : Map[String, Bool] = {}
  collect_static_accesses_block_skipping_iife(block, iife_classes, accessed)
  // Externally visible members count as accesses.
  for name in keep.keys() {
    accessed[name] = true
  }
  // 3b. Own-enumerable enumeration downgrade. `Object.keys(x)` and
  //     friends cannot see a native class's prototype methods (they
  //     are non-enumerable), but they *can* see the IIFE-lowered
  //     shape's `C.prototype.m = f`. Rather than abort, keep every
  //     IIFE-assigned prototype method and let native classes still
  //     be pruned. `accessed` doubles as the detector: the access
  //     collector records every `.NAME`, so a bundle that calls
  //     `Object.assign` has `assign` in it. That over-approximates
  //     (a `map.keys()` call trips it too) in the safe direction.
  if block_enumerates_own_props(accessed) {
    for name in iife_prototype_method_names(block, iife_classes) {
      accessed[name] = true
    }
  }
  // 4. Report. The unreached methods are computed from the same
  //    `accessed` set the rewrite uses, whether or not the scan
  //    cleared — so when the pass is off the report still says what
  //    it would have cost.
  match explain {
    Some(out) => report_method_dce(block, accessed, facts, blocked, out)
    None => ()
  }
  if blocked {
    return block
  }
  // 5. Rewrite native class statements, filtering their method lists.
  let new_stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    new_stmts.push(dce_stmt(s, accessed))
  }
  { stmts: new_stmts, stmt_positions: block.stmt_positions }
}

///|
/// The distinct sinks the scan met, most frequent first, so the
/// report names the *patterns* that block the pass rather than one
/// arbitrary occurrence. Capped — a bundle with fifty variations of
/// the same shape has nothing more to say after the first dozen.
fn rank_sink_reasons(reasons : Array[String]) -> Array[String] {
  let counts : Map[String, Int] = {}
  for r in reasons {
    counts[r] = counts.get(r).unwrap_or(0) + 1
  }
  let ranked : Array[(String, Int)] = []
  for r, n in counts {
    ranked.push((r, n))
  }
  // Selection sort by count, descending. The list is one entry per
  // distinct sink shape, so it is short.
  for i in 0..<ranked.length() {
    let mut best = i
    for j in (i + 1)..<ranked.length() {
      if ranked[j].1 > ranked[best].1 {
        best = j
      }
    }
    if best != i {
      let tmp = ranked[i]
      ranked[i] = ranked[best]
      ranked[best] = tmp
    }
  }
  let out : Array[String] = []
  let cap = 12
  out.push("sinks, most frequent first:")
  for i in 0..<ranked.length() {
    if i >= cap {
      out.push(
        "  … and " +
        (ranked.length() - cap).to_string() +
        " more distinct sink shape(s).",
      )
      break
    }
    out.push("  [x" + ranked[i].1.to_string() + "] " + ranked[i].0)
  }
  out
}

///|
/// Fill `out` with the `--explain-mangle` section for this pass:
/// which methods went (or would have gone), and — when the scan
/// found a sink — the construct that turned the pass off.
fn report_method_dce(
  block : @ast.TsBlock,
  accessed : Map[String, Bool],
  facts : SniffFacts,
  blocked : Bool,
  out : Array[String],
) -> Unit {
  let unreached : Array[String] = []
  for s in block.stmts {
    match s {
      NativeClassStmt(decl, _) =>
        for m in decl.methods {
          if m.name != "constructor" && !accessed.contains(m.name) {
            unreached.push(decl.name + "." + m.name)
          }
        }
      _ => ()
    }
  }
  if blocked {
    out.push(
      "SUPPRESSED — a sink in the bundle can observe a member name the " +
      "pass cannot spell out, so every class keeps every method.",
    )
    for line in rank_sink_reasons(facts.reasons) {
      out.push(line)
    }
    if unreached.length() == 0 {
      out.push("nothing would have been dropped anyway.")
    } else {
      out.push(
        "would have dropped " +
        unreached.length().to_string() +
        " unreached method(s):",
      )
      for name in unreached {
        out.push("  " + name)
      }
    }
    return
  }
  if unreached.length() == 0 {
    out.push("every declared method is reachable; nothing dropped.")
  } else {
    out.push("dropped " + unreached.length().to_string() + " method(s):")
    for name in unreached {
      out.push("  " + name)
    }
  }
}

///|
/// What the sink scan needs to know about the bundle's bindings to
/// judge a computed-key read. Both sets are name-keyed and drop
/// shadowed names, so a hit is a proof about *the* binding of that
/// name.
struct SniffFacts {
  /// Bindings that provably hold a number (`numeric_vars.mbt`).
  numeric : Map[String, Bool]
  /// Bindings whose declared type is a keyed container rather than an
  /// object with members — an array, a tuple, a string, a `Record`.
  keyed_containers : Map[String, Bool]
  /// Property names every class in the bundle types as a keyed
  /// container, so `this.f[k]` is an entry lookup. Same set the
  /// container inference uses for `const x = this.f`.
  this_fields : Map[String, Bool]
  /// Every construct the scan judged a sink, in the order it met
  /// them, so `--explain-mangle` can name what turned the pass off
  /// instead of just reporting that it is off. Written by the scan
  /// itself, which is why the explanation cannot drift from the
  /// decision.
  reasons : Array[String]
}

///|
/// Names of classes declared in this bundle. Only their methods can
/// be deleted, so only their names disqualify a container type below.
fn declared_class_names(block : @ast.TsBlock) -> Map[String, Bool] {
  let out : Map[String, Bool] = {}
  for s in block.stmts {
    match s {
      NativeClassStmt(decl, _) => out[decl.name] = true
      _ => ()
    }
  }
  for n in collect_iife_class_names(block).keys() {
    out[n] = true
  }
  out
}

///|
/// A short rendering of `recv[idx]` for the explain report — enough
/// to find the access in the source. Shapes the renderer can't name
/// become `…`.
fn describe_index_read(recv : @ast.TsExpr, idx : @ast.TsExpr) -> String {
  describe_index_operand(recv) + "[" + describe_index_operand(idx) + "]"
}

///|
fn describe_index_operand(e : @ast.TsExpr) -> String {
  match e {
    Var(n) => n
    StringLit(s) => "\"" + s + "\""
    PropAccess(inner, p) => describe_index_operand(inner) + "." + p
    MethodCall(inner, m, _) => describe_index_operand(inner) + "." + m + "()"
    IndexAccess(inner, k) =>
      describe_index_operand(inner) + "[" + describe_index_operand(k) + "]"
    NonNull(inner) | OptionalChain(inner) => describe_index_operand(inner)
    _ => "…"
  }
}

///|
/// True when the receiver of a computed-key read is something whose
/// declared type makes the read an entry lookup rather than a member
/// access — a bare name, or `this.f` inside a class body. For any
/// other receiver (`a.b[k]`, `f()[k]`) there is no annotation to
/// consult, so it does not qualify.
fn receiver_is_keyed_container(recv : @ast.TsExpr, facts : SniffFacts) -> Bool {
  match recv {
    Var(n) => facts.keyed_containers.contains(n)
    // `this.f[k]` — `f` is a field of the class we are inside, and the
    // set only holds names every class in the bundle types as a
    // container, so it does not matter which class that is.
    PropAccess(@ast.TsExpr::Var("this"), f) => facts.this_fields.contains(f)
    _ => false
  }
}

///|
/// The prefix the parser gives a `#private` class field. A property
/// name carrying it cannot belong to anything but the class body it
/// was declared in.
let private_field_brand_prefix : String = "__private_brand__"

///|
/// Names of **private** fields that are a keyed container on every
/// class in the bundle that declares them. `this.#f` is provably that
/// class's field: a private name is lexically scoped to the class
/// body, so no object literal, no host object, and no function called
/// with a different receiver can carry it. That is what lets
/// `const middleware = this.#middleware; middleware[i]` clear the
/// computed-read gate without an annotation at the local.
///
/// Public fields are deliberately excluded. `this.f` says nothing
/// about which object `this` is:
///
///   class Registry { table: Record<string, string> = {}; … }
///   const holder = {
///     table: new Worker(),
///     call(k: string) { return this.table[k]; },   // a Worker's member
///   };
///
/// Reading `Registry`'s annotation for `table` here would clear a read
/// that really does name a `Worker` method, and `Worker`'s unused
/// methods would then be deleted out from under it. The parser gives
/// private fields a brand-prefixed name, which is the test.
///
/// A name any class types as something else is dropped outright, so a
/// disagreement decides against the promotion.
fn class_field_containers(
  block : @ast.TsBlock,
  class_fields : Array[(String, @ast.TsType)],
  class_names : Map[String, Bool],
  aliases : Map[String, @ast.TsType],
) -> Map[String, Bool] {
  let container : Map[String, Bool] = {}
  let other : Map[String, Bool] = {}
  // The annotations the parser captured before the lowering erased
  // them. This is the source that actually has anything to say on a
  // real bundle; the walk below only catches classes that still carry
  // `properties` by the time this pass runs.
  for f in class_fields {
    if !f.0.has_prefix(private_field_brand_prefix) {
      continue
    }
    if type_is_keyed_container(f.1, class_names, aliases) {
      container[f.0] = true
    } else {
      other[f.0] = true
    }
  }
  for s in block.stmts {
    match s {
      NativeClassStmt(decl, _) =>
        for p in decl.properties {
          if !p.name.has_prefix(private_field_brand_prefix) {
            continue
          }
          if type_is_keyed_container(p.type_, class_names, aliases) {
            container[p.name] = true
          } else {
            other[p.name] = true
          }
        }
      _ => ()
    }
  }
  let out : Map[String, Bool] = {}
  for name in container.keys() {
    if !other.contains(name) {
      out[name] = true
    }
  }
  out
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
/// True when the bundle observes own enumerable property names
/// anywhere — `Object.keys` / `values` / `entries` / `assign` /
/// `fromEntries`, or a `for...in`. Reads the already-collected
/// access set instead of re-walking the tree: the collector records
/// the callee name of every `recv.m(...)`, so `Object.assign(...)`
/// leaves `assign` behind. Any same-named call on an unrelated
/// receiver trips it too, which only makes the pass more careful.
fn block_enumerates_own_props(accessed : Map[String, Bool]) -> Bool {
  if accessed.contains(for_in_sentinel) {
    return true
  }
  for m in own_enum_sniff_methods {
    if accessed.contains(m) {
      return true
    }
  }
  false
}

///|
/// Every method name assigned as `C.prototype.NAME = …` inside the
/// body of an IIFE-lowered class. Seeding these into the access set
/// pins them, which is how the pass restricts itself to native
/// classes when the bundle enumerates own enumerable properties.
/// The three statement shapes mirror `iife_method_assignment_is_dead`
/// so nothing it would delete is left unpinned.
fn iife_prototype_method_names(
  block : @ast.TsBlock,
  iife_classes : Map[String, Bool],
) -> Array[String] {
  let out : Array[String] = []
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
          for inner in f.body.stmts {
            match iife_prototype_member_name(inner) {
              Some(name) => out.push(name)
              None => ()
            }
          }
        }
      _ => ()
    }
  }
  out
}

///|
/// The `NAME` in `X.prototype.NAME = …` (or `X.prototype.NAME.SUB =
/// …`), for the statement shapes the IIFE pruner recognizes.
fn iife_prototype_member_name(stmt : @ast.TsStmt) -> String? {
  match stmt {
    PropAssign(@ast.TsExpr::PropAccess(_, "prototype"), name, _) => Some(name)
    PropAssign(
      @ast.TsExpr::PropAccess(@ast.TsExpr::PropAccess(_, "prototype"), name),
      _,
      _
    ) => Some(name)
    Expr(
      @ast.TsExpr::PropAssignExpr(
        @ast.TsExpr::PropAccess(_, "prototype"),
        name,
        _
      )
    ) => Some(name)
    _ => None
  }
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
  // Reflective method-name observation. These see *non-enumerable*
  // properties too, which is exactly what a class prototype method
  // is, so a bundle containing any of them can observe a name this
  // pass would delete. Hard abort.
  "getOwnPropertyNames", "getOwnPropertyDescriptors", "ownKeys", "getOwnPropertyDescriptor",
]

///|
/// Own-enumerable property enumeration. `Object.keys` / `values` /
/// `entries` / `assign` / `fromEntries` (and `for...in`) only ever
/// observe **own enumerable** properties, and a native
/// `class C { m() {} }` puts `m` on the prototype as a
/// *non-enumerable* property — so none of these can see it, and
/// they must not abort the pass. (`Object.assign(this, opts)` in a
/// constructor is the shape that used to disable method DCE for a
/// whole bundle.)
///
/// The IIFE-lowered shape is different: `C.prototype.m = f` creates
/// an own **enumerable** property of the prototype object, which
/// `Object.keys(C.prototype)` and `for (const k in instance)` both
/// report. So when the bundle enumerates anything, the pass keeps
/// every IIFE-assigned prototype method and prunes native classes
/// only.
let own_enum_sniff_methods : Array[String] = [
  "keys", "entries", "values", "assign", "fromEntries",
]

///|
/// Sentinel key recorded in the access set when the bundle contains a
/// `for...in`. Not a possible JavaScript member name, so it can never
/// collide with a real access.
let for_in_sentinel : String = "<for-in>"

///|
fn block_has_method_sniff(block : @ast.TsBlock, facts : SniffFacts) -> Bool {
  for s in block.stmts {
    if stmt_has_method_sniff(s, facts) {
      return true
    }
  }
  false
}

///|
fn stmt_has_method_sniff(stmt : @ast.TsStmt, facts : SniffFacts) -> Bool {
  match stmt {
    // for-in iterates property names, but the body itself may or may
    // not access prototype methods; recurse rather than unconditionally
    // aborting. The iter expression and body are checked the same way
    // ForOf is, since a `for...in` body can still contain calls or
    // computed accesses that are legitimate method-sniff sinks.
    ForIn(_, _, _, iter, body) =>
      expr_has_method_sniff(iter, facts) || block_has_method_sniff(body, facts)
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Throw(e) => expr_has_method_sniff(e, facts)
    Return(Some(e)) => expr_has_method_sniff(e, facts)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => false
    IndexAssign(t, idx, v) =>
      // Computed WRITE, statement form. Not a sink at any receiver:
      // see the `IndexAssignExpr` arm of `expr_has_method_sniff`.
      expr_has_method_sniff(t, facts) ||
      expr_has_method_sniff(idx, facts) ||
      expr_has_method_sniff(v, facts)
    PropAssign(t, _, v) =>
      expr_has_method_sniff(t, facts) || expr_has_method_sniff(v, facts)
    If(c, t, e) => {
      if expr_has_method_sniff(c, facts) {
        return true
      }
      if block_has_method_sniff(t, facts) {
        return true
      }
      match e {
        Some(b) => block_has_method_sniff(b, facts)
        None => false
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) =>
      expr_has_method_sniff(c, facts) || block_has_method_sniff(body, facts)
    For(init, cond, update, body) => {
      let init_bad = match init {
        Some(s) => stmt_has_method_sniff(s, facts)
        None => false
      }
      if init_bad {
        return true
      }
      let cond_bad = match cond {
        Some(e) => expr_has_method_sniff(e, facts)
        None => false
      }
      if cond_bad {
        return true
      }
      let upd_bad = match update {
        Some(s) => stmt_has_method_sniff(s, facts)
        None => false
      }
      if upd_bad {
        return true
      }
      block_has_method_sniff(body, facts)
    }
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body) =>
      expr_has_method_sniff(iter, facts) || block_has_method_sniff(body, facts)
    Switch(e, cases) => {
      if expr_has_method_sniff(e, facts) {
        return true
      }
      for c in cases {
        match c.test_expr {
          Some(te) => if expr_has_method_sniff(te, facts) { return true }
          None => ()
        }
        if block_has_method_sniff(c.body, facts) {
          return true
        }
      }
      false
    }
    Try(b, _, cb, fb) => {
      if block_has_method_sniff(b, facts) {
        return true
      }
      let cb_bad = match cb {
        Some(blk) => block_has_method_sniff(blk, facts)
        None => false
      }
      if cb_bad {
        return true
      }
      match fb {
        Some(blk) => block_has_method_sniff(blk, facts)
        None => false
      }
    }
    Label(_, inner) => stmt_has_method_sniff(inner, facts)
    Block(b) => block_has_method_sniff(b, facts)
    NativeClassStmt(decl, ctor_body) => {
      // Walk the methods' bodies too — internal reflection on
      // `this` (e.g. `Object.keys(this)`) counts as a sink.
      for m in decl.methods {
        match m.body {
          Some(b) => if block_has_method_sniff(b, facts) { return true }
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        if expr_has_method_sniff(sf.1, facts) {
          return true
        }
      }
      match ctor_body {
        Some(f) => block_has_method_sniff(f.body, facts)
        None => false
      }
    }
  }
}

///|
fn expr_has_method_sniff(expr : @ast.TsExpr, facts : SniffFacts) -> Bool {
  match expr {
    // `Object.foo(...)` / `Reflect.foo(...)` reflection sink.
    MethodCall(@ast.TsExpr::Var(recv), m, args) => {
      let recv_is_reflective = recv == "Object" || recv == "Reflect"
      if recv_is_reflective && method_sniff_methods.contains(m) {
        facts.reasons.push(
          "`" +
          recv +
          "." +
          m +
          "(...)` reports non-enumerable properties, which is what a " +
          "class prototype method is",
        )
        return true
      }
      for a in args {
        if expr_has_method_sniff(a, facts) {
          return true
        }
      }
      false
    }
    // Object spread `{...x}` only copies OWN enumerable properties;
    // class prototype methods are NOT own properties of instances, so
    // spreading a class instance never enumerates its methods. Recurse
    // into the inner expression for reflection sinks but do NOT abort
    // just because spread is present.
    Spread(inner) => expr_has_method_sniff(inner, facts)
    // `delete x.method` / `delete x[k]`. Deleting a name is not
    // observing one: a class prototype method is configurable, so
    // `delete` evaluates to `true` whether or not the method is
    // still there, and deleting an own property of an instance never
    // reaches the prototype at all. Just walk the operand — for
    // `delete x.m` that is a `PropAccess`, so the access collector
    // pins `m` and the method survives on its own merits.
    UnaryOp(@ast.TsUnaryOp::Delete, inner) =>
      expr_has_method_sniff(inner, facts)
    // Computed-key READ. `obj[k]` reaches exactly one property, but
    // not one we can name — if `k` can evaluate to a deletable
    // method name, dropping that method breaks the dispatch. So a
    // string-keyed dynamic read aborts unless one of two proofs
    // clears it. A *numeric* key can only name an integer slot:
    // `is_index_numeric_with_names` establishes that for the common
    // `arr[i]` / `arr[i + 1]` / `arr[n - 1]` shapes through the
    // numeric-variable inference. Otherwise the *receiver* can
    // settle it — reading an entry out of an array or a `Record`
    // never reaches a method (see `container_vars.mbt`).
    IndexAccess(recv, idx) => {
      if !is_static_index_for_method_dce(idx) &&
        !is_index_numeric_with_names(idx, facts.numeric) &&
        !receiver_is_keyed_container(recv, facts) {
        facts.reasons.push(
          "`" +
          describe_index_read(recv, idx) +
          "` reads a member under a computed key that is neither " +
          "provably numeric nor an entry of a keyed container, so any " +
          "method could be the one it names",
        )
        return true
      }
      expr_has_method_sniff(recv, facts) || expr_has_method_sniff(idx, facts)
    }
    // Computed-key WRITE. A write never observes an existing name,
    // and installing a property under a computed key cannot
    // resurrect a method this pass deleted, so `obj[k] = v` is not a
    // sink at any receiver — `C.prototype[k] = v` included.
    IndexAssignExpr(recv, idx, v) =>
      expr_has_method_sniff(recv, facts) ||
      expr_has_method_sniff(idx, facts) ||
      expr_has_method_sniff(v, facts)
    Call(name, args) => {
      // Bare `Object.keys` style isn't here (that's MethodCall).
      // But common globals named after sinks shouldn't slip
      // through — be conservative when seeing them by name.
      if name == "Object" || name == "Reflect" {
        // `Object(x)` / `Reflect(x)` — let's just play safe.
        facts.reasons.push(
          "a bare `" + name + "(...)` call, which could be any reflection op",
        )
        return true
      }
      for a in args {
        if expr_has_method_sniff(a, facts) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if expr_has_method_sniff(callee, facts) {
        return true
      }
      for a in args {
        if expr_has_method_sniff(a, facts) {
          return true
        }
      }
      false
    }
    MethodCall(recv, _, args) => {
      if expr_has_method_sniff(recv, facts) {
        return true
      }
      for a in args {
        if expr_has_method_sniff(a, facts) {
          return true
        }
      }
      false
    }
    New(_, args) => {
      for a in args {
        if expr_has_method_sniff(a, facts) {
          return true
        }
      }
      false
    }
    BinOp(_, l, r) | Seq(l, r) =>
      expr_has_method_sniff(l, facts) || expr_has_method_sniff(r, facts)
    UnaryOp(_, inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | YieldStar(inner) => expr_has_method_sniff(inner, facts)
    Cond(c, t, e) =>
      expr_has_method_sniff(c, facts) ||
      expr_has_method_sniff(t, facts) ||
      expr_has_method_sniff(e, facts)
    PropAccess(recv, _) => expr_has_method_sniff(recv, facts)
    ArrayLit(items) => {
      for i in items {
        if expr_has_method_sniff(i, facts) {
          return true
        }
      }
      false
    }
    ObjectLit(entries) => {
      for ent in entries {
        if expr_has_method_sniff(ent.1, facts) {
          return true
        }
      }
      false
    }
    ComputedProp(k, v) =>
      expr_has_method_sniff(k, facts) || expr_has_method_sniff(v, facts)
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      expr_has_method_sniff(v, facts)
    CompoundAssignExpr(t, _, v) =>
      expr_has_method_sniff(t, facts) || expr_has_method_sniff(v, facts)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => expr_has_method_sniff(e, facts)
        ArrowBlock(b) => block_has_method_sniff(b, facts)
      }
    FuncExpr(f) => block_has_method_sniff(f.body, facts)
    DynamicImport(spec, opts) => {
      if expr_has_method_sniff(spec, facts) {
        return true
      }
      match opts {
        Some(o) => expr_has_method_sniff(o, facts)
        None => false
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      if expr_has_method_sniff(tag, facts) {
        return true
      }
      for e in exprs {
        if expr_has_method_sniff(e, facts) {
          return true
        }
      }
      false
    }
    TemplateLiteral(_, exprs) => {
      for e in exprs {
        if expr_has_method_sniff(e, facts) {
          return true
        }
      }
      false
    }
    As(inner, _) | Satisfies(inner, _) => expr_has_method_sniff(inner, facts)
    Yield(Some(inner)) => expr_has_method_sniff(inner, facts)
    NativeClassExpr(decl, ctor_body) => {
      for m in decl.methods {
        match m.body {
          Some(b) => if block_has_method_sniff(b, facts) { return true }
          None => ()
        }
      }
      match ctor_body {
        Some(f) => block_has_method_sniff(f.body, facts)
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
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body) => {
      collect_static_accesses_expr(iter, out)
      collect_static_accesses_block(body, out)
    }
    ForIn(_, _, _, iter, body) => {
      // `for (const k in obj)` enumerates own *and* inherited
      // enumerable keys — it sees an IIFE-lowered
      // `C.prototype.m = f` even though it cannot see a native
      // class method. Record it so the pass falls back to
      // native-class-only pruning.
      out[for_in_sentinel] = true
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
        !accessed.contains(method_name) {
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
        !accessed.contains(method_name) {
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
        !accessed.contains(method_name) {
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
        !accessed.contains(method_name) {
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
