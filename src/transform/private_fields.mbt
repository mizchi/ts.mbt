// Emit `#private` fields as `#private` fields.
//
// The parser rewrites `#secret` into `__private_brand__<N>__secret`,
// where `N` identifies the declaring class. That encoding is what makes
// privacy NOMINAL for the checker — two classes can each have a
// `#secret` and they are different members — and it is the right
// representation for type checking.
//
// It is the wrong thing to EMIT. A branded property is an ordinary own
// enumerable property, so
//
//   class C { #secret = 7; }
//   console.log(JSON.stringify(new C()));
//
// printed `{"__private_brand__0__secret":7}` where Node prints `{}`.
// `Object.keys`, `for...in` and object spread saw it too. It was the
// fuzzer's single largest failure family, and the confusing part was
// that the MANGLED output was the correct one — the mangler treats the
// brand as an internal marker and drops the write, which happens to
// match what a real private field does.
//
// So map the brand back to `#` before anything else runs. Three things
// make this a rename rather than a rewrite:
//
//   * `rename_properties_in_block` already visits every property-name
//     site there is, including class method names and the
//     `TsClassDecl.properties` declaration list. No new walker.
//   * `collect_property_names` already answers "which property names
//     does this block mention". No new walker there either.
//   * the declaration a class body needs (`#secret;`, so the
//     constructor's `this.#secret = 7` has something to assign to) comes
//     from `TsClassDecl.properties`, which the parser fills per class.
//     Emit reads it directly.
//
// Two classes that both declare `#secret` collapse to the same text,
// and that is correct: a private name is scoped to the class body that
// declares it, so if one of those classes is nested inside the other,
// the inner `#secret` shadows the outer one — which is exactly what the
// source said, because the source declared both. A nested class that
// only REFERENCES the outer's `#secret` has no entry of its own in
// `properties`, so nothing is declared for it and the reference
// resolves outward, again as written.
//
// The IIFE-lowered class shape is not covered. `#` syntax is only legal
// inside a class body, and that path emits `C.prototype.m = function`
// into plain statements; there is nowhere to put the declaration. Those
// keep the brand, and `is_internal_marker_property` keeps them
// manglable.

///|
/// `__private_brand__<N>__<member>` -> `<member>`, or `None` when the
/// name is not a brand.
fn private_brand_member(name : String) -> String? {
  let prefix = "__private_brand__"
  if !name.has_prefix(prefix) {
    return None
  }
  let rest = name[prefix.length():].to_owned()
  match rest.find("__") {
    Some(i) => {
      let member = rest[i + 2:].to_owned()
      if member.is_empty() {
        None
      } else {
        Some(member)
      }
    }
    None => None
  }
}

///|
/// Is this a lowered private name, ready to emit as `#x`?
pub fn is_private_member_name(name : String) -> Bool {
  name.has_prefix("#") && name.length() > 1
}

///|
/// Rewrite every `__private_brand__N__x` property name in the block to
/// `#x`. A no-op for a bundle with no private members.
pub fn lower_private_fields(block : @ast.TsBlock) -> @ast.TsBlock {
  // Which BRANDS will actually get a declaration.
  //
  // `#x` is only legal inside a class body, and a `#x` reference with no
  // `#x;` declaration in that body is a SyntaxError. So the rename is
  // driven by the declarations that will be emitted, and keyed by the
  // full brand name rather than by the member name. Keying by member
  // name looked tempting — it would also fix a nested class reading an
  // outer private under its own brand — but it renames a DIFFERENT
  // class's brand that happens to share the member name, and if that
  // class is one of the shapes below, the result is a parse error.
  //
  // Two sources, both flat scans of a top-level class node:
  //
  //   * `this.#x = …` at the top level of a constructor. The class
  //     lowering puts every instance field initializer there, a bare
  //     `#x;` included (as `this.#x = void 0`). `emit.mbt` reads the
  //     same statements to emit the declarations, so the two agree by
  //     construction.
  //   * a private METHOD name, which declares itself as `#m() {}`.
  //
  // What is deliberately NOT in the set, and so keeps the brand:
  //
  //   * `static #x = 3` — the class lowering drops static private
  //     fields outright, initializer and all, so `C.#x` already reads
  //     `undefined` today. Keeping the brand leaves that bug as it is
  //     instead of turning it into a parse error.
  //   * a typed field with no initializer (`#x: T | undefined;`), which
  //     produces no constructor assignment either.
  //   * a class the IIFE lift declined, whose members live as
  //     `C.prototype.m = function` in plain statements — there is
  //     nowhere to put a declaration.
  //   * a class nested inside a method, which is not a top-level node
  //     here.
  //
  // All four are recorded in `fixtures/fuzz-findings/README.md`.
  let declarable : Map[String, Bool] = {}
  for s in block.stmts {
    match s {
      @ast.TsStmt::NativeClassStmt(decl, ctor) =>
        collect_declarable_members(decl, ctor, declarable)
      @ast.TsStmt::Let(_, _, @ast.TsExpr::NativeClassExpr(decl, ctor))
      | @ast.TsStmt::Const(_, _, @ast.TsExpr::NativeClassExpr(decl, ctor))
      | @ast.TsStmt::Var(_, _, @ast.TsExpr::NativeClassExpr(decl, ctor)) =>
        collect_declarable_members(decl, ctor, declarable)
      _ => ()
    }
  }
  if declarable.is_empty() {
    return block
  }
  // One more thing has to hold: the brand must not be mentioned by any
  // OTHER top-level statement. `#x` is scoped to the class body, so a
  // reference from anywhere else cannot be spelled `#x` — and mtsc
  // itself produces such references. hono's `Context` has an accessor
  // lowered to
  //
  //   Object.defineProperty(Context.prototype, KEY, {
  //     get: function () { return this.#matchResult }, … });
  //
  // emitted as a statement of its own, next to the class. Renaming the
  // brand gave that getter a `#matchResult` with no enclosing class —
  // "Private field '#matchResult' must be declared in an enclosing
  // class", and the whole bundle stopped loading.
  //
  // Counting the statements that mention each name is one scan and
  // exact at statement granularity: a brand mentioned by exactly one
  // top-level statement is confined to the class node that declares it.
  let stmt_count : Map[String, Int] = {}
  for st in block.stmts {
    let one : Map[String, Bool] = {}
    collect_property_names({ stmts: [st], stmt_positions: [] }, one)
    for n in one.keys() {
      stmt_count[n] = stmt_count.get(n).unwrap_or(0) + 1
    }
  }
  let map : Map[String, String] = {}
  for n in declarable.keys() {
    if stmt_count.get(n).unwrap_or(0) != 1 {
      continue
    }
    match private_brand_member(n) {
      Some(member) => {
        // The bare `#member` spelling must not already be in the
        // bundle. The parser only brands a `#x` reference when it is
        // lexically inside a class body — a reference mtsc hoisted OUT
        // of one keeps the raw `#x`, so the escaped getter above reads
        // `#matchResult` while the class writes
        // `__private_brand__N__matchResult`. Renaming the brand to the
        // same text is what put a `#` name outside a class body.
        if stmt_count.contains("#" + member) {
          continue
        }
        map[n] = "#" + member
      }
      None => ()
    }
  }
  if map.is_empty() {
    return block
  }
  rename_properties_in_block(block, map)
}

///|
/// Names assigned to `this` at the TOP LEVEL of the constructor or of
/// any method body, that look like a private member — a brand before
/// the rename, a `#` name after it.
///
/// One function for both sides on purpose. The pass renames a brand
/// only when a declaration will be emitted for it, and `emit.mbt` emits
/// a declaration for exactly what this returns; if the two scans could
/// drift, the drift is a SyntaxError.
///
/// Flat by design. A `this.#x = v` buried in an `if` is not found, so
/// that brand keeps its old spelling — a visible property, which is
/// what it already was, rather than a `#x` with no declaration.
fn class_private_this_assigns(
  decl : @ast.TsClassDecl,
  ctor : @ast.TsFunc?,
) -> Array[String] {
  let out : Array[String] = []
  let seen : Map[String, Bool] = {}
  fn scan(body : @ast.TsBlock) -> Unit {
    for s in body.stmts {
      let prop = match s {
        @ast.TsStmt::PropAssign(@ast.TsExpr::Var("this"), p, _) => p
        @ast.TsStmt::Expr(
          @ast.TsExpr::PropAssignExpr(@ast.TsExpr::Var("this"), p, _)
        ) => p
        _ => ""
      }
      let looks_private = is_private_member_name(prop) ||
        private_brand_member(prop) is Some(_)
      if looks_private && !seen.contains(prop) {
        seen[prop] = true
        out.push(prop)
      }
    }
  }

  match ctor {
    Some(f) => scan(f.body)
    None => ()
  }
  for m in decl.methods {
    match m.body {
      Some(b) => scan(b)
      None => ()
    }
  }
  out
}

///|
/// Brand names of one class that will get a `#` declaration, plus its
/// private method names — a private method declares itself as
/// `#m() {}` and needs no field declaration, but its name still has to
/// be renamed.
fn collect_declarable_members(
  decl : @ast.TsClassDecl,
  ctor : @ast.TsFunc?,
  out : Map[String, Bool],
) -> Unit {
  for name in class_private_this_assigns(decl, ctor) {
    if private_brand_member(name) is Some(_) {
      out[name] = true
    }
  }
  for m in decl.methods {
    if private_brand_member(m.name) is Some(_) {
      out[m.name] = true
    }
  }
}
