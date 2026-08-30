// Class names the bundle reads back off `Function.prototype.name`.
//
// `--mangle` renames a class and `C.name` changes with it. superstruct's
// error base does
//
//   this.name = this.constructor.name
//
// so after mangling `err.name` came back `"a"` instead of
// `"StructError"`, and the `fixtures/type-aware-corpus` driver caught it
// as an observable difference.
//
// terser and esbuild both rename class names by default
// (`keep_classnames: false`) and expect the library to opt out. This
// pass takes the other side, for one reason: the read is IN THE SOURCE.
// A minifier that can see `this.constructor.name` does not have to
// choose between correctness and bytes for the whole bundle — it can pay
// for the names actually observed and mangle the rest. That is the same
// trade the property mangler already makes.
//
// Three receiver shapes, three answers:
//
//   C.name              names C. Reserve exactly C.
//   x.constructor.name  names nothing. Any class could be on the other
//                       end of `x`, so no top-level name may be renamed.
//   anything else       ignored. See the hole below.
//
// THE HOLE, stated plainly: `foo().name` where `foo` returns a class is
// not caught. Neither is `bag.ctor.name` where `bag.ctor` holds one, nor
// `C.name` where `C` is a class declared inside a function body rather
// than at the top level — the caller's constructor table is top-level
// (plus nested blocks), because that is what it can enumerate without
// another walker whose misses fail toward a renamed class.
// Proving those needs to know what an arbitrary expression evaluates to,
// and treating every `.name` read as dangerous is not an option —
// `err.name`, `req.name`, `{name: …}.name` are everywhere, and the pass
// would reserve the top level of nearly every bundle. So this is
// strictly better than renaming class names unconditionally, and it is
// not a proof. The two shapes that occur in practice are covered.
//
// The receiver classification happens inside
// `collect_read_property_names_expr` (`dead_props.mbt`), which is
// already threaded through every expression shape and already
// load-bearing for dead-property elimination. Findings come back as
// sentinel keys in the map it fills. That is a peculiar channel and it
// buys something specific: a second sink threaded through ninety-odd
// arms loses a subtree the moment one recursive call forgets to pass it
// along, and a lost subtree here is a renamed class and a wrong
// `err.name`. Riding a map that is already threaded correctly cannot
// drift that way.

///|
/// Sentinel prefix for "the bundle reads `<name>.name`".
const NAME_OF_PREFIX : String = "@@nameof:"

///|
/// Sentinel for "the bundle reads `<something>.constructor.name`", where
/// the class cannot be named syntactically.
const NAME_OF_CTOR : String = "@@nameof-constructor"

///|
/// Sentinel prefix for "the bundle compares `<something>.constructor.name`
/// against this string literal, and does nothing else with it".
///
/// Recorded by the equality arm of `collect_read_property_names_expr`
/// INSTEAD of `NAME_OF_CTOR`, which is what makes the narrowing below
/// complete by construction: a read in any other position still takes
/// the generic path and still reserves every callable.
const NAME_OF_CTOR_EQ_PREFIX : String = "@@nameof-ctor-eq:"

///|
/// Is this operator an equality comparison, i.e. one whose result
/// depends on the operand strings only through `===`-style identity?
///
/// Relational operators are excluded on purpose. `name < "M"` observes
/// the name's ORDER, which a rename changes even when no name equals a
/// literal, so the literal set says nothing there.
pub fn binop_is_equality(op : @ast.TsBinOp) -> Bool {
  match op {
    @ast.TsBinOp::BinEq
    | @ast.TsBinOp::BinNe
    | @ast.TsBinOp::AbstractEq
    | @ast.TsBinOp::AbstractNe => true
    _ => false
  }
}

///|
/// If `expr` is exactly `<recv>.constructor.name` (or the `["…"]`
/// spellings of either step), return `<recv>`.
///
/// Deliberately narrow: only the shapes `record_name_receiver` would
/// have classified as `NAME_OF_CTOR`, so the two cannot disagree about
/// which reads the narrowing accounts for.
pub fn ctor_name_read_receiver(expr : @ast.TsExpr) -> @ast.TsExpr? {
  let inner = match expr {
    @ast.TsExpr::PropAccess(inner, "name") => inner
    @ast.TsExpr::IndexAccess(inner, @ast.TsExpr::StringLit("name")) => inner
    _ => return None
  }
  match inner {
    @ast.TsExpr::PropAccess(recv, "constructor") => Some(recv)
    @ast.TsExpr::IndexAccess(recv, @ast.TsExpr::StringLit("constructor")) =>
      Some(recv)
    _ => None
  }
}

///|
/// Classify the receiver of a `.name` read. Called from the read-property
/// walker; writes its answer as a sentinel key.
fn record_name_receiver(recv : @ast.TsExpr, out : Map[String, Bool]) -> Unit {
  match recv {
    // `C.name` — a plain identifier, so the class is named right here.
    // Whether `C` IS a constructor is decided by the CALLER, which has
    // the declaration table this walker does not: reserving every
    // identifier on the left of a `.name` read cost 282 KB (7.9%) on the
    // TypeScript compiler, which writes `node.name` / `symbol.name` /
    // `declaration.name` thousands of times and would have had its most
    // common locals frozen.
    @ast.TsExpr::Var(n) => out[NAME_OF_PREFIX + n] = true
    // `x.constructor.name` / `x["constructor"].name`, `this` included.
    @ast.TsExpr::PropAccess(_, "constructor") => out[NAME_OF_CTOR] = true
    @ast.TsExpr::IndexAccess(_, @ast.TsExpr::StringLit("constructor")) =>
      out[NAME_OF_CTOR] = true
    _ => ()
  }
}

///|
/// Top-level bindings that HAVE a meaningful `.name`: class declarations
/// and functions. `this.constructor` is always one of these, so this is
/// what the coarse branch reserves.
///
/// The first attempt reserved every top-level binding instead, and the
/// corpus priced it: typebox +70%, zod +40%, superstruct +31%. That is
/// not a default anyone would accept. Narrowing to constructors costs
/// only the names that could answer a `.constructor` lookup.
///
/// Missing a shape here is fail-open — a class that keeps no name and
/// gets renamed — so the arms below are the declaration forms the
/// bundler produces, and `NativeClassExpr` covers the lifted form the
/// class lowering emits.
pub fn constructor_like_top_level(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    match s {
      @ast.TsStmt::NativeClassStmt(decl, _) =>
        if decl.name != "" {
          out[decl.name] = true
        }
      @ast.TsStmt::Var(@ast.TsBinding::Ident(n), _, e)
      | @ast.TsStmt::Let(@ast.TsBinding::Ident(n), _, e)
      | @ast.TsStmt::Const(@ast.TsBinding::Ident(n), _, e) =>
        match e {
          @ast.TsExpr::NativeClassExpr(_, _) | @ast.TsExpr::FuncExpr(_) =>
            out[n] = true
          _ => ()
        }
      // `var a = …, b = …` and the class lift both nest one block deep.
      @ast.TsStmt::Block(inner) => constructor_like_top_level(inner, out)
      _ => ()
    }
  }
}

///|
/// Which classes can be on the other end of a `this.constructor.name`.
///
/// `this.constructor` inside a method of `C` is `C` or one of its
/// subclasses — never an unrelated class. So instead of reserving every
/// callable, find the classes whose own bodies read
/// `this.constructor.name` and close over their subclasses. superstruct's
/// `StructError` does it and has no subclasses, so the cost is one name.
///
/// `found_outside` is set when the read happens somewhere that is NOT a
/// top-level class body — a free function, an IIFE, an object literal's
/// method. `this` is unconstrained there, so the caller falls back to
/// reserving every callable. That fallback is what keeps this
/// fail-closed; the narrowing only applies where the class hierarchy
/// answers the question.
///
/// Each class body is measured with `collect_read_property_names_block`,
/// the same trusted walker the sentinel channel rides, so no new
/// traversal is introduced here either.
pub fn classes_observing_own_name(
  block : @ast.TsBlock,
) -> (Map[String, Bool], Bool) {
  let observing : Map[String, Bool] = {}
  // `subclass -> base`, to close over the hierarchy afterwards.
  let bases : Array[(String, Array[String])] = []
  let mut inside_class_total = 0
  fn class_reads_ctor_name(
    decl : @ast.TsClassDecl,
    ctor : @ast.TsFunc?,
  ) -> Bool {
    let seen : Map[String, Bool] = {}
    match decl.constructor_body {
      Some(b) => collect_read_property_names_block(b, seen)
      None => ()
    }
    match ctor {
      Some(f) => collect_read_property_names_block(f.body, seen)
      None => ()
    }
    for m in decl.methods {
      match m.body {
        Some(b) => collect_read_property_names_block(b, seen)
        None => ()
      }
    }
    seen.contains(NAME_OF_CTOR)
  }

  fn visit(decl : @ast.TsClassDecl, ctor : @ast.TsFunc?) -> Unit {
    if decl.name == "" {
      return
    }
    let base_list : Array[String] = []
    for b in decl.base_names {
      base_list.push(b)
    }
    bases.push((decl.name, base_list))
    if class_reads_ctor_name(decl, ctor) {
      observing[decl.name] = true
      inside_class_total = inside_class_total + 1
    }
  }

  for s in block.stmts {
    match s {
      @ast.TsStmt::NativeClassStmt(decl, ctor) => visit(decl, ctor)
      @ast.TsStmt::Var(@ast.TsBinding::Ident(_), _, e)
      | @ast.TsStmt::Let(@ast.TsBinding::Ident(_), _, e)
      | @ast.TsStmt::Const(@ast.TsBinding::Ident(_), _, e) =>
        match e {
          @ast.TsExpr::NativeClassExpr(decl, ctor) => visit(decl, ctor)
          _ => ()
        }
      _ => ()
    }
  }
  // Close over subclasses: a base that reads `this.constructor.name` has
  // it read through every class below it.
  let mut changed = true
  while changed {
    changed = false
    for entry in bases {
      if observing.contains(entry.0) {
        continue
      }
      for b in entry.1 {
        if observing.contains(b) {
          observing[entry.0] = true
          changed = true
          break
        }
      }
    }
  }
  // Did every `.constructor.name` in the bundle come from a class body we
  // accounted for? If the whole block mentions the sentinel but no class
  // body did, the read is somewhere `this` is unconstrained.
  let whole : Map[String, Bool] = {}
  collect_read_property_names_block(block, whole)
  let found_outside = whole.contains(NAME_OF_CTOR) && inside_class_total == 0
  (observing, found_outside)
}

///|
/// Is this one of the sentinel keys rather than a real property name?
pub fn is_name_observation_key(key : String) -> Bool {
  key.has_prefix(NAME_OF_PREFIX) ||
  key == NAME_OF_CTOR ||
  key.has_prefix(NAME_OF_CTOR_EQ_PREFIX)
}

///|
/// Every `.constructor.name` read in this block is compared against a
/// string literal and used for nothing else: return those literals.
///
/// `None` means at least one read is somewhere else, so the caller must
/// keep reserving every callable. That is decided by whether the trusted
/// walker produced `NAME_OF_CTOR` at all — the equality arm records the
/// literal sentinel INSTEAD of it, so an unaccounted read is exactly a
/// surviving `NAME_OF_CTOR`. Nothing here has to enumerate positions or
/// reconcile counts, which is the only reason it can be trusted: a
/// second walker's missed subtree would have failed OPEN.
///
/// What reserving the literals buys, precisely. The observation is a
/// boolean, and it changes only if the set of names reaching the site
/// gains or loses one of the compared literals. Reserving a literal
/// stops a class already called that from being renamed AND withholds
/// the name from the generated pool, so neither direction can flip.
///
/// The empty case is real and is the interesting one: a bundle that only
/// ever compares against `"Object"` reserves nothing at all, because no
/// bundle class is called `Object` and the mangler never invents that
/// name.
pub fn ctor_name_comparison_literals(block : @ast.TsBlock) -> Array[String]? {
  let read : Map[String, Bool] = {}
  collect_read_property_names_block(block, read)
  if read.contains(NAME_OF_CTOR) {
    return None
  }
  let lits : Array[String] = []
  for k in read.keys() {
    if k.has_prefix(NAME_OF_CTOR_EQ_PREFIX) {
      lits.push(k[NAME_OF_CTOR_EQ_PREFIX.length():].to_owned())
    }
  }
  if lits.is_empty() {
    return None
  }
  Some(lits)
}

///|
/// What `--mangle` must not rename because the bundle reads it back as a
/// `.name`.
///
/// `reserve_all` is set when the bundle reads `<expr>.constructor.name`
/// anywhere. There is no syntactic handle on which class that reaches —
/// a base class doing `this.constructor.name` is read through every
/// subclass — so the caller has to reserve every candidate.
pub fn observed_class_names(block : @ast.TsBlock) -> (Array[String], Bool) {
  let read : Map[String, Bool] = {}
  collect_read_property_names_block(block, read)
  // `.name` is never read at all: nothing to reserve, and the common
  // case pays one map lookup.
  if !read.contains("name") {
    return ([], false)
  }
  let mut reserve_all = false
  let names : Array[String] = []
  for k in read.keys() {
    if k == NAME_OF_CTOR {
      reserve_all = true
    } else if k.has_prefix(NAME_OF_PREFIX) {
      names.push(k[NAME_OF_PREFIX.length():].to_owned())
    }
  }
  (names, reserve_all)
}
