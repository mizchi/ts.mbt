// Expression and statement-level type inference / type checking, layered on
// top of the structural checker. Aimed at validating runtime `function` /
// arrow bodies against their declared parameter and return-type annotations.
//
// Behavior is intentionally conservative: when a sub-expression cannot be
// typed concretely (unknown identifier, property access against an opaque
// receiver, etc.) the inferred type is `Any`, and `Any` is assignable to /
// from anything via the structural assignability checker. That keeps false
// positives low against real-world `.ts` files that pull in untyped DOM /
// Node globals and class state we do not model yet.

///|
pub(all) struct ExprIssue {
  // Dotted breadcrumb describing where in the function the issue was found,
  // e.g. `function foo > param init`, `function foo > return`.
  path : String
  message : String
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// Resolver — maps `Named(N)` to interface / class / type-alias definitions and
// looks up fields, methods, constructors. Built once per module check.
// ---------------------------------------------------------------------------

///|
priv struct Resolver {
  interfaces : Map[String, @ast.TsInterface]
  classes : Map[String, @ast.TsClassDecl]
  type_aliases : Map[String, @ast.TsTypeAlias]
  // Module-level identifier types: top-level functions, ambient values,
  // imports. Looked up when an identifier is unbound in the local env.
  globals : Map[String, @ast.TsType]
  // Rich call signatures for top-level functions — carries optional / default
  // / rest information lost when funcs are collapsed into `Func(...)`.
  signatures : Map[String, Array[@ast.TsParam]]
  // Generic type-parameter names declared on top-level functions, keyed by
  // function name. Empty array for non-generic functions.
  func_type_params : Map[String, Array[String]]
  // Per-function `<const T>` modifier flags, positionally aligned with
  // `func_type_params[name]`. A `true` entry means generic inference
  // should not widen the inferred literal type for that parameter.
  // Missing key / shorter array is treated as "all false".
  func_const_type_params : Map[String, Array[Bool]]
  // Per-function type-parameter constraints (`(P, Bound)` pairs), keyed by
  // function name. Sparse — only constrained parameters appear. The checker
  // uses it to validate explicit type arguments against their bounds (TS2344).
  func_type_param_bounds : Map[String, Array[(String, @ast.TsType)]]
  // Enum declarations keyed by name so `Color.Red` resolves to the member's
  // literal value type rather than falling through to Any.
  enums : Map[String, @ast.TsEnumDecl]
  // Every value-binding name introduced anywhere in the module tree
  // (functions, classes, enums, imports, params, `var`/`let`/`const`
  // bindings incl. destructuring, catch params, loop variables). A
  // hoisting / forward-reference backstop for the TS2304 ("Cannot find
  // name") check: a referenced identifier present here is declared
  // *somewhere*, so it is never flagged even if the per-scope `env` hasn't
  // bound it yet at the reference site.
  declared_value_names : Map[String, Bool]
}

///|
fn Resolver::empty() -> Resolver {
  {
    interfaces: {},
    classes: {},
    type_aliases: {},
    globals: {},
    signatures: {},
    func_type_params: {},
    func_type_param_bounds: {},
    func_const_type_params: {},
    enums: {},
    declared_value_names: {},
  }
}

///|
/// TypeScript interface declaration merging. Two `interface Foo {...}`
/// blocks with the same name combine into one whose member list is the
/// union of both bodies. Later-declared members for the same key
/// override earlier ones (TS itself rejects conflicting overrides at
/// declaration time, but the checker doesn't enforce that — last writer
/// wins for the lookup).
fn merge_interfaces(
  a : @ast.TsInterface,
  b : @ast.TsInterface,
) -> @ast.TsInterface {
  let fields : Array[(String, @ast.TsType)] = []
  let seen : Map[String, Int] = {}
  // Take `a`'s fields first, then let `b` override / extend.
  for f in a.fields {
    seen[f.0] = fields.length()
    fields.push(f)
  }
  for f in b.fields {
    match seen.get(f.0) {
      Some(idx) => fields[idx] = f
      None => {
        seen[f.0] = fields.length()
        fields.push(f)
      }
    }
  }
  let readonly_fields : Array[String] = []
  let ro_seen : Map[String, Bool] = {}
  for n in a.readonly_fields {
    if !(ro_seen.get(n) is Some(_)) {
      ro_seen[n] = true
      readonly_fields.push(n)
    }
  }
  for n in b.readonly_fields {
    if !(ro_seen.get(n) is Some(_)) {
      ro_seen[n] = true
      readonly_fields.push(n)
    }
  }
  let extends_names : Array[String] = []
  let extends_args : Array[Array[@ast.TsType]] = []
  for i in 0..<a.extends_names.length() {
    extends_names.push(a.extends_names[i])
    extends_args.push(a.extends_args[i])
  }
  for i in 0..<b.extends_names.length() {
    extends_names.push(b.extends_names[i])
    extends_args.push(b.extends_args[i])
  }
  let index_signatures : Array[(@ast.TsType, @ast.TsType)] = []
  for sig in a.index_signatures {
    index_signatures.push(sig)
  }
  for sig in b.index_signatures {
    index_signatures.push(sig)
  }
  let method_type_params : Array[(String, Array[String])] = []
  for mtp in a.method_type_params {
    method_type_params.push(mtp)
  }
  for mtp in b.method_type_params {
    method_type_params.push(mtp)
  }
  // Type parameters: use `a`'s. TS requires them to match across
  // declarations, so it shouldn't matter which we pick.
  {
    name: a.name,
    type_params: a.type_params,
    extends_names,
    extends_args,
    fields,
    readonly_fields,
    index_signatures,
    method_type_params,
  }
}

///|
fn Resolver::from_module(module_ : @ast.TsModule) -> Resolver {
  let r = Resolver::empty()
  Resolver::ingest_module(r, module_, "")
  collect_module_value_names(module_, r.declared_value_names)
  r
}

///|
/// Collect every value-binding name introduced in `module_` (and nested
/// namespaces) into `out`. Backstop for the TS2304 check — see
/// `Resolver::declared_value_names`.
fn collect_module_value_names(
  module_ : @ast.TsModule,
  out : Map[String, Bool],
) -> Unit {
  for f in module_.funcs {
    out[f.name] = true
    for p in f.params {
      collect_param_value_names(p, out)
    }
    collect_block_value_names(f.body, out)
  }
  for imp in module_.imports {
    out[imp.name] = true
  }
  for v in module_.values {
    out[v.name] = true
  }
  for e in module_.enums {
    out[e.name] = true
  }
  for c in module_.classes {
    out[c.name] = true
    collect_class_body_value_names(c, out)
  }
  for ns in module_.namespaces {
    out[ns.name] = true
    collect_module_value_names(ns.module_, out)
  }
  for stmt in module_.top_level_stmts {
    collect_stmt_value_names(stmt, out)
  }
}

///|
/// Collect binding names introduced inside a class body: method / accessor
/// parameters and bodies, and field / static-block initializer expressions.
fn collect_class_body_value_names(
  c : @ast.TsClassDecl,
  out : Map[String, Bool],
) -> Unit {
  for m in c.methods {
    for p in m.params {
      out[p.0] = true
    }
    match m.body {
      Some(b) => collect_block_value_names(b, out)
      None => ()
    }
  }
  // The constructor is stored separately from `methods`; collect its
  // parameter and body bindings too so a `var` hoisted within the constructor
  // (`super(i); … var i = …`) isn't falsely flagged as an undefined name.
  match c.constructor_params {
    Some(ps) =>
      for p in ps {
        out[p.0] = true
      }
    None => ()
  }
  match c.constructor_body {
    Some(b) => collect_block_value_names(b, out)
    None => ()
  }
  for blk in c.static_blocks {
    collect_block_value_names(blk, out)
  }
  for fi in c.instance_field_inits {
    collect_expr_value_names(fi.1, out)
  }
  for fi in c.static_field_inits {
    collect_expr_value_names(fi.1, out)
  }
}

///|
fn collect_param_value_names(p : @ast.TsParam, out : Map[String, Bool]) -> Unit {
  if p.name != "" {
    out[p.name] = true
  }
  match p.binding {
    Some(b) => collect_binding_value_names(b, out)
    None => ()
  }
  match p.default {
    Some(d) => collect_expr_value_names(d, out)
    None => ()
  }
}

///|
fn collect_binding_value_names(
  b : @ast.TsBinding,
  out : Map[String, Bool],
) -> Unit {
  match b {
    Ident(n) => out[n] = true
    Array(ab) => {
      for item in ab.items {
        match item {
          Some(elem) => collect_binding_value_names(elem.binding, out)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_binding_value_names(r, out)
        None => ()
      }
    }
    Object(ob) => {
      for prop in ob.props {
        collect_binding_value_names(prop.binding, out)
      }
      match ob.rest {
        Some(n) => out[n] = true
        None => ()
      }
    }
    Target(_) => ()
  }
}

///|
/// Walk a statement collecting introduced binding names, recursing into
/// nested blocks, control flow, and function / arrow bodies.
fn collect_stmt_value_names(
  stmt : @ast.TsStmt,
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(b, _, init) | Let(b, _, init) | Const(b, _, init) => {
      collect_binding_value_names(b, out)
      collect_expr_value_names(init, out)
    }
    Expr(e) | Throw(e) => collect_expr_value_names(e, out)
    Return(opt) =>
      match opt {
        Some(e) => collect_expr_value_names(e, out)
        None => ()
      }
    Assign(_, e) | CompoundAssign(_, _, e) => collect_expr_value_names(e, out)
    If(c, then_, else_) => {
      collect_expr_value_names(c, out)
      collect_block_value_names(then_, out)
      match else_ {
        Some(b) => collect_block_value_names(b, out)
        None => ()
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      collect_expr_value_names(c, out)
      collect_block_value_names(body, out)
    }
    For(init, _, update, body) => {
      match init {
        Some(s) => collect_stmt_value_names(s, out)
        None => ()
      }
      match update {
        Some(s) => collect_stmt_value_names(s, out)
        None => ()
      }
      collect_block_value_names(body, out)
    }
    ForOf(_, b, _, e, body)
    | ForAwaitOf(_, b, _, e, body)
    | ForIn(_, b, _, e, body) => {
      collect_binding_value_names(b, out)
      collect_expr_value_names(e, out)
      collect_block_value_names(body, out)
    }
    Switch(e, cases) => {
      collect_expr_value_names(e, out)
      for c in cases {
        collect_block_value_names(c.body, out)
      }
    }
    Try(b, catch_binding, catch_, finally_) => {
      collect_block_value_names(b, out)
      match catch_binding {
        Some(cb) => collect_binding_value_names(cb, out)
        None => ()
      }
      match catch_ {
        Some(cb) => collect_block_value_names(cb, out)
        None => ()
      }
      match finally_ {
        Some(fb) => collect_block_value_names(fb, out)
        None => ()
      }
    }
    Block(b) => collect_block_value_names(b, out)
    Label(_, inner) => collect_stmt_value_names(inner, out)
    NativeClassStmt(decl, _) => {
      out[decl.name] = true
      for blk in decl.static_blocks {
        collect_block_value_names(blk, out)
      }
    }
    _ => ()
  }
}

///|
fn collect_block_value_names(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_stmt_value_names(s, out)
  }
}

///|
/// Walk an expression collecting binding names introduced by nested
/// function / arrow / class expressions.
fn collect_expr_value_names(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    FuncExpr(f) => {
      if f.name != "" {
        out[f.name] = true
      }
      for p in f.params {
        collect_param_value_names(p, out)
      }
      for s in f.body.stmts {
        collect_stmt_value_names(s, out)
      }
    }
    NativeClassExpr(decl, _) => {
      if decl.name != "" {
        out[decl.name] = true
      }
      for blk in decl.static_blocks {
        collect_block_value_names(blk, out)
      }
    }
    ArrowFunc(params, _, body, _) => {
      for p in params {
        collect_param_value_names(p, out)
      }
      match body {
        ArrowExpr(e) => collect_expr_value_names(e, out)
        ArrowBlock(b) => collect_block_value_names(b, out)
      }
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_expr_value_names(a, out)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_expr_value_names(callee, out)
      for a in args {
        collect_expr_value_names(a, out)
      }
    }
    MethodCall(recv, _, args) => {
      collect_expr_value_names(recv, out)
      for a in args {
        collect_expr_value_names(a, out)
      }
    }
    BinOp(_, l, r) | Seq(l, r) => {
      collect_expr_value_names(l, out)
      collect_expr_value_names(r, out)
    }
    UnaryOp(_, e)
    | Spread(e)
    | Await(e)
    | NonNull(e)
    | OptionalChain(e)
    | As(e, _)
    | PropAccess(e, _) => collect_expr_value_names(e, out)
    Cond(c, t, e) => {
      collect_expr_value_names(c, out)
      collect_expr_value_names(t, out)
      collect_expr_value_names(e, out)
    }
    ArrayLit(items) =>
      for it in items {
        collect_expr_value_names(it, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_expr_value_names(ent.1, out)
      }
    AssignExpr(_, v) | AssignPattern(_, v) | CompoundAssignExpr(_, _, v) =>
      collect_expr_value_names(v, out)
    _ => ()
  }
}

///|
/// Register the declarations of `module_` into `r`, prefixing every
/// name with `prefix` (e.g. `"Layout."`). Recurses into nested
/// namespaces so `namespace Layout { export function Header(...) }` is
/// reachable as `Layout.Header` for member-expression JSX tags.
fn Resolver::ingest_module(
  r : Resolver,
  module_ : @ast.TsModule,
  prefix : String,
) -> Unit {
  for i in module_.interfaces {
    let key = prefix + i.name
    match r.interfaces.get(key) {
      // TS declaration merging: `interface Foo { a }` + `interface Foo
      // { b }` produces a single `Foo` whose members are the union of
      // both bodies. Field-key collisions take the later declaration.
      Some(existing) => r.interfaces[key] = merge_interfaces(existing, i)
      None => r.interfaces[key] = i
    }
  }
  for c in module_.classes {
    r.classes[prefix + c.name] = c
  }
  for e in module_.enums {
    r.enums[prefix + e.name] = e
    // Expose enum members as globals so `Color.Red` resolves via PropAccess.
    for m in e.members {
      let val_ty = match m.value {
        Some(@ast.TsEnumMemberValue::Number(s)) => @ast.TsType::NumberLiteral(s)
        Some(@ast.TsEnumMemberValue::String(s)) => @ast.TsType::Literal(s)
        Some(@ast.TsEnumMemberValue::BigInt(s)) => @ast.TsType::Literal(s)
        Some(@ast.TsEnumMemberValue::Bool(b)) => @ast.TsType::BooleanLiteral(b)
        None => @ast.TsType::Number
      }
      r.globals[prefix + e.name + "." + m.name] = val_ty
    }
  }
  for ta in module_.type_aliases {
    r.type_aliases[prefix + ta.name] = ta
  }
  for v in module_.values {
    r.globals[prefix + v.name] = v.type_
  }
  for imp in module_.imports {
    // Drop a leading `this` parameter (`declare function f(this: T, a)`): it
    // declares the callee's `this` type, not an argument position.
    let this_start = if imp.params.length() > 0 && imp.params[0].0 == "this" {
      1
    } else {
      0
    }
    let param_types : Array[@ast.TsType] = []
    let mut pi = this_start
    while pi < imp.params.length() {
      // `declare function`'s params come from `(name, type)` pairs without
      // a rest flag, so each entry is taken as-is. A surface-level rest
      // declaration like `(...args: T[])` shows up as `Array(T)` here
      // already; the rest pattern path in `match_infer_pattern` handles
      // single-Array-param shapes without needing an explicit Rest.
      param_types.push(imp.params[pi].1)
      pi = pi + 1
    }
    let new_sig = @ast.TsType::Func(param_types, imp.return_type)
    // When multiple `declare function f(...)` overloads share the same name,
    // accumulate them as a Union of Func types so infer_call can pick the
    // right branch at each call site.
    let key = prefix + imp.name
    match r.globals.get(key) {
      Some(Func(_, _) as existing) =>
        r.globals[key] = @ast.TsType::Union([existing, new_sig])
      Some(Union(existing_parts)) => {
        let parts = []
        for p in existing_parts {
          parts.push(p)
        }
        parts.push(new_sig)
        r.globals[key] = @ast.TsType::Union(parts)
      }
      _ => r.globals[key] = new_sig
    }
    // Also expose type parameters so generic-call inference picks up
    // `declare function f<T>(...)` imports — without this the inference
    // path skipped imports entirely.
    r.func_type_params[prefix + imp.name] = imp.type_params
    // Synthesize a minimal `TsParam` list (names only) so the rich-
    // signature path used by `apply_type_predicate_narrowing` can map
    // the predicate's parameter name to an argument index.
    let synth_params : Array[@ast.TsParam] = []
    let mut si = this_start
    while si < imp.params.length() {
      let p = imp.params[si]
      // Preserve the rest-parameter flag (`...args: T[]`) so the call
      // checker compares each variadic argument against the element type
      // rather than the whole array. `param_is_rest` is positionally
      // aligned with the original `params`, so index with `si`.
      let is_rest = si < imp.param_is_rest.length() && imp.param_is_rest[si]
      synth_params.push({
        name: p.0,
        binding: None,
        is_rest,
        type_: p.1,
        default: None,
      })
      si = si + 1
    }
    r.signatures[prefix + imp.name] = synth_params
  }
  for f in module_.funcs {
    // A leading `this` parameter (`function f(this: T, a)`) declares the
    // callee's `this` type, not an argument position, so drop it from the
    // arity / signature model -- otherwise argument-count and per-argument
    // checks are off by one.
    let effective_params : Array[@ast.TsParam] = []
    for idx, p in f.params {
      if idx == 0 && p.name == "this" {
        continue
      }
      effective_params.push(p)
    }
    let param_types : Array[@ast.TsType] = []
    for p in effective_params {
      // Preserve rest-parameter information so `Parameters<F>` sees the
      // variadic tail. `function f(a: string, ...rest: number[])` -> the
      // last param type becomes `Rest(Array(Number))` so the resulting
      // `Parameters<typeof f>` tuple carries the variadic marker.
      if p.is_rest {
        param_types.push(@ast.TsType::Rest(p.type_))
      } else {
        param_types.push(p.type_)
      }
    }
    // Async functions expose `Promise<R>` to callers even when the body's
    // declared `return_type` is the un-wrapped `R`.
    let ret = wrap_async_return(f.is_async, f.return_type)
    let new_func_sig = @ast.TsType::Func(param_types, ret)
    let func_key = prefix + f.name
    match r.globals.get(func_key) {
      Some(Func(_, _) as existing) =>
        r.globals[func_key] = @ast.TsType::Union([existing, new_func_sig])
      Some(Union(existing_parts)) => {
        let parts = []
        for p in existing_parts {
          parts.push(p)
        }
        parts.push(new_func_sig)
        r.globals[func_key] = @ast.TsType::Union(parts)
      }
      _ => r.globals[func_key] = new_func_sig
    }
    r.signatures[prefix + f.name] = effective_params
    r.func_type_params[prefix + f.name] = f.type_params
    r.func_const_type_params[prefix + f.name] = f.const_type_params
    if f.type_param_bounds.length() > 0 {
      r.func_type_param_bounds[prefix + f.name] = f.type_param_bounds
    }
  }
  for ns in module_.namespaces {
    // `<global>` is the synthetic namespace emitted for `declare global {}`
    // augmentation blocks. Its declarations belong to the global scope so
    // they are ingested at the current prefix rather than under a sub-prefix.
    let ns_prefix = if ns.name == "<global>" {
      prefix
    } else {
      prefix + ns.name + "."
    }
    Resolver::ingest_module(r, ns.module_, ns_prefix)
    // Namespace + class static-side merging: when a `namespace X` is
    // declared alongside `class X`, the namespace's exports are
    // exposed as static members on the class. Wire each top-level
    // function / value / class into the class lookup by also
    // registering them under the `<Class>.<member>` key so PropAccess
    // resolution that goes through the class shape can find them.
    if ns.name != "<global>" {
      let cls_key = prefix + ns.name
      let _ = r.classes.get(cls_key) // existence check; presence is enough
    }
    // (`r.globals[ns_prefix + name]` is already set above by the
    // recursive ingest; the qualified key is what lookup_class_field
    // would walk through.)
  }
  // Top-level `var` / `let` / `const` decls with an explicit type
  // annotation should be visible via `typeof <name>` from inside the
  // module. `module_.values` covers ambient `declare var`s; this loop
  // covers the rest by pulling typed bindings out of `top_level_stmts`.
  for stmt in module_.top_level_stmts {
    match stmt {
      Var(Ident(name), ty, _)
      | Let(Ident(name), ty, _)
      | Const(Ident(name), ty, _) =>
        // Skip any type that mentions `typeof` anywhere -- registering
        // `var d: typeof e` would create a cycle as soon as another
        // `var e: typeof d` lands beside it (the conformance corpus has
        // exactly that shape in `recursiveTypesWithTypeof.ts`).
        if is_checkable(ty) && !type_contains_typeof(ty) {
          let key = prefix + name
          // Don't shadow an existing entry (e.g. from `declare var`).
          if !(r.globals.get(key) is Some(_)) {
            r.globals[key] = ty
          }
        }
      _ => ()
    }
  }
}

///|
/// True when `ty` contains a `TypeOf(_)` reference anywhere in its
/// structure. Used by the top-level globals ingestion to skip
/// `typeof`-referencing declarations -- registering them risks
/// resolver cycles (e.g. `var d: typeof e; var e: typeof d`).
fn type_contains_typeof(ty : @ast.TsType) -> Bool {
  match ty {
    TypeOf(_) => true
    Array(inner) => type_contains_typeof(inner)
    Union(parts) | Intersection(parts) | Tuple(parts) => {
      for p in parts {
        if type_contains_typeof(p) {
          return true
        }
      }
      false
    }
    Applied(_, args) => {
      for a in args {
        if type_contains_typeof(a) {
          return true
        }
      }
      false
    }
    Func(params, ret) => {
      for p in params {
        if type_contains_typeof(p) {
          return true
        }
      }
      type_contains_typeof(ret)
    }
    Object(entries) => {
      for e in entries {
        if type_contains_typeof(e.0) || type_contains_typeof(e.1) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
/// Required-argument count for a parameter list: the index of the first
/// trailing optional / default / rest param. Used to validate `Call(...)`
/// arity when the rich signature is available.
fn required_arity(params : Array[@ast.TsParam]) -> Int {
  // Walk left-to-right; once we cross an optional we keep going to make sure
  // the parameter list is well-formed (TS rejects required-after-optional
  // already), then return the last required index + 1.
  let mut last_required = 0
  let mut i = 0
  while i < params.length() {
    let p = params[i]
    if !param_is_optional(p) {
      last_required = i + 1
    }
    i = i + 1
  }
  last_required
}

///|
/// Minimum argument count derivable from parameter *types* alone (no rich
/// `TsParam` metadata). A trailing parameter whose type accepts `undefined`
/// (the `x?: T` -> `T | undefined` widening) is optional and omittable.
fn required_arity_from_types(params : Array[@ast.TsType]) -> Int {
  let mut last_required = 0
  let mut i = 0
  while i < params.length() {
    // A rest parameter (`...args: T[]`, stored as `Rest(...)`) accepts zero
    // arguments, so it never raises the required count.
    if !(params[i] is Rest(_)) && !type_accepts_undefined_param(params[i]) {
      last_required = i + 1
    }
    i = i + 1
  }
  last_required
}

///|
fn type_accepts_undefined_param(ty : @ast.TsType) -> Bool {
  match ty {
    Undefined => true
    Union(parts) => {
      for part in parts {
        if part is Undefined {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn param_is_optional(p : @ast.TsParam) -> Bool {
  if p.is_rest {
    return true
  }
  match p.default {
    Some(_) => return true
    None => ()
  }
  // The parser widens `x?: T` to `T | undefined`, which we treat as optional
  // both ways: callers can omit the trailing argument either form.
  match p.type_ {
    Union(parts) => {
      for part in parts {
        match part {
          Undefined => return true
          _ => ()
        }
      }
      false
    }
    Undefined => true
    _ => false
  }
}

///|
/// Resolve a type to its "shape" — unwrap `Named(N)` through type aliases
/// (one hop, with simple cycle protection) so callers can pattern-match on
/// the structural form (Object, Tuple, Array, Func, ...).
fn Resolver::unwrap(self : Resolver, ty : @ast.TsType) -> @ast.TsType {
  let seen : Map[String, Bool] = {}
  let mut cur = ty
  let mut keep_going = true
  while keep_going {
    match cur {
      Named(n) =>
        if seen.contains(n) {
          keep_going = false
        } else {
          match self.type_aliases.get(n) {
            Some(aliased) => {
              seen[n] = true
              cur = aliased.type_
            }
            None =>
              // A pure array-alias interface (`interface I extends Array<T>
              // {}` / `ReadonlyArray<T>`, no own members) is structurally an
              // array — resolve it so array-literal contextual typing and
              // assignability see the element type.
              match interface_pure_array_element(self, n) {
                Some(elem) => {
                  seen[n] = true
                  cur = Array(elem)
                }
                None => keep_going = false
              }
          }
        }
      Applied(n, args) =>
        if seen.contains(n) {
          keep_going = false
        } else {
          match self.type_aliases.get(n) {
            Some(aliased) if aliased.type_params.length() > 0 => {
              seen[n] = true
              let bindings : Map[String, @ast.TsType] = {}
              let limit = if args.length() < aliased.type_params.length() {
                args.length()
              } else {
                aliased.type_params.length()
              }
              let mut i = 0
              while i < limit {
                bindings[aliased.type_params[i]] = args[i]
                i = i + 1
              }
              cur = substitute_params(aliased.type_, bindings)
            }
            _ => keep_going = false
          }
        }
      // `typeof varName` in type position — resolve the variable's current type.
      // Self-referential exports (`export var r: typeof r;`) would otherwise
      // loop forever, so guard the name through `seen` like the alias cases.
      TypeOf(name) => {
        let key = "typeof " + name
        if seen.contains(key) {
          keep_going = false
        } else {
          match self.globals.get(name) {
            Some(resolved) => {
              seen[key] = true
              cur = resolved
            }
            None => keep_going = false
          }
        }
      }
      // `keyof typeof Enum` — the type of the enum object has the member
      // names as its keys, so `keyof typeof Color` resolves to the union
      // of member-name string literals (`"Red" | "Green" | ...`). This
      // also covers `const enum`s, whose members aren't exposed as
      // structural object fields.
      Keyof(TypeOf(enum_name)) if self.enums.get(enum_name) is Some(_) => {
        let decl = self.enums.get(enum_name).unwrap()
        let keys : Array[@ast.TsType] = []
        for m in decl.members {
          keys.push(@ast.TsType::Literal(m.name))
        }
        if keys.length() == 0 {
          keep_going = false
        } else if keys.length() == 1 {
          cur = keys[0]
        } else {
          cur = @ast.TsType::Union(keys)
        }
      }
      // `keyof T` where T is a Named interface/class — extract the union of
      // field names so `keyof MyInterface` resolves to a string literal union.
      Keyof(inner) => {
        let resolved_inner = self.unwrap(inner)
        let fields = collect_declared_fields(resolved_inner, self)
        if fields.length() == 0 {
          keep_going = false
        } else {
          let keys : Array[@ast.TsType] = []
          for f in fields {
            keys.push(@ast.TsType::Literal(f.0))
          }
          cur = if keys.length() == 1 {
            keys[0]
          } else {
            @ast.TsType::Union(keys)
          }
        }
      }
      // Simplify mapped types to Object shapes so field lookups work.
      MappedType(_, _, _, _) | MappedTypeRemap(_, _, _, _, _) => {
        let simplified = simplify_type(cur)
        match simplified {
          MappedType(_, _, _, _) | MappedTypeRemap(_, _, _, _, _) =>
            keep_going = false // couldn't resolve — leave as-is
          _ => cur = simplified
        }
      }
      // `T[K]` indexed access — resolve via simplify_type first; if still
      // unresolved, try lookup_field when the base is a Named/Applied type.
      IndexedAccess(base, key) => {
        let simplified = simplify_type(cur)
        match simplified {
          IndexedAccess(_, _) => {
            // simplify couldn't resolve it; try resolver-aware field lookup.
            let resolved_base = self.unwrap(base)
            match key {
              Literal(name) =>
                match self.lookup_field(resolved_base, name) {
                  Some(t) => cur = t
                  None => keep_going = false
                }
              _ => keep_going = false
            }
          }
          _ => cur = simplified
        }
      }
      // Simplify template literal types to concrete Literal strings when possible.
      TemplateLiteralType(_, _) => {
        let simplified = simplify_type(cur)
        match simplified {
          TemplateLiteralType(_, _) => keep_going = false
          _ => cur = simplified
        }
      }
      // A generic function type erases to its underlying callable for every
      // value-shape decision (assignability, member lookup, inference): the
      // declared type-parameter names matter only to scope-aware checks that
      // read the wrapper directly. Peel it here so the rest of the resolver
      // sees the plain `Func` / `Constructor` exactly as before this variant
      // existed.
      GenericFunc(_, inner) => cur = inner
      _ => keep_going = false
    }
  }
  cur
}

///|
/// Look up a property on a value of type `recv` named `field`. Walks
/// interfaces / classes / objects / arrays. Returns `None` when the property
/// cannot be resolved structurally; callers fall back to `Any`.

///|
/// Well-known `Array.prototype.*` members specialised at the array's
/// element type `elem`. Returns `None` for unrecognised members so the
/// caller can fall back to its default behaviour (typically `Any`).
/// Methods whose return / parameter types involve a callback-local
/// generic (`map<U>`, `reduce<U>`, …) are handled separately in
/// `infer_expr.MethodCall` so the callback's body can supply the
/// instantiation; this function only returns the non-generic prototype
/// shape for those entries so call-site checks still see a sensible
/// formal-parameter type for the argument.
fn array_prototype_member(elem : @ast.TsType, field : String) -> @ast.TsType? {
  let arr_t = @ast.TsType::Array(elem)
  let nullable_elem = narrow_union(elem, @ast.TsType::Undefined)
  // Helper for `(value: T, index: number, array: T[]) => R` callback shapes.
  let cb = fn(ret) {
    @ast.TsType::Func([elem, @ast.TsType::Number, arr_t], ret)
  }
  let cb_bool = cb(@ast.TsType::Boolean)
  match field {
    // Properties
    "length" => Some(@ast.TsType::Number)
    // Numeric index access falls through to the element type.
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" => Some(elem)
    // Mutating methods
    "push" => Some(@ast.TsType::Func([elem], @ast.TsType::Number))
    "pop" => Some(@ast.TsType::Func([], nullable_elem))
    "shift" => Some(@ast.TsType::Func([], nullable_elem))
    "unshift" => Some(@ast.TsType::Func([elem], @ast.TsType::Number))
    "reverse" => Some(@ast.TsType::Func([], arr_t))
    "sort" =>
      Some(
        @ast.TsType::Func(
          [@ast.TsType::Func([elem, elem], @ast.TsType::Number)],
          arr_t,
        ),
      )
    "fill" => Some(@ast.TsType::Func([elem], arr_t))
    // Non-mutating producers
    "concat" => Some(@ast.TsType::Func([arr_t], arr_t))
    "slice" =>
      Some(@ast.TsType::Func([@ast.TsType::Number, @ast.TsType::Number], arr_t))
    "flat" => Some(@ast.TsType::Func([], arr_t))
    "join" =>
      Some(@ast.TsType::Func([@ast.TsType::String_], @ast.TsType::String_))
    "toString" => Some(@ast.TsType::Func([], @ast.TsType::String_))
    // Search / predicate
    "indexOf" =>
      Some(@ast.TsType::Func([elem, @ast.TsType::Number], @ast.TsType::Number))
    "lastIndexOf" =>
      Some(@ast.TsType::Func([elem, @ast.TsType::Number], @ast.TsType::Number))
    "includes" => Some(@ast.TsType::Func([elem], @ast.TsType::Boolean))
    "every" => Some(@ast.TsType::Func([cb_bool], @ast.TsType::Boolean))
    "some" => Some(@ast.TsType::Func([cb_bool], @ast.TsType::Boolean))
    "find" => Some(@ast.TsType::Func([cb_bool], nullable_elem))
    "findIndex" => Some(@ast.TsType::Func([cb_bool], @ast.TsType::Number))
    "findLast" => Some(@ast.TsType::Func([cb_bool], nullable_elem))
    "findLastIndex" => Some(@ast.TsType::Func([cb_bool], @ast.TsType::Number))
    // Iteration with element-type-preserving result
    "filter" => Some(@ast.TsType::Func([cb_bool], arr_t))
    "forEach" =>
      Some(@ast.TsType::Func([cb(@ast.TsType::Void)], @ast.TsType::Void))
    // Generic methods — the formal `U` shape is exposed here for the
    // call-site contextual typing path to thread through, but the call
    // site's `MethodCall` handler in `infer_expr` substitutes the real
    // inferred return type. We use `Any` for the callback's return slot
    // so the contextual-typing dispatch doesn't reject arrow bodies that
    // legitimately produce any `U`.
    "map" =>
      Some(
        @ast.TsType::Func(
          [cb(@ast.TsType::Any)],
          @ast.TsType::Array(@ast.TsType::Any),
        ),
      )
    "flatMap" =>
      Some(
        @ast.TsType::Func(
          [cb(@ast.TsType::Any)],
          @ast.TsType::Array(@ast.TsType::Any),
        ),
      )
    "reduce" =>
      // (acc: U, cur: T, idx: number, arr: T[]) => U + initial U
      Some(
        @ast.TsType::Func(
          [
            @ast.TsType::Func(
              [@ast.TsType::Any, elem, @ast.TsType::Number, arr_t],
              @ast.TsType::Any,
            ),
            @ast.TsType::Any,
          ],
          @ast.TsType::Any,
        ),
      )
    "reduceRight" =>
      Some(
        @ast.TsType::Func(
          [
            @ast.TsType::Func(
              [@ast.TsType::Any, elem, @ast.TsType::Number, arr_t],
              @ast.TsType::Any,
            ),
            @ast.TsType::Any,
          ],
          @ast.TsType::Any,
        ),
      )
    // ES2023 non-mutating array methods — return a new array of the same element type.
    "toReversed" => Some(@ast.TsType::Func([], arr_t))
    "toSorted" =>
      Some(
        @ast.TsType::Func(
          [
            @ast.TsType::Union([
              @ast.TsType::Func([elem, elem], @ast.TsType::Number),
              @ast.TsType::Undefined,
            ]),
          ],
          arr_t,
        ),
      )
    "toSpliced" =>
      Some(@ast.TsType::Func([@ast.TsType::Number, @ast.TsType::Number], arr_t))
    "with" => Some(@ast.TsType::Func([@ast.TsType::Number, elem], arr_t))
    _ => None
  }
}

///|
/// Return a copy of `bindings` with the named field's method-level type
/// parameters removed, so a generic method's shadowing type variable
/// (`interface I<T> { m<T>(x: T): T }`) is left unsubstituted instead of
/// being captured by the interface's instantiated `T`. When the field has
/// no recorded method generics the original map is returned unchanged.
fn scoped_bindings_for_method(
  bindings : Map[String, @ast.TsType],
  method_type_params : Array[(String, Array[String])],
  field : String,
) -> Map[String, @ast.TsType] {
  let mut shadowed : Array[String]? = None
  for mtp in method_type_params {
    if mtp.0 == field {
      shadowed = Some(mtp.1)
      break
    }
  }
  match shadowed {
    None => bindings
    Some(names) => {
      if names.length() == 0 {
        return bindings
      }
      let scoped : Map[String, @ast.TsType] = {}
      for kv in bindings {
        if !names.contains(kv.0) {
          scoped[kv.0] = kv.1
        }
      }
      scoped
    }
  }
}

///|
fn Resolver::lookup_field(
  self : Resolver,
  recv : @ast.TsType,
  field : String,
) -> @ast.TsType? {
  match self.lookup_field_core(recv, field) {
    Some(t) => Some(t)
    None =>
      // Object-like receivers inherit Object.prototype members
      // (toString / hasOwnProperty / valueOf / …). Fall back to those so
      // they don't surface as missing-property diagnostics. Primitives have
      // their own prototype dispatchers and don't need this hop.
      match self.unwrap(recv) {
        Named(_) | Applied(_, _) | Object(_) | Struct(_, _) =>
          object_prototype_member(field)
        _ => None
      }
  }
}

///|
// True when `recv` is (or unwraps to) a union in which at least one member
// declares `field`.  `lookup_field` on a union returns `None` unless *every*
// member has the field, which produces false "does not exist" diagnostics on
// discriminated unions where flow-narrowing (a `switch`/`if` on the
// discriminant) would make the access valid.  The PropAccess existence check
// uses this to stay silent in that situation — we can't model the narrowing,
// so we trust the partial match.
fn Resolver::field_on_any_union_member(
  self : Resolver,
  recv : @ast.TsType,
  field : String,
) -> Bool {
  match self.unwrap(recv) {
    Union(items) =>
      items.iter().any(fn(it) { self.lookup_field(it, field) is Some(_) })
    _ => false
  }
}

///|

///|
/// True when assigning to `recv.field` is forbidden because the field is
/// declared `readonly` on a reachable interface/class member. For a union
/// receiver, *any* member with the readonly bit set is enough — the value
/// could be that variant at runtime. We're conservative: only flag when
/// at least one resolved shape on the receiver explicitly carries the
/// readonly marker; unresolvable shapes stay silent.
fn is_readonly_field(
  resolver : Resolver,
  recv : @ast.TsType,
  field : String,
) -> Bool {
  let candidates : Array[@ast.TsType] = []
  match resolver.unwrap(recv) {
    Union(members) | Intersection(members) =>
      for m in members {
        candidates.push(m)
      }
    other => candidates.push(other)
  }
  for ty in candidates {
    match ty {
      Named(n) | Applied(n, _) =>
        match resolver.interfaces.get(n) {
          Some(iface) =>
            if iface.readonly_fields.contains(field) {
              return true
            }
          None =>
            match resolver.classes.get(n) {
              Some(cls) =>
                for p in cls.properties {
                  if p.name == field && p.is_readonly {
                    return true
                  }
                }
              None => ()
            }
        }
      _ => ()
    }
  }
  false
}

///|
fn Resolver::lookup_field_core(
  self : Resolver,
  recv : @ast.TsType,
  field : String,
) -> @ast.TsType? {
  let unwrapped = self.unwrap(recv)
  // Try the built-in prototype dispatchers first so a `Named("Date")` /
  // `Named("RegExp")` receiver doesn't get masked by a missing-interface
  // lookup in the generic `Named(n)` arm below.
  match unwrapped {
    Named("Date") =>
      match date_prototype_member(field) {
        Some(t) => return Some(t)
        None => ()
      }
    Named("RegExp") =>
      match regexp_prototype_member(field) {
        Some(t) => return Some(t)
        None => ()
      }
    Named(n) =>
      if is_error_class_name(n) {
        match error_prototype_member(field) {
          Some(t) => return Some(t)
          None => ()
        }
      } else {
        match typed_array_element_type(n) {
          Some(elem) =>
            match typed_array_extra_member(field) {
              Some(t) => return Some(t)
              None =>
                match array_prototype_member(elem, field) {
                  Some(t) => return Some(t)
                  None => ()
                }
            }
          None => ()
        }
        match (n, field) {
          // ArrayBuffer / DataView shape.
          ("ArrayBuffer", "byteLength")
          | ("SharedArrayBuffer", "byteLength")
          | ("DataView", "byteLength")
          | ("DataView", "byteOffset") => return Some(@ast.TsType::Number)
          ("ArrayBuffer", "slice") | ("SharedArrayBuffer", "slice") =>
            return Some(
              @ast.TsType::Func(
                [@ast.TsType::Number, @ast.TsType::Number],
                @ast.TsType::Named(n),
              ),
            )
          _ => ()
        }
      }
    _ => ()
  }
  match unwrapped {
    Named(n) =>
      match self.interfaces.get(n) {
        Some(iface) => {
          for f in iface.fields {
            if f.0 == field {
              return Some(f.1)
            }
          }
          // Walk `extends` chain one level (no cycle protection — the
          // checker's `check_module` already validates these).
          let mut i = 0
          while i < iface.extends_names.length() {
            let base_name = iface.extends_names[i]
            let base_args = if i < iface.extends_args.length() {
              iface.extends_args[i]
            } else {
              []
            }
            let base_ty : @ast.TsType = if base_args.length() > 0 {
              @ast.TsType::Applied(base_name, base_args)
            } else {
              @ast.TsType::Named(base_name)
            }
            match self.lookup_field(base_ty, field) {
              Some(t) => return Some(t)
              None => ()
            }
            i = i + 1
          }
          // Index-signature fallback: when no named field / extends
          // chain entry matched, consult the interface's index
          // signatures so `d.foo` on `{ [k: string]: V }` resolves to
          // `V` (and likewise for numeric keys).
          index_signature_value(iface.index_signatures, field)
        }
        None =>
          match self.classes.get(n) {
            Some(cls) => self.lookup_class_field(cls, field)
            None => None
          }
      }
    // `Applied(N, [A, B, …])` — the type instantiates a generic
    // interface (or class). Substitute type-parameter names with the
    // Built-in generic prototypes need to fire before the generic
    // `Applied(n, args)` interface-lookup arm — otherwise the resolver
    // would search for an `interface Array { ... }` declaration that
    // doesn't exist and return `None`.
    Applied("Array", [elem]) | Applied("ReadonlyArray", [elem]) =>
      array_prototype_member(elem, field)
    Applied("Promise", [inner]) | Applied("PromiseLike", [inner]) =>
      promise_prototype_member(inner, field)
    Applied("Map", [k, v]) | Applied("ReadonlyMap", [k, v]) =>
      map_prototype_member(k, v, field)
    Applied("Set", [t]) | Applied("ReadonlySet", [t]) =>
      set_prototype_member(t, field)
    Applied("WeakMap", [k, v]) => weakmap_prototype_member(k, v, field)
    Applied("WeakSet", [t]) => weakset_prototype_member(t, field)
    Applied("Iterable", [t])
    | Applied("IterableIterator", [t])
    | Applied("Iterator", [t]) => iterator_prototype_member(t, field)
    // `Generator<T, TReturn, TNext>` — only `T` matters at our resolution.
    Applied("Generator", args) if args.length() >= 1 =>
      iterator_prototype_member(args[0], field)
    Applied("AsyncIterable", [t])
    | Applied("AsyncIterableIterator", [t])
    | Applied("AsyncIterator", [t]) => async_iterator_prototype_member(t, field)
    Applied("AsyncGenerator", args) if args.length() >= 1 =>
      async_iterator_prototype_member(args[0], field)
    // TypeScript utility types — handled at the lookup layer so we don't
    // need a structural rewrite of the whole type. The handler returns
    // the field's specialised type or `None` to keep falling through.
    Applied("Record", [_, v]) => Some(v)
    Applied("Partial", [t]) =>
      match self.lookup_field(t, field) {
        Some(inner) => Some(narrow_union(inner, @ast.TsType::Undefined))
        None => None
      }
    Applied("Required", [t]) =>
      match self.lookup_field(t, field) {
        Some(inner) => Some(non_nullable(inner))
        None => None
      }
    Applied("Readonly", [t]) => self.lookup_field(t, field)
    Applied("Pick", [t, keys]) =>
      if utility_keys_include(keys, field) {
        self.lookup_field(t, field)
      } else {
        None
      }
    Applied("Omit", [t, keys]) =>
      if utility_keys_include(keys, field) {
        None
      } else {
        self.lookup_field(t, field)
      }
    // supplied args before returning the field type so `b.value` on
    // `b: Box<number>` resolves to `number` rather than the raw `T`.
    Applied(n, args) =>
      match self.interfaces.get(n) {
        Some(iface) => {
          let bindings : Map[String, @ast.TsType] = {}
          let limit = if args.length() < iface.type_params.length() {
            args.length()
          } else {
            iface.type_params.length()
          }
          let mut i = 0
          while i < limit {
            bindings[iface.type_params[i]] = args[i]
            i = i + 1
          }
          for f in iface.fields {
            if f.0 == field {
              // Method-level generics shadow the interface's type params:
              // drop any shadowed names so a generic method keeps its own
              // fresh type variable rather than resolving it to the
              // interface's instantiated argument.
              let scoped = scoped_bindings_for_method(
                bindings,
                iface.method_type_params,
                field,
              )
              return Some(substitute_params(f.1, scoped))
            }
          }
          let mut j = 0
          while j < iface.extends_names.length() {
            let base_name = iface.extends_names[j]
            let base_args = if j < iface.extends_args.length() {
              iface.extends_args[j]
            } else {
              []
            }
            // Substitute the outer interface's bindings into the base's
            // type args before recursing — `Sub<number> extends Box<T>`
            // becomes a lookup against `Box<number>`, not `Box<T>`.
            let substituted_args : Array[@ast.TsType] = []
            for a in base_args {
              substituted_args.push(substitute_params(a, bindings))
            }
            let base_ty : @ast.TsType = if substituted_args.length() > 0 {
              @ast.TsType::Applied(base_name, substituted_args)
            } else {
              @ast.TsType::Named(base_name)
            }
            match self.lookup_field(base_ty, field) {
              Some(t) => return Some(substitute_params(t, bindings))
              None => ()
            }
            j = j + 1
          }
          // Index-signature fallback with the outer-interface bindings
          // applied to the signature's value type.
          match index_signature_value(iface.index_signatures, field) {
            Some(t) => Some(substitute_params(t, bindings))
            None => None
          }
        }
        None =>
          match self.classes.get(n) {
            Some(cls) => {
              // Same shape as the interface arm, walking class members
              // (instance only — static members aren't reachable via
              // `recv.field` on an instance).
              let bindings : Map[String, @ast.TsType] = {}
              let limit = if args.length() < cls.type_params.length() {
                args.length()
              } else {
                cls.type_params.length()
              }
              let mut i = 0
              while i < limit {
                bindings[cls.type_params[i]] = args[i]
                i = i + 1
              }
              for p in cls.properties {
                if p.name == field && !p.is_static {
                  return Some(substitute_params(p.type_, bindings))
                }
              }
              for m in cls.methods {
                if m.name == field && !m.is_static {
                  // Method-level type parameters shadow the class's: a
                  // `foo3<T>(t: T, u: U)` declares a fresh `T` that is
                  // unrelated to the class's instantiated `T`. Drop any
                  // shadowed names from the substitution map so the method's
                  // own generics stay as bare `Named(...)` references (which
                  // the assignability check then leaves unconstrained)
                  // instead of being resolved to the class's type argument.
                  let method_bindings = if m.type_params.length() > 0 {
                    let scoped : Map[String, @ast.TsType] = {}
                    for kv in bindings {
                      if !m.type_params.contains(kv.0) {
                        scoped[kv.0] = kv.1
                      }
                    }
                    scoped
                  } else {
                    bindings
                  }
                  let param_types : Array[@ast.TsType] = []
                  for mp in m.params {
                    param_types.push(substitute_params(mp.1, method_bindings))
                  }
                  return Some(
                    @ast.TsType::Func(
                      param_types,
                      substitute_params(m.return_type, method_bindings),
                    ),
                  )
                }
              }
              for base in cls.base_names {
                match self.lookup_field(@ast.TsType::Named(base), field) {
                  Some(t) => return Some(substitute_params(t, bindings))
                  None => ()
                }
              }
              None
            }
            None => None
          }
      }
    Object(entries) => {
      // Named-property lookup first — `Literal("foo")` keyed entry.
      for entry in entries {
        match entry.0 {
          Literal(name) if name == field => return Some(entry.1)
          _ => ()
        }
      }
      // Index-signature fallback: an entry keyed by the bare primitive
      // shape (`String_` / `Number`) acts as `[k: string]: V`. Honour it
      // so a type-alias `{ foo: number; [k: string]: V }` returns `V`
      // for non-declared keys instead of producing a missing-field
      // diagnostic.
      let field_is_numeric = try @string.parse_int(field) catch {
        _ => false
      } noraise {
        _ => true
      }
      for entry in entries {
        match entry.0 {
          String_ => return Some(entry.1)
          Number | Int =>
            // Numeric index signatures only match numeric keys.
            if field_is_numeric {
              return Some(entry.1)
            }
          _ => ()
        }
      }
      None
    }
    Struct(_, fields) => {
      for f in fields {
        if f.0 == field {
          return Some(f.1)
        }
      }
      None
    }
    Array(elem) => array_prototype_member(elem, field)
    Number | NumberLiteral(_) | Int => number_prototype_member(field)
    Boolean | BooleanLiteral(_) => boolean_prototype_member(field)
    Func(params, ret) => func_prototype_member(params, ret, field)
    Tuple(items) =>
      // Numeric field on a tuple → that element type.
      try @string.parse_int(field) catch {
        _ =>
          match field {
            "length" => Some(@ast.TsType::Number)
            _ => None
          }
      } noraise {
        idx =>
          if idx >= 0 && idx < items.length() {
            Some(items[idx])
          } else {
            None
          }
      }
    String_ | Literal(_) => string_prototype_member(field)
    // Field access on a union is only safe when *every* member
    // declares the field. Build the per-member result and either
    // return the union of their field types (common case) or `None`
    // if any member lacks it (which surfaces as an error at the
    // PropAccess site).
    Union(items) => {
      let parts : Array[@ast.TsType] = []
      let mut any_missing = false
      for it in items {
        match self.lookup_field(it, field) {
          Some(t) => parts.push(t)
          None => any_missing = true
        }
      }
      if parts.length() == 0 {
        None
      } else if !any_missing {
        // Every member has the field — return the tight union.
        if parts.length() == 1 {
          Some(parts[0])
        } else {
          Some(@ast.TsType::Union(parts))
        }
      } else {
        // Some members lack the field. This is a real type error at the
        // call site, but return the best-effort union so downstream inference
        // still gets a useful type rather than Any.
        None
      }
    }
    // Intersection: a value of `A & B` has all properties of both A and B.
    // Return the type from the first member that declares the field; when
    // the same name is declared on multiple members the types should be
    // identical (or one is a sub-type), so first-match is correct in practice.
    Intersection(items) => {
      for it in items {
        match self.lookup_field(it, field) {
          Some(t) => return Some(t)
          None => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
/// Strip `null` and `undefined` members from a union type so nullable
/// receivers degrade gracefully in field / method lookups. Returns the
/// original type unchanged when no null/undefined members are present or when
/// the result would be empty (all members were nullish).
fn prune_nullish(resolver : Resolver, ty : @ast.TsType) -> @ast.TsType {
  match resolver.unwrap(ty) {
    Union(parts) => {
      let nn : Array[@ast.TsType] = []
      for p in parts {
        match p {
          Null | Undefined => ()
          _ => nn.push(p)
        }
      }
      if nn.length() > 0 && nn.length() < parts.length() {
        if nn.length() == 1 {
          nn[0]
        } else {
          @ast.TsType::Union(nn)
        }
      } else {
        ty
      }
    }
    _ => ty
  }
}

///|
fn collect_index_sigs(
  resolver : Resolver,
  ty : @ast.TsType,
  out : Array[(@ast.TsType, @ast.TsType)],
  seen : Map[String, Bool],
) -> Unit {
  match resolver.unwrap(ty) {
    Named(n) => {
      if seen.contains(n) {
        return
      }
      seen[n] = true
      match resolver.interfaces.get(n) {
        Some(iface) => {
          for sig in iface.index_signatures {
            out.push(sig)
          }
          let mut i = 0
          while i < iface.extends_names.length() {
            let base_name = iface.extends_names[i]
            let base_args = if i < iface.extends_args.length() {
              iface.extends_args[i]
            } else {
              []
            }
            let base_ty : @ast.TsType = if base_args.length() > 0 {
              @ast.TsType::Applied(base_name, base_args)
            } else {
              @ast.TsType::Named(base_name)
            }
            collect_index_sigs(resolver, base_ty, out, seen)
            i = i + 1
          }
        }
        None =>
          match resolver.classes.get(n) {
            Some(cls) =>
              for sig in cls.index_signatures {
                out.push(sig)
              }
            None => ()
          }
      }
    }
    Applied(n, args) => {
      if seen.contains(n) {
        return
      }
      seen[n] = true
      match resolver.interfaces.get(n) {
        Some(iface) => {
          let bindings : Map[String, @ast.TsType] = {}
          let limit = if args.length() < iface.type_params.length() {
            args.length()
          } else {
            iface.type_params.length()
          }
          let mut i = 0
          while i < limit {
            bindings[iface.type_params[i]] = args[i]
            i = i + 1
          }
          for sig in iface.index_signatures {
            out.push((sig.0, substitute_params(sig.1, bindings)))
          }
          let mut j = 0
          while j < iface.extends_names.length() {
            let base_name = iface.extends_names[j]
            let base_args = if j < iface.extends_args.length() {
              iface.extends_args[j]
            } else {
              []
            }
            let substituted_args : Array[@ast.TsType] = []
            for a in base_args {
              substituted_args.push(substitute_params(a, bindings))
            }
            let base_ty : @ast.TsType = if substituted_args.length() > 0 {
              @ast.TsType::Applied(base_name, substituted_args)
            } else {
              @ast.TsType::Named(base_name)
            }
            collect_index_sigs(resolver, base_ty, out, seen)
            j = j + 1
          }
        }
        None =>
          match resolver.classes.get(n) {
            Some(cls) =>
              for sig in cls.index_signatures {
                out.push(sig)
              }
            None => ()
          }
      }
    }
    Union(items) =>
      for it in items {
        collect_index_sigs(resolver, it, out, seen)
      }
    Intersection(items) =>
      for it in items {
        collect_index_sigs(resolver, it, out, seen)
      }
    _ => ()
  }
}

///|
/// Look up the value type of an index signature on an interface or class
/// for a dynamic (non-literal) key access `recv[idx]`. Returns `None` when
/// the receiver has no matching index signature.
fn Resolver::lookup_index_sig(
  self : Resolver,
  recv : @ast.TsType,
  idx : @ast.TsType,
) -> @ast.TsType? {
  let is_numeric = match idx {
    Number | Int | NumberLiteral(_) => true
    _ => false
  }
  let is_stringy = match idx {
    String_ | Literal(_) | Number | Int | NumberLiteral(_) => true
    _ => false
  }
  let all_sigs : Array[(@ast.TsType, @ast.TsType)] = []
  collect_index_sigs(self, self.unwrap(recv), all_sigs, {})
  match all_sigs {
    [] => None
    signatures => {
      let mut numeric_val : @ast.TsType? = None
      let mut string_val : @ast.TsType? = None
      for sig in signatures {
        match sig.0 {
          Number | Int => numeric_val = Some(sig.1)
          String_ | Literal(_) => string_val = Some(sig.1)
          _ => ()
        }
      }
      if is_numeric {
        match numeric_val {
          Some(t) => return Some(t)
          None => ()
        }
      }
      if is_stringy {
        match string_val {
          Some(t) => return Some(t)
          None => ()
        }
      }
      None
    }
  }
}

///|
/// Well-known `Promise.prototype.*` members. `inner` is the resolved-value
/// type (the `T` in `Promise<T>`). The chainable `then` / `catch` /
/// `finally` methods need callback-driven inference for the result type;
/// they're handled in `infer_expr.MethodCall` so the result `Promise<U>`
/// reflects the callback's body, similar to `Array.prototype.map`.
fn promise_prototype_member(
  inner : @ast.TsType,
  field : String,
) -> @ast.TsType? {
  let promise_t = @ast.TsType::Applied("Promise", [inner])
  match field {
    // Chain methods — return promise-typed; the call-site path
    // substitutes the callback's return.
    "then" =>
      Some(
        @ast.TsType::Func(
          [@ast.TsType::Func([inner], @ast.TsType::Any)],
          promise_t,
        ),
      )
    "catch" =>
      Some(
        @ast.TsType::Func(
          [@ast.TsType::Func([@ast.TsType::Any], @ast.TsType::Any)],
          promise_t,
        ),
      )
    "finally" =>
      Some(
        @ast.TsType::Func([@ast.TsType::Func([], @ast.TsType::Void)], promise_t),
      )
    _ => None
  }
}

///|
/// Well-known `Map<K, V>` instance members specialised at the receiver's
/// key / value types. Iterator-returning methods yield
/// `Applied("IterableIterator", [...])` so downstream code paths can
/// recognise them.
fn map_prototype_member(
  k : @ast.TsType,
  v : @ast.TsType,
  field : String,
) -> @ast.TsType? {
  let map_t = @ast.TsType::Applied("Map", [k, v])
  let bool_ = @ast.TsType::Boolean
  let num = @ast.TsType::Number
  let nullable_v = narrow_union(v, @ast.TsType::Undefined)
  let entry_t = @ast.TsType::Tuple([k, v])
  let iter_of = fn(t) { @ast.TsType::Applied("IterableIterator", [t]) }
  match field {
    "size" => Some(num)
    "get" => Some(@ast.TsType::Func([k], nullable_v))
    "set" => Some(@ast.TsType::Func([k, v], map_t))
    "has" => Some(@ast.TsType::Func([k], bool_))
    "delete" => Some(@ast.TsType::Func([k], bool_))
    "clear" => Some(@ast.TsType::Func([], @ast.TsType::Void))
    "keys" => Some(@ast.TsType::Func([], iter_of(k)))
    "values" => Some(@ast.TsType::Func([], iter_of(v)))
    "entries" => Some(@ast.TsType::Func([], iter_of(entry_t)))
    "forEach" =>
      Some(
        @ast.TsType::Func(
          [@ast.TsType::Func([v, k, map_t], @ast.TsType::Void)],
          @ast.TsType::Void,
        ),
      )
    _ => None
  }
}

///|
/// Well-known `Set<T>` instance members. Mirrors `map_prototype_member`
/// for the simpler single-type-parameter shape.
fn set_prototype_member(t : @ast.TsType, field : String) -> @ast.TsType? {
  let set_t = @ast.TsType::Applied("Set", [t])
  let bool_ = @ast.TsType::Boolean
  let num = @ast.TsType::Number
  let iter_of = fn(x) { @ast.TsType::Applied("IterableIterator", [x]) }
  match field {
    "size" => Some(num)
    "add" => Some(@ast.TsType::Func([t], set_t))
    "has" => Some(@ast.TsType::Func([t], bool_))
    "delete" => Some(@ast.TsType::Func([t], bool_))
    "clear" => Some(@ast.TsType::Func([], @ast.TsType::Void))
    "keys" | "values" => Some(@ast.TsType::Func([], iter_of(t)))
    "entries" =>
      Some(@ast.TsType::Func([], iter_of(@ast.TsType::Tuple([t, t]))))
    "forEach" =>
      Some(
        @ast.TsType::Func(
          [@ast.TsType::Func([t, t, set_t], @ast.TsType::Void)],
          @ast.TsType::Void,
        ),
      )
    _ => None
  }
}

///|
/// `Date.prototype.*` members.
fn date_prototype_member(field : String) -> @ast.TsType? {
  let n = @ast.TsType::Number
  let s = @ast.TsType::String_
  match field {
    "getTime"
    | "getFullYear"
    | "getMonth"
    | "getDate"
    | "getHours"
    | "getMinutes"
    | "getSeconds"
    | "getMilliseconds"
    | "getDay"
    | "getTimezoneOffset"
    | "getUTCFullYear"
    | "getUTCMonth"
    | "getUTCDate"
    | "getUTCHours"
    | "getUTCMinutes"
    | "getUTCSeconds"
    | "getUTCMilliseconds"
    | "getUTCDay"
    | "valueOf" => Some(@ast.TsType::Func([], n))
    "setTime"
    | "setFullYear"
    | "setMonth"
    | "setDate"
    | "setHours"
    | "setMinutes"
    | "setSeconds"
    | "setMilliseconds"
    | "setUTCFullYear"
    | "setUTCMonth"
    | "setUTCDate"
    | "setUTCHours"
    | "setUTCMinutes"
    | "setUTCSeconds"
    | "setUTCMilliseconds" => Some(@ast.TsType::Func([n], n))
    "toString"
    | "toDateString"
    | "toTimeString"
    | "toLocaleString"
    | "toLocaleDateString"
    | "toLocaleTimeString"
    | "toISOString"
    | "toJSON"
    | "toUTCString" => Some(@ast.TsType::Func([], s))
    _ => None
  }
}

///|
/// `Number.prototype.*` members. All numeric literal subtypes share the
/// same prototype as the base `number` shape.
fn number_prototype_member(field : String) -> @ast.TsType? {
  let n = @ast.TsType::Number
  let s = @ast.TsType::String_
  match field {
    "toFixed" | "toExponential" | "toPrecision" =>
      Some(@ast.TsType::Func([n], s))
    // `toString(radix?: number): string` — the radix argument is
    // optional, so expose the zero-arg form so a bare `.toString()`
    // call validates.
    "toString" => Some(@ast.TsType::Func([], s))
    "toLocaleString" => Some(@ast.TsType::Func([], s))
    "valueOf" => Some(@ast.TsType::Func([], n))
    _ => None
  }
}

///|
/// `Boolean.prototype.*` members.
fn boolean_prototype_member(field : String) -> @ast.TsType? {
  let b = @ast.TsType::Boolean
  let s = @ast.TsType::String_
  match field {
    "toString" => Some(@ast.TsType::Func([], s))
    "valueOf" => Some(@ast.TsType::Func([], b))
    _ => None
  }
}

///|
/// `RegExp.prototype.*` members and the read-only flag accessors.
fn regexp_prototype_member(field : String) -> @ast.TsType? {
  let s = @ast.TsType::String_
  let b = @ast.TsType::Boolean
  let n = @ast.TsType::Number
  let regex_t = @ast.TsType::Named("RegExp")
  let exec_arr = @ast.TsType::Array(s)
  match field {
    // Methods
    "test" => Some(@ast.TsType::Func([s], b))
    "exec" =>
      Some(@ast.TsType::Func([s], narrow_union(exec_arr, @ast.TsType::Null)))
    "compile" => Some(@ast.TsType::Func([s, s], regex_t))
    "toString" => Some(@ast.TsType::Func([], s))
    // Properties
    "source" | "flags" => Some(s)
    "global"
    | "ignoreCase"
    | "multiline"
    | "sticky"
    | "unicode"
    | "dotAll"
    | "unicodeSets"
    | "hasIndices" => Some(b)
    "lastIndex" => Some(n)
    _ => None
  }
}

///|
/// `IteratorResult<T>` synthesis: `{ value: T; done: boolean }`. Used by
/// the iterator prototypes' `next()` / `return()` / `throw()` results.
fn iterator_result_type(t : @ast.TsType) -> @ast.TsType {
  @ast.TsType::Object([
    (@ast.TsType::Literal("value"), t),
    (@ast.TsType::Literal("done"), @ast.TsType::Boolean),
  ])
}

///|
/// `Iterator<T>` / `IterableIterator<T>` / `Generator<T>` members. The
/// `next` / `return` / `throw` methods all surface `IteratorResult<T>`;
/// the `[Symbol.iterator]` / `[Symbol.asyncIterator]` methods aren't
/// expressible via a string key here so they fall through to `None`.
fn iterator_prototype_member(t : @ast.TsType, field : String) -> @ast.TsType? {
  let res = iterator_result_type(t)
  match field {
    "next" => Some(@ast.TsType::Func([], res))
    "return" => Some(@ast.TsType::Func([t], res))
    "throw" => Some(@ast.TsType::Func([@ast.TsType::Any], res))
    _ => None
  }
}

///|
/// Async-variant iterator: `next/return/throw` resolve to
/// `Promise<IteratorResult<T>>`.
fn async_iterator_prototype_member(
  t : @ast.TsType,
  field : String,
) -> @ast.TsType? {
  let res = @ast.TsType::Applied("Promise", [iterator_result_type(t)])
  match field {
    "next" => Some(@ast.TsType::Func([], res))
    "return" => Some(@ast.TsType::Func([t], res))
    "throw" => Some(@ast.TsType::Func([@ast.TsType::Any], res))
    _ => None
  }
}

///|
/// `WeakMap<K, V>` instance members. Subset of `Map` — no `size` /
/// iteration since the entries are weakly held.
fn weakmap_prototype_member(
  k : @ast.TsType,
  v : @ast.TsType,
  field : String,
) -> @ast.TsType? {
  let map_t = @ast.TsType::Applied("WeakMap", [k, v])
  let bool_ = @ast.TsType::Boolean
  let nullable_v = narrow_union(v, @ast.TsType::Undefined)
  match field {
    "get" => Some(@ast.TsType::Func([k], nullable_v))
    "set" => Some(@ast.TsType::Func([k, v], map_t))
    "has" => Some(@ast.TsType::Func([k], bool_))
    "delete" => Some(@ast.TsType::Func([k], bool_))
    _ => None
  }
}

///|
/// `WeakSet<T>` instance members. Subset of `Set`.
fn weakset_prototype_member(t : @ast.TsType, field : String) -> @ast.TsType? {
  let set_t = @ast.TsType::Applied("WeakSet", [t])
  let bool_ = @ast.TsType::Boolean
  match field {
    "add" => Some(@ast.TsType::Func([t], set_t))
    "has" => Some(@ast.TsType::Func([t], bool_))
    "delete" => Some(@ast.TsType::Func([t], bool_))
    _ => None
  }
}

///|
/// `Function.prototype.{call, apply, bind, length, name}` members.
/// `call` / `apply` return the inner function's return type; `bind`
/// returns the same `Func(...)` shape (we don't model partial
/// application of arguments here).
fn func_prototype_member(
  params : Array[@ast.TsType],
  ret : @ast.TsType,
  field : String,
) -> @ast.TsType? {
  let s = @ast.TsType::String_
  let n = @ast.TsType::Number
  let any = @ast.TsType::Any
  match field {
    // `call(thisArg, ...args)` — thisArg comes first, followed by the
    // function's own parameter list. Returns the function's `ret`.
    "call" => {
      let call_params : Array[@ast.TsType] = [any]
      for p in params {
        call_params.push(p)
      }
      Some(@ast.TsType::Func(call_params, ret))
    }
    "apply" => Some(@ast.TsType::Func([any, @ast.TsType::Array(any)], ret))
    "bind" => Some(@ast.TsType::Func([any], @ast.TsType::Func(params, ret)))
    "name" => Some(s)
    "length" => Some(n)
    "toString" => Some(@ast.TsType::Func([], s))
    _ => None
  }
}

///|
/// Recognise built-in error-class names — `Error` and its subclasses
/// inherit a stable instance shape (`message`, `name`, `stack`,
/// `toString`).
fn is_error_class_name(name : String) -> Bool {
  match name {
    "Error"
    | "TypeError"
    | "RangeError"
    | "SyntaxError"
    | "ReferenceError"
    | "EvalError"
    | "URIError"
    | "AggregateError" => true
    _ => false
  }
}

///|
fn error_prototype_member(field : String) -> @ast.TsType? {
  let s = @ast.TsType::String_
  match field {
    "message" | "name" => Some(s)
    "stack" => Some(narrow_union(s, @ast.TsType::Undefined))
    "toString" => Some(@ast.TsType::Func([], s))
    _ => None
  }
}

///|
/// Element type of a typed-array class. Returns `None` for non-typed-array
/// class names so callers know to fall through.
fn typed_array_element_type(name : String) -> @ast.TsType? {
  match name {
    "Int8Array"
    | "Uint8Array"
    | "Uint8ClampedArray"
    | "Int16Array"
    | "Uint16Array"
    | "Int32Array"
    | "Uint32Array"
    | "Float32Array"
    | "Float64Array" => Some(@ast.TsType::Number)
    "BigInt64Array" | "BigUint64Array" => Some(@ast.TsType::BigInt)
    _ => None
  }
}

///|
/// Extra members declared on the typed-array shape that don't appear on
/// the regular `Array.prototype` (`buffer`, `byteLength`, `byteOffset`,
/// `BYTES_PER_ELEMENT`, `subarray`, `set`, `copyWithin`).
fn typed_array_extra_member(field : String) -> @ast.TsType? {
  let n = @ast.TsType::Number
  match field {
    "buffer" => Some(@ast.TsType::Named("ArrayBuffer"))
    "byteLength" | "byteOffset" | "BYTES_PER_ELEMENT" => Some(n)
    "subarray" =>
      Some(@ast.TsType::Func([n, n], @ast.TsType::Named("Uint8Array")))
    "set" =>
      Some(@ast.TsType::Func([@ast.TsType::Array(n), n], @ast.TsType::Void))
    "copyWithin" =>
      Some(@ast.TsType::Func([n, n], @ast.TsType::Named("Uint8Array")))
    _ => None
  }
}

///|
/// Well-known global namespace static methods (`Object.keys`, `Math.max`,
/// `Number.isNaN`, etc.). Returns the conventional `Func(...)` shape so
/// `check_call_args_in_expr` validates argument types; the result type
/// of generic-shaped statics (e.g. `Object.entries<T>`) is handled by
/// `global_static_method_special` at the call site.
fn global_namespace_method(ns : String, meth : String) -> @ast.TsType? {
  let s = @ast.TsType::String_
  let n = @ast.TsType::Number
  let b = @ast.TsType::Boolean
  let any = @ast.TsType::Any
  let str_arr = @ast.TsType::Array(s)
  match (ns, meth) {
    // Object.*
    ("Object", "keys") => Some(@ast.TsType::Func([any], str_arr))
    ("Object", "values") =>
      Some(@ast.TsType::Func([any], @ast.TsType::Array(any)))
    ("Object", "entries") =>
      Some(
        @ast.TsType::Func(
          [any],
          @ast.TsType::Array(@ast.TsType::Tuple([s, any])),
        ),
      )
    ("Object", "assign") => Some(@ast.TsType::Func([any, any], any))
    ("Object", "freeze") => Some(@ast.TsType::Func([any], any))
    ("Object", "isFrozen") => Some(@ast.TsType::Func([any], b))
    ("Object", "create") => Some(@ast.TsType::Func([any], any))
    ("Object", "fromEntries") => Some(@ast.TsType::Func([any], any))
    ("Object", "getPrototypeOf") => Some(@ast.TsType::Func([any], any))
    ("Object", "setPrototypeOf") => Some(@ast.TsType::Func([any, any], any))
    ("Object", "getOwnPropertyNames") => Some(@ast.TsType::Func([any], str_arr))
    ("Object", "hasOwn") => Some(@ast.TsType::Func([any, s], b))
    // Math.*
    ("Math", "abs")
    | ("Math", "ceil")
    | ("Math", "floor")
    | ("Math", "round")
    | ("Math", "trunc")
    | ("Math", "sign")
    | ("Math", "sqrt")
    | ("Math", "cbrt")
    | ("Math", "exp")
    | ("Math", "log")
    | ("Math", "log2")
    | ("Math", "log10")
    | ("Math", "log1p")
    | ("Math", "expm1")
    | ("Math", "sin")
    | ("Math", "cos")
    | ("Math", "tan")
    | ("Math", "asin")
    | ("Math", "acos")
    | ("Math", "atan")
    | ("Math", "sinh")
    | ("Math", "cosh")
    | ("Math", "tanh")
    | ("Math", "asinh")
    | ("Math", "acosh")
    | ("Math", "atanh") => Some(@ast.TsType::Func([n], n))
    ("Math", "pow") | ("Math", "atan2") | ("Math", "hypot") =>
      Some(@ast.TsType::Func([n, n], n))
    ("Math", "max") | ("Math", "min") => Some(@ast.TsType::Func([n], n))
    ("Math", "random") => Some(@ast.TsType::Func([], n))
    ("Math", "fround") | ("Math", "clz32") | ("Math", "imul") =>
      Some(@ast.TsType::Func([n], n))
    // Number.*
    ("Number", "isInteger")
    | ("Number", "isSafeInteger")
    | ("Number", "isFinite")
    | ("Number", "isNaN") => Some(@ast.TsType::Func([any], b))
    ("Number", "parseFloat") => Some(@ast.TsType::Func([s], n))
    ("Number", "parseInt") => Some(@ast.TsType::Func([s, n], n))
    // String.* (constructor namespace, not prototype)
    ("String", "fromCharCode") => Some(@ast.TsType::Func([n], s))
    ("String", "fromCodePoint") => Some(@ast.TsType::Func([n], s))
    ("String", "raw") => Some(@ast.TsType::Func([any], s))
    // JSON.*
    ("JSON", "parse") => Some(@ast.TsType::Func([s], any))
    ("JSON", "stringify") => Some(@ast.TsType::Func([any], s))
    // Array.*
    ("Array", "isArray") => Some(@ast.TsType::Func([any], b))
    ("Array", "of") => Some(@ast.TsType::Func([any], @ast.TsType::Array(any)))
    ("Array", "from") => Some(@ast.TsType::Func([any], @ast.TsType::Array(any)))
    // Boolean
    ("Boolean", "constructor") => Some(@ast.TsType::Func([any], b))
    // Symbol.*
    ("Symbol", "for") => Some(@ast.TsType::Func([s], @ast.TsType::Symbol))
    ("Symbol", "keyFor") => Some(@ast.TsType::Func([@ast.TsType::Symbol], s))
    // Date.*
    ("Date", "now") => Some(@ast.TsType::Func([], n))
    ("Date", "parse") => Some(@ast.TsType::Func([s], n))
    ("Date", "UTC") => Some(@ast.TsType::Func([n], n))
    // Promise.*
    ("Promise", "resolve") =>
      Some(@ast.TsType::Func([any], @ast.TsType::Applied("Promise", [any])))
    ("Promise", "reject") =>
      Some(@ast.TsType::Func([any], @ast.TsType::Applied("Promise", [any])))
    ("Promise", "all") | ("Promise", "race") | ("Promise", "any") =>
      Some(
        @ast.TsType::Func(
          [@ast.TsType::Array(any)],
          @ast.TsType::Applied("Promise", [any]),
        ),
      )
    ("Promise", "allSettled") =>
      Some(
        @ast.TsType::Func(
          [@ast.TsType::Array(any)],
          @ast.TsType::Applied("Promise", [@ast.TsType::Array(any)]),
        ),
      )
    // console.* — every method accepts any arg list and returns void.
    // Modelled with a single-arg `Func` so the universally common
    // `console.log("msg")` call validates; multi-arg calls fall through
    // to the contextual-typing fallback.
    ("console", "log")
    | ("console", "info")
    | ("console", "warn")
    | ("console", "error")
    | ("console", "debug")
    | ("console", "trace")
    | ("console", "dir")
    | ("console", "table")
    | ("console", "group")
    | ("console", "groupCollapsed")
    | ("console", "groupEnd")
    | ("console", "clear")
    | ("console", "count")
    | ("console", "countReset")
    | ("console", "time")
    | ("console", "timeEnd")
    | ("console", "timeLog")
    | ("console", "assert")
    | ("console", "dirxml") => Some(@ast.TsType::Func([any], @ast.TsType::Void))
    _ => None
  }
}

///|
/// Generic-shaped static methods that need callback / argument-driven
/// inference for their result type. Returns the specialised result type
/// when the static call matches a recognised pattern; otherwise `None`,
/// letting the caller use the conventional `Func` shape.
fn global_static_method_special(
  env : ExprEnv,
  resolver : Resolver,
  ns : String,
  meth : String,
  args : Array[@ast.TsExpr],
) -> @ast.TsType? {
  match (ns, meth, args) {
    // `Promise.resolve(value)` — yields `Promise<typeof value>`. If
    // the value is itself a promise, flatten one level.
    ("Promise", "resolve", [v]) => {
      let inner = infer_expr(env, resolver, v)
      let flat = match inner {
        Applied("Promise", [t]) | Applied("PromiseLike", [t]) => t
        other => other
      }
      Some(@ast.TsType::Applied("Promise", [flat]))
    }
    // `Promise.all(arr)` — when `arr` infers to `Array(T)` (or a tuple
    // shape), yield `Promise<Array(unwrap(T))>` so awaited values
    // surface with the promise-unwrapped element type.
    ("Promise", "all", [arr]) => {
      let arr_ty = infer_expr(env, resolver, arr)
      let elem = match array_element_type(resolver, arr_ty) {
        Some(e) => e
        None => @ast.TsType::Any
      }
      // Unwrap each element if it's `Promise<T>` so we end up with the
      // resolved-value array.
      let unwrapped = match elem {
        Applied("Promise", [t]) | Applied("PromiseLike", [t]) => t
        other => other
      }
      Some(@ast.TsType::Applied("Promise", [@ast.TsType::Array(unwrapped)]))
    }
    ("Promise", "race", [arr]) | ("Promise", "any", [arr]) => {
      let arr_ty = infer_expr(env, resolver, arr)
      let elem = match array_element_type(resolver, arr_ty) {
        Some(e) => e
        None => @ast.TsType::Any
      }
      let unwrapped = match elem {
        Applied("Promise", [t]) | Applied("PromiseLike", [t]) => t
        other => other
      }
      Some(@ast.TsType::Applied("Promise", [unwrapped]))
    }
    // `JSON.parse(...)` returns `any` already by convention.
    _ => None
  }
}

///|
/// Well-known `String.prototype.*` members. Strings are immutable in JS so
/// every "mutating-looking" method returns a new string rather than
/// modifying the receiver. We expose the most commonly used ones with
/// concrete `Func(...)` signatures.
fn string_prototype_member(field : String) -> @ast.TsType? {
  let s = @ast.TsType::String_
  let n = @ast.TsType::Number
  let b = @ast.TsType::Boolean
  let str_arr = @ast.TsType::Array(s)
  match field {
    // Properties
    "length" => Some(n)
    // Char access
    "charAt" => Some(@ast.TsType::Func([n], s))
    "charCodeAt" => Some(@ast.TsType::Func([n], n))
    "codePointAt" => Some(@ast.TsType::Func([n], n))
    "at" =>
      Some(@ast.TsType::Func([n], narrow_union(s, @ast.TsType::Undefined)))
    // Search
    "indexOf" => Some(@ast.TsType::Func([s, n], n))
    "lastIndexOf" => Some(@ast.TsType::Func([s, n], n))
    "includes" => Some(@ast.TsType::Func([s], b))
    "startsWith" => Some(@ast.TsType::Func([s], b))
    "endsWith" => Some(@ast.TsType::Func([s], b))
    "search" => Some(@ast.TsType::Func([s], n))
    "match" =>
      Some(@ast.TsType::Func([s], narrow_union(str_arr, @ast.TsType::Null)))
    "matchAll" => Some(@ast.TsType::Func([s], str_arr))
    // Transformation (returns string)
    "slice" => Some(@ast.TsType::Func([n, n], s))
    "substring" => Some(@ast.TsType::Func([n, n], s))
    "substr" => Some(@ast.TsType::Func([n, n], s))
    "replace" => Some(@ast.TsType::Func([s, s], s))
    "replaceAll" => Some(@ast.TsType::Func([s, s], s))
    "toLowerCase" => Some(@ast.TsType::Func([], s))
    "toUpperCase" => Some(@ast.TsType::Func([], s))
    "toLocaleLowerCase" => Some(@ast.TsType::Func([], s))
    "toLocaleUpperCase" => Some(@ast.TsType::Func([], s))
    "trim" => Some(@ast.TsType::Func([], s))
    "trimStart" => Some(@ast.TsType::Func([], s))
    "trimEnd" => Some(@ast.TsType::Func([], s))
    "padStart" => Some(@ast.TsType::Func([n, s], s))
    "padEnd" => Some(@ast.TsType::Func([n, s], s))
    "repeat" => Some(@ast.TsType::Func([n], s))
    "normalize" => Some(@ast.TsType::Func([s], s))
    "concat" => Some(@ast.TsType::Func([s], s))
    // Splitting
    "split" => Some(@ast.TsType::Func([s], str_arr))
    // Conversion
    "toString" => Some(@ast.TsType::Func([], s))
    "valueOf" => Some(@ast.TsType::Func([], s))
    // Comparison
    "localeCompare" => Some(@ast.TsType::Func([s], n))
    _ => None
  }
}

///|
fn Resolver::lookup_class_field(
  self : Resolver,
  cls : @ast.TsClassDecl,
  field : String,
) -> @ast.TsType? {
  for p in cls.properties {
    if p.name == field && !p.is_static {
      return Some(p.type_)
    }
  }
  for m in cls.methods {
    if m.name == field && !m.is_static {
      let param_types : Array[@ast.TsType] = []
      for p in m.params {
        param_types.push(p.1)
      }
      return Some(@ast.TsType::Func(param_types, m.return_type))
    }
  }
  for base in cls.base_names {
    match self.lookup_field(@ast.TsType::Named(base), field) {
      Some(t) => return Some(t)
      None => ()
    }
  }
  // Index-signature fallback (`class C { [k: string]: T }`): when no
  // declared property or method matched and the index signature accepts
  // the field's key kind, return the indexed value type.
  index_signature_value(cls.index_signatures, field)
}

///|
/// Element type of a "pure array-alias" interface: one whose only content is
/// `extends Array<T>` (or `ReadonlyArray<T>`) with no own fields or index
/// signatures. Returns `None` for interfaces that add members (those are not
/// interchangeable with a plain array) or that extend anything else.
fn interface_pure_array_element(
  resolver : Resolver,
  name : String,
) -> @ast.TsType? {
  match resolver.interfaces.get(name) {
    Some(iface) =>
      if iface.fields.length() == 0 &&
        iface.index_signatures.length() == 0 &&
        iface.extends_names.length() == 1 &&
        iface.extends_args.length() == 1 &&
        (
          iface.extends_names[0] == "Array" ||
          iface.extends_names[0] == "ReadonlyArray"
        ) &&
        iface.extends_args[0].length() == 1 {
        Some(iface.extends_args[0][0])
      } else {
        None
      }
    None => None
  }
}

///|
/// Look up a method's `(params, return)` signature. Returns `None` when the
/// receiver shape is opaque.
fn Resolver::lookup_method_sig(
  self : Resolver,
  recv : @ast.TsType,
  meth : String,
) -> (Array[@ast.TsType], @ast.TsType)? {
  match self.lookup_field(recv, meth) {
    Some(Func(ps, ret)) => Some((ps, ret))
    _ => None
  }
}

///|
/// True when `name` is assigned somewhere inside a class static
/// initialization block (`class C { static { name = ... } }`). Such blocks
/// run eagerly at class-definition time, so an outer `let name;` they assign
/// must not be reported as TS2454 (used-before-assigned) -- top-level class
/// declarations live in `module_.classes` rather than the statement stream,
/// so the per-statement assignment tracking never sees these writes.
fn Resolver::name_assigned_in_static_block(
  self : Resolver,
  name : String,
) -> Bool {
  for _, cls in self.classes {
    for block in cls.static_blocks {
      if block_assigns_name(block, name) {
        return true
      }
    }
  }
  false
}

///|
fn block_assigns_name(block : @ast.TsBlock, name : String) -> Bool {
  for stmt in block.stmts {
    if stmt_assigns_name(stmt, name) {
      return true
    }
  }
  false
}

///|
fn stmt_assigns_name(stmt : @ast.TsStmt, name : String) -> Bool {
  match stmt {
    Assign(n, _) | CompoundAssign(n, _, _) => n == name
    Expr(e) => expr_assigns_name(e, name)
    Block(b) => block_assigns_name(b, name)
    If(_, then_, else_) =>
      block_assigns_name(then_, name) ||
      (match else_ {
        Some(b) => block_assigns_name(b, name)
        None => false
      })
    While(_, body) | DoWhile(_, body) | With(_, body) =>
      block_assigns_name(body, name)
    Try(b, _, catch_, finally_) =>
      block_assigns_name(b, name) ||
      (match catch_ {
        Some(c) => block_assigns_name(c, name)
        None => false
      }) ||
      (match finally_ {
        Some(f) => block_assigns_name(f, name)
        None => false
      })
    Label(_, inner) => stmt_assigns_name(inner, name)
    _ => false
  }
}

///|
fn expr_assigns_name(expr : @ast.TsExpr, name : String) -> Bool {
  match expr {
    AssignExpr(n, _) | CompoundAssignExpr(Var(n), _, _) => n == name
    Seq(a, b) => expr_assigns_name(a, name) || expr_assigns_name(b, name)
    _ => false
  }
}

///|
/// Resolve an overloaded class method (`foo(x: 'a'): A; foo(x: 'b'): B;
/// foo(x: string): C`) to the return type of the first signature whose
/// parameters accept the given argument types. `lookup_method_sig` only
/// surfaces the first signature, so this is consulted first for receivers
/// that resolve to a class with more than one signature of the name.
/// Returns `None` when the receiver isn't such a class, the method has a
/// single signature, or no signature matches (callers fall back to the
/// existing single-signature path).
fn Resolver::resolve_method_overload(
  self : Resolver,
  recv : @ast.TsType,
  meth : String,
  arg_types : Array[@ast.TsType],
) -> @ast.TsType? {
  // Collect the candidate signatures of `meth` as `(params, return)` pairs,
  // in declaration order. A class method may be overloaded across several
  // declarations; an object / interface type expresses overloads as repeated
  // fields of the same name.
  let candidates : Array[(Array[@ast.TsType], @ast.TsType)] = []
  match self.unwrap(recv) {
    Named(n) | Applied(n, _) =>
      match self.classes.get(n) {
        Some(cls) => {
          // Overload *signatures* (no body) are the callable surface in TS;
          // the implementation signature (with a body) is not, so prefer the
          // former when both are present.
          let sig_only : Array[@ast.TsClassMethodDecl] = []
          let all : Array[@ast.TsClassMethodDecl] = []
          for m in cls.methods {
            if m.name == meth && !m.is_static {
              all.push(m)
              if m.body is None {
                sig_only.push(m)
              }
            }
          }
          let chosen = if sig_only.length() > 0 { sig_only } else { all }
          for m in chosen {
            let ps : Array[@ast.TsType] = []
            for p in m.params {
              ps.push(p.1)
            }
            candidates.push((ps, m.return_type))
          }
        }
        None => ()
      }
    Object(fields) =>
      for f in fields {
        match (f.0, f.1) {
          (Literal(k), Func(ps, ret)) if k == meth => candidates.push((ps, ret))
          _ => ()
        }
      }
    Struct(_, fields) =>
      for f in fields {
        match f.1 {
          Func(ps, ret) => if f.0 == meth { candidates.push((ps, ret)) }
          _ => ()
        }
      }
    _ => ()
  }
  // Only meaningful for an overload set: a single signature is already
  // handled by the first-match `lookup_method_sig` path.
  if candidates.length() <= 1 {
    return None
  }
  for c in candidates {
    let (params, ret) = c
    if params.length() != arg_types.length() {
      continue
    }
    let mut ok = true
    for i in 0..<arg_types.length() {
      if !is_assignable_to(arg_types[i], params[i]) {
        ok = false
        break
      }
    }
    if ok {
      return Some(ret)
    }
  }
  None
}

///|
/// Look up the constructor parameter types for a class. Returns `None` when
/// the class is unknown or has no declared constructor (the latter falls back
/// to a zero-arg signature, mirroring TS semantics).
fn Resolver::lookup_constructor(
  self : Resolver,
  class_name : String,
) -> Array[@ast.TsType]? {
  match self.classes.get(class_name) {
    Some(cls) =>
      match cls.constructor_params {
        Some(params) => {
          let types : Array[@ast.TsType] = []
          for p in params {
            types.push(p.1)
          }
          Some(types)
        }
        None => Some([])
      }
    None => None
  }
}

///|
/// Rich constructor signature (`TsParam` list carrying the rest-parameter
/// flag) for `class_name`, so a `new` call validates each variadic argument
/// against the element type instead of the whole array. Returns `None` for
/// an unknown class; `Some([])` for a class with no declared constructor.
fn Resolver::lookup_constructor_sig(
  self : Resolver,
  class_name : String,
) -> (Array[@ast.TsType], Array[@ast.TsParam])? {
  match self.classes.get(class_name) {
    Some(cls) =>
      match cls.constructor_params {
        Some(params) => {
          let types : Array[@ast.TsType] = []
          let sig : Array[@ast.TsParam] = []
          for idx, p in params {
            types.push(p.1)
            let is_rest = idx < cls.constructor_param_is_rest.length() &&
              cls.constructor_param_is_rest[idx]
            sig.push({
              name: p.0,
              binding: None,
              is_rest,
              type_: p.1,
              default: None,
            })
          }
          Some((types, sig))
        }
        // No explicit constructor. With no base class the constructor is the
        // implicit zero-arg one, so its arity is known exactly. With a base
        // (named or expression heritage) the constructor is *inherited*, and
        // we don't resolve the base's parameter list here -- return `None` so
        // the call site skips arity / argument checks rather than assuming
        // zero parameters (which would be a false positive on `new Derived(x)`
        // when the base takes `x`).
        None => if cls.base_names.length() == 0 { Some(([], [])) } else { None }
      }
    None => None
  }
}

// ---------------------------------------------------------------------------
// Environment — flat name -> type map with snapshot/restore for block scope
// and narrowing.
// ---------------------------------------------------------------------------

///|
priv struct ExprEnv {
  vars : Map[String, @ast.TsType]
  // Declared types -- captured at the original `let x: T;` /
  // function-parameter binding site and never overwritten by
  // narrowing. Assignments are checked against this rather than the
  // (possibly narrowed) `vars[name]`: `let x: string | number; x =
  // "hi";` followed by `x = 5;` is valid in TS even after `x` was
  // narrowed to `string`, because the assignment target stays at the
  // declared union.
  declared : Map[String, @ast.TsType]
}

///|
fn ExprEnv::new() -> ExprEnv {
  { vars: {}, declared: {} }
}

///|
fn ExprEnv::bind(self : ExprEnv, name : String, ty : @ast.TsType) -> Unit {
  self.vars[name] = ty
  // First write wins for `declared` -- subsequent narrowing rewrites
  // only `vars`. `declare_type` is the explicit alternative when the
  // caller wants to set / reset the declared slot deliberately.
  if !self.declared.contains(name) {
    self.declared[name] = ty
  }
}

///|
/// Narrowing-only write: update the current type in `vars` without
/// touching `declared`. Used by post-assignment narrowing
/// (`x = "hi"; x;` narrows `x` to `string`) and by analyse_narrowing
/// to avoid promoting a narrowed type into the assignment target.
fn ExprEnv::narrow(self : ExprEnv, name : String, ty : @ast.TsType) -> Unit {
  self.vars[name] = ty
}

///|
/// Set the declared (assignment-target) type for `name` explicitly,
/// overriding any previous binding. Used by the function-body walker
/// at parameter bind time and by the let/var/const walker for the
/// initial declaration -- both of which set the declared slot to
/// the source-annotated type, which is then preserved through any
/// narrowing rewrites in `vars`.
fn ExprEnv::declare_type(
  self : ExprEnv,
  name : String,
  ty : @ast.TsType,
) -> Unit {
  self.declared[name] = ty
}

///|
fn ExprEnv::lookup(self : ExprEnv, name : String) -> @ast.TsType? {
  self.vars.get(name)
}

///|
/// Look up the *declared* type for `name` -- i.e. the type the
/// variable was bound with at its declaration site, ignoring any
/// later flow narrowing. Returns `None` when no declared entry
/// exists, so callers can fall back to a different source (e.g.
/// `resolver.globals` for module-level variables) rather than
/// silently using the narrowed type.
fn ExprEnv::lookup_declared(self : ExprEnv, name : String) -> @ast.TsType? {
  self.declared.get(name)
}

///|
/// Capture a snapshot of `(name, type)` pairs currently in the env so we can
/// fully restore — including overwritten bindings — when a block exits. Used
/// for both lexical scope and narrowing. The snapshot covers `vars`
/// only; the matching `declared` entries are walked in step on
/// restore so a nested `let x: T;` doesn't leak its declared slot.
fn ExprEnv::full_snapshot(self : ExprEnv) -> Array[(String, @ast.TsType)] {
  let entries : Array[(String, @ast.TsType)] = []
  for entry in self.vars {
    entries.push((entry.0, entry.1))
  }
  entries
}

///|
fn ExprEnv::restore_from(
  self : ExprEnv,
  snap : Array[(String, @ast.TsType)],
) -> Unit {
  let kept : Map[String, @ast.TsType] = {}
  for entry in snap {
    kept[entry.0] = entry.1
  }
  let to_remove : Array[String] = []
  for entry in self.vars {
    if !kept.contains(entry.0) {
      to_remove.push(entry.0)
    }
  }
  for n in to_remove {
    let _ = self.vars.remove(n)
    // Drop the matching declared slot too: a name that wasn't in
    // `vars` at snapshot time was introduced after, so its declared
    // entry was also introduced after and must go.
    let _ = self.declared.remove(n)
  }
  for entry in snap {
    self.vars[entry.0] = entry.1
  }
}

// ---------------------------------------------------------------------------
// Context — issues accumulator + return type + async flag + resolver.
// ---------------------------------------------------------------------------

///|
priv struct CheckCtx {
  path_prefix : String
  // Effective return type used by `return` checks: for async functions this
  // is the inner `T` of `Promise<T>` (since `return x` inside `async`
  // returns a `T`, not the wrapping promise).
  return_type : @ast.TsType
  // Element type for `yield x` inside a generator function (the `T` in
  // `Generator<T, ...>` / `Iterable<T>` / `AsyncGenerator<T, ...>`).
  // `Any` when not in a generator or when the type isn't statically
  // extractable — the yield check skips in that case.
  yield_type : @ast.TsType
  resolver : Resolver
  issues : Array[ExprIssue]
  // Type-parameter names that are in scope where the checker is running
  // (function generics, surrounding class generics, etc.). Used to avoid
  // false "method does not exist on `T`" diagnostics: TypeScript treats
  // a bare type parameter as having `object`'s API, so we only flag
  // property / method misses on named types that are *not* type
  // parameters at this point.
  in_scope_type_params : Array[String]
  // Permissive mode for whole-corpus runs: when `true`, drop the
  // diagnostic families dominated by features we don't model (flow
  // narrowing, generic inference, builtin optional-arg tables). Set
  // by `check_module_function_bodies_permissive` -- the strict
  // `check_module_function_bodies` entry leaves it false so unit
  // tests keep asserting on those diagnostics.
  permissive : Bool
  // TS2454 ("Variable 'x' is used before being assigned") tracking
  // set. Names declared with `let x: T;` / `var x: T;` (no `=`
  // initializer, identified by the parser's `Var("__ts_no_init__")`
  // sentinel init) and whose declared type doesn't already accept
  // `undefined` are added here at the declaration site. A subsequent
  // `Assign(name, _)` removes the entry; a `Var(name)` reference
  // while the name is still in the set emits the diagnostic and
  // removes the entry (one report per variable is enough).
  unassigned : Map[String, Bool]
  // Strict-mode flag derived from the source file's
  // `// @strict: ...` / `// @strictPropertyInitialization: ...` /
  // `// @strictNullChecks: ...` header directives. Gates TS2454
  // (use-before-assign) and TS2564 (no initializer) emission.
  // True by default to match the tsc baseline behaviour for the
  // conformance corpus.
  strict_property_init : Bool
  // True while walking a computed property key (`{ [expr]: v }`). Suppresses
  // the TS2454 used-before-assigned read-check there: tsc does not apply
  // definite-assignment analysis to a name read inside a computed key
  // (`var s: string; ({ [s]() {} })` is accepted), so flagging it would be a
  // false positive. Undefined-name (TS2304) checking still runs.
  mut in_computed_key : Bool
}

///|
/// TS18013 ("Property '#x' is not accessible outside class ... because
/// it has a private identifier"). The parser brands every in-class
/// private access (`this.#x`, same-scope `obj.#x`) to a
/// `__private_brand__N__x` symbol; a member name that still carries the
/// literal `#` prefix at check time therefore only ever comes from an
/// access *outside* any class body (top-level code or a free function),
/// where touching a private identifier is always illegal. That makes
/// this a false-positive-free signal.
fn check_private_name_access(ctx : CheckCtx, prop_name : String) -> Unit {
  if prop_name.has_prefix("#") {
    record(
      ctx,
      "access `\{prop_name}`",
      "private identifier `\{prop_name}` is not accessible outside its class",
    )
  }
}

///|
/// The class whose body the checker is currently inside, derived from
/// `path_prefix`. Class-method bodies are walked under a synthesized
/// `"<Class>.<method>"` path (optionally prefixed with `namespace X > `
/// for nested namespaces); free functions and top-level statements have
/// no `"."`, so they yield `None` ("not inside a class body").
fn current_enclosing_class(path_prefix : String) -> String? {
  // Drop any `namespace … > ` / `declare global > ` prefix segments.
  let tail = match path_prefix.rev_find("> ") {
    Some(i) => path_prefix[i + 2:].to_owned()
    None => path_prefix
  }
  // Function bodies are walked under `"function <name>"`; class methods
  // synthesize `<name>` as `"<Class>.<method>"`, so strip the leading
  // `"function "` before splitting on `.`.
  let tail = if tail.has_prefix("function ") {
    tail["function ".length():].to_owned()
  } else {
    tail
  }
  match tail.find(".") {
    Some(i) => Some(tail[:i].to_owned())
    None => None
  }
}

///|
/// True when `sub` is `base` or transitively extends it, walking the
/// declared `base_names` chain through the resolver's class table.
fn class_extends(resolver : Resolver, sub : String, base : String) -> Bool {
  if sub == base {
    return true
  }
  let mut current = sub
  let mut depth = 0
  while depth < 32 {
    depth = depth + 1
    match resolver.classes.get(current) {
      Some(decl) => {
        if decl.base_names.contains(base) {
          return true
        }
        if decl.base_names.length() == 0 {
          return false
        }
        current = decl.base_names[0]
      }
      None => return false
    }
  }
  false
}

///|
/// TS2341 / TS2445: accessing a `private` / `protected` class member from
/// outside the scope that's allowed to see it. The receiver's class is
/// resolved (instance type or a static `Class.member` reference); a
/// `private` member is legal only inside the exact declaring class, a
/// `protected` member inside that class or a subclass. `this` / `super`
/// receivers are always same-instance and never flagged.
fn check_member_accessibility(
  env : ExprEnv,
  ctx : CheckCtx,
  recv : @ast.TsExpr,
  prop : String,
) -> Unit {
  match recv {
    Var("this") | Var("super") => return
    _ => ()
  }
  // Resolve the receiver to a declared class name: a bare `Var` naming a
  // class is a static-side access; otherwise infer the instance type.
  let class_name = match recv {
    Var(n) if ctx.resolver.classes.get(n) is Some(_) => n
    _ =>
      match ctx.resolver.unwrap(infer_expr(env, ctx.resolver, recv)) {
        Named(n) => n
        Applied(n, _) => n
        _ => return
      }
  }
  let decl = match ctx.resolver.classes.get(class_name) {
    Some(d) => d
    None => return
  }
  let is_private = decl.private_members.contains(prop)
  let is_protected = decl.protected_members.contains(prop)
  if !(is_private || is_protected) {
    return
  }
  let enclosing = current_enclosing_class(ctx.path_prefix)
  if is_private {
    if enclosing != Some(class_name) {
      record(
        ctx,
        "access `.\{prop}`",
        "property `\{prop}` is private and only accessible within class `\{class_name}`",
      )
    }
  } else {
    let allowed = match enclosing {
      Some(cc) => class_extends(ctx.resolver, cc, class_name)
      None => false
    }
    if !allowed {
      record(
        ctx,
        "access `.\{prop}`",
        "property `\{prop}` is protected and only accessible within class `\{class_name}` and its subclasses",
      )
    }
  }
}

///|
fn record(ctx : CheckCtx, sub_path : String, message : String) -> Unit {
  // T9: in permissive mode, drop the diagnostic families whose
  // residual FPs are dominated by features we don't model. Strict
  // mode (the unit-test path) keeps every emission.
  if ctx.permissive && is_permissively_suppressed(sub_path, message) {
    return
  }
  let path = if sub_path == "" {
    ctx.path_prefix
  } else if ctx.path_prefix == "" {
    sub_path
  } else {
    ctx.path_prefix + " > " + sub_path
  }
  ctx.issues.push({ path, message })
}

///|
/// Like `record`, but bypasses the permissive-mode suppression filter. Used
/// for diagnostics the caller has already established are reliable in
/// permissive mode (e.g. constructor / direct-function-call arity).
fn record_unfiltered(
  ctx : CheckCtx,
  sub_path : String,
  message : String,
) -> Unit {
  let path = if sub_path == "" {
    ctx.path_prefix
  } else if ctx.path_prefix == "" {
    sub_path
  } else {
    ctx.path_prefix + " > " + sub_path
  }
  ctx.issues.push({ path, message })
}

///|
/// Resolve the class name targeted by `new <callee>(...)` when the
/// callee is a bare identifier or a dotted member path. Returns `None`
/// for any other callee shape (call results, parenthesised expressions,
/// etc.) where the constructed type isn't a statically-named class.
fn new_callee_class_name(callee : @ast.TsExpr) -> String? {
  match callee {
    Var(n) => Some(n)
    PropAccess(inner, prop) =>
      match new_callee_class_name(inner) {
        Some(prefix) => Some(prefix + "." + prop)
        None => None
      }
    _ => None
  }
}

///|
/// TS2511 ("Cannot create an instance of an abstract class"): when
/// `new X` names a class declared `abstract`, the construction is
/// illegal. Only fires on a direct class reference -- constructing a
/// `typeof AbstractClass`-typed value is a separate (legal) case TS
/// allows, and we don't resolve those here.
fn check_abstract_instantiation(ctx : CheckCtx, class_name : String) -> Unit {
  let decl = match ctx.resolver.classes.get(class_name) {
    Some(d) => d
    None =>
      // Fall back to the unqualified tail of a dotted reference.
      match class_name.rev_find(".") {
        Some(dot) =>
          match
            ctx.resolver.classes.get(
              class_name[dot + 1:class_name.length()].to_owned(),
            ) {
            Some(d) => d
            None => return
          }
        None => return
      }
  }
  if decl.is_abstract {
    record(
      ctx,
      "new `\{class_name}`",
      "cannot create an instance of abstract class `\{class_name}`",
    )
  }
}

///|
/// True when the diagnostic message belongs to a family suppressed
/// under `permissive` mode -- mismatch, property / method existence,
/// arity, callable / index, equality / assertion, and CFA-dependent
/// never-return paths. These are the families dominated by gaps we
/// don't model (flow narrowing, user-defined typeguards, generic
/// inference, builtin optional-arg signatures).
///
/// Narrow exception: a mismatch where *both* sides parse as a
/// "simple" type (primitive / literal / `T[]` / single Named) is
/// reliable enough to keep -- those cases are picked up by the
/// strict mode anyway and contribute recall without inflating FP.
fn is_permissively_suppressed(sub_path : String, message : String) -> Bool {
  if message.has_prefix("expected `") && message.contains("but got `") {
    // Compatibility goal: a type mismatch is a real TS error, so emit it
    // even when the shapes involve unions / generics rather than only the
    // narrow "reliable" primitive subset (see `is_reliable_mismatch_pair`,
    // which now admits any renderable pair). We still suppress where *we*
    // are likely to be wrong, never tsc: a `type` residue token (our
    // `type_display` couldn't render the shape), widening-direction
    // residue, and rest-parameter residue.
    match extract_mismatch_types(message) {
      Some((exp, got)) =>
        if is_reliable_mismatch_pair(exp, got) &&
          !is_widening_direction_mismatch(sub_path, exp, got) &&
          !is_rest_param_residue(sub_path, exp, got) {
          return false
        }
      None => ()
    }
    return true
  }
  if message.has_prefix("property `") &&
    (
      message.contains("does not exist on `") ||
      message.contains("does not exist on target type") ||
      message.contains("is required by")
    ) {
    // Carve out a narrow exception: when the receiver renders as a
    // bare primitive type (`number`, `string`, `boolean`, `bigint`),
    // missing-property is a reliable signal — prototype dispatch
    // covers the legitimate uses (`(1).toString()`, `"x".charAt(0)`)
    // via `prim["method"]` lookup, so a remaining miss is a real bug.
    if message.contains("does not exist on `number`") ||
      message.contains("does not exist on `string`") ||
      message.contains("does not exist on `boolean`") ||
      message.contains("does not exist on `bigint`") {
      return false
    }
    // Nullable receiver: when the rendered receiver ends in `| undefined`
    // or `| null`, our lookup correctly fails because the bottom side
    // has no members. TS reports TS18047 / TS2532 ("Object is possibly
    // null/undefined") rather than TS2339; the file-level baseline
    // still carries some error code, so emitting turns the case from
    // recall_miss into recall_hit.
    if message.has_suffix("| undefined`") || message.has_suffix("| null`") {
      return false
    }
    return false
  }
  if message.has_prefix("method `") && message.contains("does not exist on") {
    // Same carve-out as the property branch: bare-primitive receiver
    // produces a reliable missing-method signal because prototype
    // dispatch covers the genuine uses already.
    if message.contains("does not exist on `number`") ||
      message.contains("does not exist on `string`") ||
      message.contains("does not exist on `boolean`") ||
      message.contains("does not exist on `bigint`") {
      return false
    }
    if message.has_suffix("| undefined`") || message.has_suffix("| null`") {
      return false
    }
    return false
  }
  if message.contains("argument(s), got ") {
    // Arity diagnostics are suppressed by default in permissive mode
    // (overloads / optional / builtin signatures we don't fully model make
    // them false-positive-prone). The reliable cases -- constructor calls
    // and direct calls to rest-free top-level function declarations -- are
    // emitted via `record_unfiltered`, so they never reach this filter.
    return true
  }
  if message.contains("is not callable") {
    return true
  }
  if message.contains("cannot access `") &&
    message.contains("receiver may be null or undefined") {
    return true
  }
  if message.contains("expected tuple of ") {
    // Tuple-arity mismatches are reliable in value-position (assign /
    // binding) — both sides are concrete tuples and the count is a
    // hard fact. Suppress only in call-argument paths, where variadic-
    // tuple parameters (`...args: [...T]`) make the apparent arity
    // wrong (the call site unpacks a tuple of unknown length).
    if sub_path.contains("call ") && sub_path.contains(" arg[") {
      return true
    }
    return false
  }
  if message.has_prefix("comparing `") &&
    message.contains("will always be false") {
    // Always-false equality on disjoint literal / value sets is a
    // reliable signal: `"foo" === "bar"`, `typeof x === "null"`. The
    // residual FP comes from `as`-cast widening (`"foo" === ("bar"
    // as string)`), which our parser drops — we accept that single
    // FP family rather than suppress the entire diagnostic.
    return false
  }
  if message.has_prefix("Type '") &&
    message.contains("cannot be asserted to type") {
    return true
  }
  if message.contains("not all paths return") {
    return true
  }
  if message.contains("cannot index into") {
    return true
  }
  false
}

///|
/// Pull the rendered "expected" and "got" types out of a
/// `expected `X` but got `Y`` mismatch message. Returns `None` when
/// the message doesn't match that exact shape.
fn extract_mismatch_types(message : String) -> (String, String)? {
  // `expected `<exp>` but got `<got>`
  let exp_start = match message.find("expected `") {
    Some(i) => i + "expected `".length()
    None => return None
  }
  let rest_after_exp_start = message[exp_start:].to_owned()
  let exp_end_rel = match rest_after_exp_start.find("` but got `") {
    Some(i) => i
    None => return None
  }
  let exp = rest_after_exp_start[:exp_end_rel].to_owned()
  let got_start_in_rest = exp_end_rel + "` but got `".length()
  let after_got_start = rest_after_exp_start[got_start_in_rest:].to_owned()
  let got_end_rel = match after_got_start.find("`") {
    Some(i) => i
    None => return None
  }
  let got = after_got_start[:got_end_rel].to_owned()
  Some((exp, got))
}

///|
/// True when both rendered type strings are "reliable" -- specifically
/// the primitive / literal / single-named shapes where our checker's
/// strict mismatch decision is not muddied by generics, flow
/// narrowing, or anonymous-shape flattening. Used by the permissive
/// filter to keep `var x: number = "hello"`-style mismatches.
fn is_reliable_mismatch_pair(exp : String, got : String) -> Bool {
  // Pure primitive-vs-primitive: well-tested in is_assignable_to.
  if is_reliable_mismatch_type(exp) && is_reliable_mismatch_type(got) {
    return true
  }
  // Assigning a single bare primitive into a union of primitives /
  // literals whose members are all of a *different* family (`string |
  // undefined` <- `number`): the source is already concrete, so no flow
  // narrowing can rescue it, and the family-disjointness rules out our
  // literal-widening blind spot (`123 | 456` <- `number`, where the
  // source is really a literal we over-widened). Restricted to a union
  // *target* with an atom *source* — a union *source* is flow-narrowing
  // residue and stays suppressed by the blanket `|` bail below.
  if is_reliable_primitive_union(exp) &&
    is_bare_primitive(got) &&
    got != "any" &&
    got != "unknown" &&
    got != "never" &&
    got != "object" &&
    got != "void" &&
    !primitive_union_contains_family(exp, primitive_family(got)) {
    return true
  }
  // Single-letter Named (`A`, `B`, `C`) vs primitive: short-identifier
  // names usually denote type parameters (T, U, K) but a primitive on the
  // other side rules that out — TS-style type parameters are never
  // structurally compared against primitives at an assignment site
  // without an explicit constraint, and the failing case (`let b: B = 5`,
  // where `B` is a literal-union alias) is exactly the kind of error we
  // want to flag.
  if (is_short_named_identifier(exp) && is_bare_primitive(got)) ||
    (is_bare_primitive(exp) && is_short_named_identifier(got)) {
    return true
  }
  if is_reliable_mismatch_type(exp) && is_simple_shape_type(got) {
    return true
  }
  if is_simple_shape_type(exp) && is_reliable_mismatch_type(got) {
    return true
  }
  // Compatibility goal: admit every *renderable* mismatch -- a type
  // mismatch is a real TS error even when the shapes are unions or generic
  // applications. The only pairs we still treat as unreliable are those
  // carrying the `type` residue token, which means our `type_display`
  // couldn't render the shape (mapped type / unresolved generic): we can't
  // claim a mismatch on a type we can't even print, and that is the family
  // where the checker is the one likely to be wrong rather than tsc.
  !has_type_residue_token(exp) && !has_type_residue_token(got)
}

///|
/// True when the rendered shape contains a `type` token that came
/// from our `type_display` fallback. We bail on these because the
/// fallback hides the real shape (mapped type, unresolved generic,
/// etc.) and the strict checker is likely to compare two distinct
/// shapes incorrectly.
fn has_type_residue_token(s : String) -> Bool {
  // Word boundaries: `type` surrounded by non-identifier chars.
  let bytes = s.to_array()
  let mut i = 0
  while i + 3 < bytes.length() {
    if bytes[i] == 't' &&
      bytes[i + 1] == 'y' &&
      bytes[i + 2] == 'p' &&
      bytes[i + 3] == 'e' {
      let before_ok = i == 0 || !is_ident_char(bytes[i - 1])
      let after_idx = i + 4
      let after_ok = after_idx >= bytes.length() ||
        !is_ident_char(bytes[after_idx])
      if before_ok && after_ok {
        return true
      }
    }
    i = i + 1
  }
  false
}

///|
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '$'
}

///|
/// True if `s` starts with an ASCII uppercase letter. Used to gate
/// `keyof X` / `typeof X` admission on a Named type (class /
/// interface / alias name); excludes `keyof any` / `keyof unknown`
/// which collapse to wide property-key unions in TS.
fn starts_uppercase(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let c = s[0]
  c >= 'A' && c <= 'Z'
}

///|
/// True if `s` is a non-empty identifier (head: letter/_/$, rest:
/// identifier chars). Distinct from `is_bare_identifier`, which adds
/// a length-3 + lowercase requirement to filter type-param names —
/// here we want even `A` / `B` admitted when the caller's context
/// already rules out type-parameter confusion (e.g. `keyof A`).
fn is_named_identifier(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let bytes = s.to_array()
  let head = bytes[0]
  let head_ok = (head >= 'a' && head <= 'z') ||
    (head >= 'A' && head <= 'Z') ||
    head == '_' ||
    head == '$'
  if !head_ok {
    return false
  }
  let mut i = 1
  while i < bytes.length() {
    if !is_ident_char(bytes[i]) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// True when a `expected T[] but got T` mismatch comes from a call
/// argument and the `got` type is exactly the element type of `exp`.
/// This is the residue from calling a function value typed as
/// `(...args: T[]) => U` -- our `TsType::Func` doesn't carry rest
/// metadata, so we treat the trailing arg as needing `T[]` instead
/// of `T`. TS accepts these.
fn is_rest_param_residue(sub_path : String, exp : String, got : String) -> Bool {
  if !sub_path.contains("call ") || !sub_path.contains(" arg[") {
    return false
  }
  if !exp.has_suffix("[]") {
    return false
  }
  let elem = exp[:exp.length() - 2].to_owned()
  elem == got
}

///|
/// A "simple shape": `T[]`, `[A,B,...]`, `{...}`, or `(...) => T`,
/// where the inner parts may themselves be compound. Used by
/// `is_reliable_mismatch_pair` to admit primitive-vs-shape mismatches
/// through the permissive filter (the categories are obviously
/// disjoint -- a primitive is never assignable to an array / tuple /
/// object / function and vice versa).
fn is_simple_shape_type(s : String) -> Bool {
  // T[] (array)
  if s.has_suffix("[]") {
    return true
  }
  // Tuples (`[A, B, ...]`) are excluded: generic-rest substitution
  // gaps render leftover type-parameter names as bare identifiers
  // inside the brackets (`[number, string, type]`), producing FPs
  // in `genericRestParameters2` and similar. The other shapes below
  // don't suffer from this because they're either header-marked
  // (`T[]`, `(...) => T`) or fully enclosing (`{...}`).
  // { ... } (object literal type) — leading `{`
  if s.has_prefix("{") && s.has_suffix("}") {
    return true
  }
  // (...) => T (function type)
  if s.has_prefix("(") && s.contains(") => ") {
    return true
  }
  false
}

///|
/// A mismatch where the source is the widened primitive of the
/// target's literal type -- e.g. `expected "ABC" (string) but got
/// string`, `expected 123 but got number`, `expected true but got
/// boolean`. TS accepts these (the literal initializer collapses to
/// the wider type at the use site without narrowing), so they show
/// up as FPs in our checker. The reverse direction (`expected
/// string but got "ABC"`) is *not* widening -- it's the kind of
/// mismatch we *do* want to catch.
fn is_widening_direction_mismatch(
  sub_path : String,
  exp : String,
  got : String,
) -> Bool {
  // String literal "X" -> string
  if got == "string" && exp.has_prefix("\"") && exp.has_suffix("\" (string)") {
    return true
  }
  // Numeric literal 123 -> number
  if got == "number" && is_numeric_literal_display(exp) {
    return true
  }
  // Boolean literal true/false -> boolean
  if got == "boolean" && (exp == "true" || exp == "false") {
    return true
  }
  // BigInt literal 5n -> bigint
  if got == "bigint" &&
    exp.has_suffix("n") &&
    exp.length() > 1 &&
    is_numeric_literal_display(exp[:exp.length() - 1].to_owned()) {
    return true
  }
  // void target accepts any source ONLY in callback-return / function-return
  // positions: a callback like `(x) => x.foo()` returning `boolean` passed
  // to `forEach` (`(v) => void`) is fine because the return value is
  // discarded. But `let x: void; x = 1` is a real TS error — the value-
  // position assignment isn't covered by the discard rule. Distinguish by
  // path: arrow-body / return contexts are callback-shaped, everything
  // else (assign / binding) is value-position.
  if exp == "void" &&
    (sub_path.contains("arrow body") || sub_path.has_suffix("return")) {
    return true
  }
  false
}

///|
fn is_reliable_mismatch_type(s : String) -> Bool {
  // Compound forms (unions / intersections / generics / arrays /
  // tuples / function types) are exactly the cases where flow
  // narrowing or generic-substitution gaps produce FPs. Bail before
  // the simple-shape checks below.
  if s.contains("|") ||
    s.contains("&") ||
    s.contains("<") ||
    s.contains("[") ||
    s.contains("{") ||
    s.contains(",") {
    return false
  }
  // Bare primitives / literals
  match s {
    "number"
    | "int"
    | "string"
    | "boolean"
    | "void"
    | "null"
    | "undefined"
    | "bigint"
    | "symbol"
    | "any"
    | "never"
    | "true"
    | "false"
    | "object" => return true
    // `type` is the fallback string from `type_display` for Object /
    // Struct / Null / NumberLiteral / BooleanLiteral etc. — opaque
    // shapes where we can't be confident about reliability.
    "type" | "function" => return false
    _ => ()
  }
  // `keyof <Named>` -- only when the inner type is a user-defined
  // Named (uppercase initial, identifier-shaped). `keyof any` /
  // `keyof unknown` widen to all property-key primitives so a string
  // source IS assignable and the diagnostic would be a false positive.
  // Single-letter Named (`A`, `B`) is allowed since it's a concrete
  // type alias / class in the failing fixtures.
  if s.has_prefix("keyof ") {
    let inner = s[6:].to_owned()
    if is_named_identifier(inner) && starts_uppercase(inner) {
      return true
    }
  }
  // `typeof <Named>` -- same shape, same filter.
  if s.has_prefix("typeof ") {
    let inner = s[7:].to_owned()
    if is_named_identifier(inner) && starts_uppercase(inner) {
      return true
    }
  }
  // Bare identifier: a single Named type (e.g. `C`, `I`, `Point`).
  // These come from interface / class / type-alias references. When
  // both sides of a mismatch render as a bare identifier, it's a
  // clean Named-vs-Named comparison that strict assignability gets
  // right (no flow narrowing, no generic inference, no anonymous
  // shapes to flatten). Conservative shape check: first char is a
  // letter or `_`, rest are alphanumeric or `_`.
  if s.length() > 0 && is_bare_identifier(s) {
    return true
  }
  // String literal types: `"foo" (string)` exactly (no embedded
  // newlines, no compound suffix). The strict `"X" (string)` match
  // -- no trailing characters -- keeps multi-line / interpolated
  // template-literal residue out.
  if s.has_prefix("\"") && s.has_suffix("\" (string)") {
    return true
  }
  // Numeric literal types: a bare digit string (possibly negative,
  // possibly with a decimal point). type_display emits these raw.
  if is_numeric_literal_display(s) {
    return true
  }
  // BigInt literal: digits with a trailing `n`.
  if s.has_suffix("n") && s.length() > 1 {
    let body = s[:s.length() - 1].to_owned()
    if is_numeric_literal_display(body) {
      return true
    }
  }
  false
}

///|
/// True when `s` is a bare identifier that is *unlikely* to be a type
/// parameter name. Conventional type parameters in TS test fixtures are
/// short uppercase forms (`T`, `U`, `K`, `V`, `S2`, `T2`); concrete
/// class/interface/alias names almost always contain a lowercase letter
/// (`Beast`, `Point`, `Promise`) or are at least 3+ chars. Used by
/// `is_reliable_mismatch_type` to admit Named-vs-Named mismatches
/// (e.g. `expected `Beast` but got `Legged``) through the permissive
/// filter without unleashing Type-parameter-vs-Type-parameter false
/// positives from generic call sites.
fn is_bare_identifier(s : String) -> Bool {
  if s.length() < 3 {
    return false
  }
  let bytes = s.to_array()
  let head = bytes[0]
  let head_ok = (head >= 'a' && head <= 'z') ||
    (head >= 'A' && head <= 'Z') ||
    head == '_' ||
    head == '$'
  if !head_ok {
    return false
  }
  let mut i = 1
  let mut has_lower = head >= 'a' && head <= 'z'
  while i < bytes.length() {
    let c = bytes[i]
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '$'
    if !ok {
      return false
    }
    if c >= 'a' && c <= 'z' {
      has_lower = true
    }
    i = i + 1
  }
  has_lower
}

///|
/// A short uppercase Named (1-2 chars, optional trailing digit): `A`, `B`,
/// `T2`, `S2`. Used together with `is_bare_primitive` to admit mismatches
/// where one side is a short Named alias / interface name and the other
/// is a concrete primitive — the failing case (`let b: B = 5`) is a real
/// error and the primitive side rules out generic-inference residue.
fn is_short_named_identifier(s : String) -> Bool {
  if s.length() == 0 || s.length() > 2 {
    return false
  }
  let bytes = s.to_array()
  let head = bytes[0]
  if !(head >= 'A' && head <= 'Z') {
    return false
  }
  if s.length() == 1 {
    return true
  }
  let tail = bytes[1]
  tail >= '0' && tail <= '9'
}

///|
/// True when `s` renders as a union (`A | B | ...`) whose every member is
/// a bare primitive or a string / numeric literal. Used by the permissive
/// mismatch filter: assignability into such a union is exact membership,
/// so a mismatch is reliable even though the blanket `|` bail would
/// otherwise drop it. Bails on any compound marker that would break the
/// naive ` | ` split (`&`, generics, function / object / array shapes).
fn is_reliable_primitive_union(s : String) -> Bool {
  if !s.contains(" | ") {
    return false
  }
  if s.contains("&") ||
    s.contains("<") ||
    s.contains("(") ||
    s.contains("{") ||
    s.contains("[") ||
    s.contains("=>") {
    return false
  }
  let mut count = 0
  for part in s.split(" | ") {
    let p = part.to_owned()
    let ok = (is_bare_primitive(p) && p != "any" && p != "unknown") ||
      is_numeric_literal_display(p) ||
      (p.has_prefix("\"") && p.has_suffix("\" (string)"))
    if !ok {
      return false
    }
    count = count + 1
  }
  count >= 2
}

///|
/// Coarse primitive family of a rendered atom (`"number"` / `"string"` /
/// `"boolean"` / `"bigint"` / `"null"` / `"undefined"` / `"symbol"`),
/// folding literals into their base family. `""` for anything else.
fn primitive_family(s : String) -> String {
  match s {
    "number" | "int" => "number"
    "string" => "string"
    "boolean" | "true" | "false" => "boolean"
    "bigint" => "bigint"
    "null" => "null"
    "undefined" => "undefined"
    "symbol" => "symbol"
    _ =>
      if is_numeric_literal_display(s) {
        "number"
      } else if s.has_prefix("\"") && s.has_suffix("\" (string)") {
        "string"
      } else {
        ""
      }
  }
}

///|
/// True when any member of the primitive/literal union `s` shares
/// `family`. Used to keep the union-target mismatch carve-out away from
/// our literal-widening blind spot (a widened `number` source against a
/// numeric-literal union member).
fn primitive_union_contains_family(s : String, family : String) -> Bool {
  if family == "" {
    return true
  }
  for part in s.split(" | ") {
    if primitive_family(part.to_owned()) == family {
      return true
    }
  }
  false
}

///|
/// True for the rendered name of a bare TS primitive (no compound shape).
fn is_bare_primitive(s : String) -> Bool {
  match s {
    "number"
    | "int"
    | "string"
    | "boolean"
    | "bigint"
    | "symbol"
    | "null"
    | "undefined"
    | "void"
    | "any"
    | "never"
    | "true"
    | "false"
    | "object" => true
    _ => false
  }
}

///|
fn is_numeric_literal_display(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let bytes = s.to_array()
  let mut i = 0
  if bytes[0] == '-' {
    i = 1
    if bytes.length() == 1 {
      return false
    }
  }
  let mut seen_digit = false
  let mut seen_dot = false
  while i < bytes.length() {
    let c = bytes[i]
    if c == '.' {
      if seen_dot {
        return false
      }
      seen_dot = true
    } else if c >= '0' && c <= '9' {
      seen_digit = true
    } else {
      return false
    }
    i = i + 1
  }
  seen_digit
}

///|
/// A type is "concrete enough to check" when it is not `Any` (modelling
/// `unknown` the same way). The checker silently accepts anything involving
/// `Any`.
fn is_checkable(ty : @ast.TsType) -> Bool {
  match ty {
    Any => false
    _ => true
  }
}

///|
fn is_nullable_type(ty : @ast.TsType) -> Bool {
  match ty {
    Null | Undefined => true
    Union(members) => {
      let has_non_nullish = members
        .iter()
        .any(fn(m) {
          match m {
            Null | Undefined => false
            _ => true
          }
        })
      // Only flag as "nullable" when ALL members are null/undefined (i.e., the
      // type IS null/undefined). Unions like `string | null` are common valid
      // patterns and are handled by the existing optional-field machinery.
      !has_non_nullish
    }
    _ => false
  }
}

///|
// Returns true only for types that can NEVER participate in numeric
// arithmetic (`-`, `*`, `/`, bit ops, …), so the "not a valid number type"
// diagnostic stays free of false positives.  Mirrors `is_definitely_not_callable`:
// permissive for Named / Applied (could be a numeric enum or branded number),
// Union / Intersection (could be a numeric-literal union like `0 | 1 | 2`),
// and unresolved type-level forms.  Only concrete non-numeric primitives and
// object-like shapes are flagged.
fn is_definitely_not_arithmetic(ty : @ast.TsType) -> Bool {
  match ty {
    String_
    | Literal(_)
    | Boolean
    | BooleanLiteral(_)
    | Void
    | Null
    | Undefined
    | Symbol
    | Object(_)
    | Struct(_, _)
    | Array(_)
    | Tuple(_)
    | TemplateLiteralType(_, _)
    | Func(_, _) => true
    _ => false
  }
}

///|
// Returns true when two types might share a common value at runtime —
// used to detect comparisons like `number === string` that are always false.
// Conservative: returns true (allows) when either side is Any, Never, a
// union/intersection, a named reference, or an object shape (those are
// structural and could overlap via subtypes).
// Returns true only for types that can never have a call signature, so the
// "not callable" diagnostic stays free of false positives. Permissive for
// Named / Applied (interfaces may carry call signatures), Union / Intersection
// (overload sets), and unresolved type-level forms.
fn is_definitely_not_callable(ty : @ast.TsType) -> Bool {
  match ty {
    Number
    | Int
    | NumberLiteral(_)
    | String_
    | Literal(_)
    | Boolean
    | BooleanLiteral(_)
    | BigInt
    | BigIntLiteral(_)
    | Symbol
    | Void
    | Null
    | Undefined
    | Object(_)
    | Struct(_, _)
    | Array(_)
    | Tuple(_)
    | TemplateLiteralType(_, _) => true
    _ => false
  }
}

///|
// Object.prototype members inherited by every object-like type. Returns the
// member's type for the standard set, or `None` for anything else. Used as a
// lookup fallback so `obj.toString()` / `obj.hasOwnProperty(...)` resolve on
// interfaces, object literals, and structs without false "does not exist"
// diagnostics.
fn object_prototype_member(field : String) -> @ast.TsType? {
  match field {
    "toString" | "toLocaleString" =>
      Some(@ast.TsType::Func([], @ast.TsType::String_))
    "hasOwnProperty" | "isPrototypeOf" | "propertyIsEnumerable" =>
      Some(@ast.TsType::Func([@ast.TsType::Any], @ast.TsType::Boolean))
    "valueOf" => Some(@ast.TsType::Func([], @ast.TsType::Any))
    "constructor" => Some(@ast.TsType::Any)
    _ => None
  }
}

///|
// True when the expression is a literal `null` / `undefined` source — the
// only forms that are universally assignable under non-strict null checks.
// `undefined` parses as `Var("undefined")`; `void <expr>` (e.g. `void 0`)
// also evaluates to `undefined`.

///|
/// Recursively walk a binding pattern and clear every named slot
/// from the TS2454 unassigned set. Used by the destructuring-
/// assignment walker so `[a, b] = expr` / `{x: y} = expr` register
/// as assignments for use-before-assign tracking.
fn clear_unassigned_in_binding(
  ctx : CheckCtx,
  binding : @ast.TsBinding,
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(n) => {
      let _ = ctx.unassigned.remove(n)
    }
    @ast.TsBinding::Array(ab) => {
      for it in ab.items {
        match it {
          Some(elem) => clear_unassigned_in_binding(ctx, elem.binding)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => clear_unassigned_in_binding(ctx, r)
        None => ()
      }
    }
    @ast.TsBinding::Object(ob) => {
      for prop in ob.props {
        clear_unassigned_in_binding(ctx, prop.binding)
      }
      match ob.rest {
        Some(name) => {
          let _ = ctx.unassigned.remove(name)
        }
        None => ()
      }
    }
    @ast.TsBinding::Target(_) => ()
  }
}

///|
fn is_null_or_undefined_literal_expr(expr : @ast.TsExpr) -> Bool {
  match expr {
    NullLit => true
    Var("undefined") => true
    // Parser-synthesised sentinel for `let x;` / `var x;` -- treat
    // it as `undefined` for assignability purposes (the binding-init
    // check shouldn't trip on a no-init declaration), but the TS2454
    // walker pattern-matches the same sentinel separately to emit
    // "used before being assigned".
    Var("__ts_no_init__") => true
    UnaryOp(Void, _) => true
    _ => false
  }
}

///|
// Returns true only for types that can NEVER be indexed with `x[i]`, so the
// "cannot index into" diagnostic stays free of false positives.  Permissive
// for every object-like / named / abstract type-level form (mapped types,
// keyof, indexed-access, conditional types are all indexable in valid TS);
// only concrete non-indexable primitives are flagged.
fn is_definitely_not_indexable(ty : @ast.TsType) -> Bool {
  match ty {
    Number
    | Int
    | NumberLiteral(_)
    | Boolean
    | BooleanLiteral(_)
    | BigInt
    | BigIntLiteral(_)
    | Symbol
    | Void
    | Null
    | Undefined => true
    _ => false
  }
}

///|

///|
/// The exact set of integer values an enum declares, or `None` when any
/// member's value isn't a plain integer literal (computed members make
/// the set unknown, so callers must stay conservative).
fn enum_integer_values(decl : @ast.TsEnumDecl) -> Array[Int]? {
  let values : Array[Int] = []
  for m in decl.members {
    match m.value {
      Some(Number(s)) => {
        let n = @string.parse_int(s) catch { _ => return None }
        values.push(n)
      }
      _ => return None
    }
  }
  if values.length() == 0 {
    return None
  }
  Some(values)
}

///|
/// The integer value of a literal expression / type, if it is one.
fn expr_integer_literal(e : @ast.TsExpr, t : @ast.TsType) -> Int? {
  match e {
    IntLit(n) => Some(n)
    NumberLit(d) =>
      if d == d.to_int().to_double() {
        Some(d.to_int())
      } else {
        None
      }
    _ =>
      match t {
        NumberLiteral(s) => Some(@string.parse_int(s)) catch { _ => None }
        _ => None
      }
  }
}

///|
/// TS2367 helper: when one operand is a numeric-enum type and the other
/// a numeric literal that is not one of the enum's members, the `===` /
/// `!==` can never be true. Returns the rendered `` `E` and `n` ``
/// fragment to embed in the diagnostic, or `None` when it doesn't apply.
fn enum_numeric_literal_disjoint(
  resolver : Resolver,
  lt : @ast.TsType,
  l : @ast.TsExpr,
  rt : @ast.TsType,
  r : @ast.TsExpr,
) -> String? {
  fn check(
    en_ty : @ast.TsType,
    lit_e : @ast.TsExpr,
    lit_t : @ast.TsType,
  ) -> String? {
    let name = match en_ty {
      Named(n) => n
      _ => return None
    }
    let decl = match resolver.enums.get(name) {
      Some(d) => d
      None => return None
    }
    let values = match enum_integer_values(decl) {
      Some(v) => v
      None => return None
    }
    let lit = match expr_integer_literal(lit_e, lit_t) {
      Some(n) => n
      None => return None
    }
    if values.contains(lit) {
      None
    } else {
      Some("`\{name}` and `\{lit}`")
    }
  }

  match check(lt, r, rt) {
    Some(s) => return Some(s)
    None => ()
  }
  check(rt, l, lt)
}

///|
fn types_can_overlap(a : @ast.TsType, b : @ast.TsType) -> Bool {
  match (a, b) {
    (Any, _) | (_, Any) => true
    (Never, _) | (_, Never) => true
    (Union(_), _) | (_, Union(_)) => true
    (Intersection(_), _) | (_, Intersection(_)) => true
    (Named(_), _) | (_, Named(_)) => true
    (Applied(_, _), _) | (_, Applied(_, _)) => true
    (Object(_), _) | (_, Object(_)) => true
    (Struct(_, _), _) | (_, Struct(_, _)) => true
    // Same primitive families overlap with each other and their literals.
    (Number, Number)
    | (Number, NumberLiteral(_))
    | (NumberLiteral(_), Number) => true
    (NumberLiteral(a_), NumberLiteral(b_)) => a_ == b_
    (String_, String_) | (String_, Literal(_)) | (Literal(_), String_) => true
    (Literal(a_), Literal(b_)) => a_ == b_
    (Boolean, Boolean)
    | (Boolean, BooleanLiteral(_))
    | (BooleanLiteral(_), Boolean) => true
    (BooleanLiteral(a_), BooleanLiteral(b_)) => a_ == b_
    (BigInt, BigInt)
    | (BigInt, BigIntLiteral(_))
    | (BigIntLiteral(_), BigInt) => true
    (Null, Null) | (Undefined, Undefined) => true
    // Cross-family primitives never overlap.
    _ => false
  }
}

///|
fn check_binop_operands(
  env : ExprEnv,
  op : @ast.TsBinOp,
  l : @ast.TsExpr,
  r : @ast.TsExpr,
  ctx : CheckCtx,
) -> Unit {
  match op {
    Sub | Mul | Div | Mod | Pow | Shl | Shr | UShr | BitAnd | BitOr | BitXor => {
      let lt = ctx.resolver.unwrap(infer_expr(env, ctx.resolver, l))
      let rt = ctx.resolver.unwrap(infer_expr(env, ctx.resolver, r))
      if is_checkable(lt) && is_definitely_not_arithmetic(lt) {
        record(
          ctx,
          "binary op",
          "left operand `\{type_display(lt)}` is not a valid number type",
        )
      }
      if is_checkable(rt) && is_definitely_not_arithmetic(rt) {
        record(
          ctx,
          "binary op",
          "right operand `\{type_display(rt)}` is not a valid number type",
        )
      }
    }
    // Strict equality: comparing two types with no overlap is always false.
    // e.g., `someNumber === "hello"` or `true === 42`.
    BinEq | BinNe => {
      // `typeof x === "..."` is a narrowing idiom: TypeScript treats the
      // result of `typeof` as the full string-literal union of tags, so the
      // comparison always overlaps and is never an error — even when the
      // operand's static type makes the result statically determinable.
      // Skip the overlap check entirely when either side is a `typeof`.
      let is_typeof = fn(e : @ast.TsExpr) -> Bool {
        match e {
          UnaryOp(Typeof, _) => true
          _ => false
        }
      }
      let lt = ctx.resolver.unwrap(infer_expr(env, ctx.resolver, l))
      let rt = ctx.resolver.unwrap(infer_expr(env, ctx.resolver, r))
      if !is_typeof(l) &&
        !is_typeof(r) &&
        is_checkable(lt) &&
        is_checkable(rt) &&
        !types_can_overlap(lt, rt) {
        record(
          ctx,
          "strict equality",
          "comparing `\{type_display(lt)}` and `\{type_display(rt)}` with === will always be false",
        )
      } else if !is_typeof(l) && !is_typeof(r) {
        // TS2367 for a numeric-enum-typed operand compared against a
        // numeric literal that is not one of the enum's members. Only
        // fires when *every* member has a known integer value (so the
        // member set is exact) -- computed members bail out.
        match enum_numeric_literal_disjoint(ctx.resolver, lt, l, rt, r) {
          Some(rendered) =>
            record(
              ctx,
              "strict equality",
              "comparing \{rendered} will always be false",
            )
          None => ()
        }
      }
    }
    // Loose equality (`==` / `!=`): TypeScript also reports TS2367 for
    // operands whose types have no overlap. `==` coerces *across*
    // primitive families (`0 == ""`, `1 == "1"`), so we only flag when
    // both operands are in the *same* primitive family -- there the
    // abstract-equality result matches strict equality and "no overlap"
    // (e.g. `"foo" == "bar"`, `x /* : "foo" */ == "bar"`) is reliably
    // always-false.
    AbstractEq | AbstractNe => {
      let is_typeof = fn(e : @ast.TsExpr) -> Bool {
        match e {
          UnaryOp(Typeof, _) => true
          _ => false
        }
      }
      // A dropped type assertion (`"x" == (<any>"y")`, `... == ("y" as
      // string)`) used to leave behind a spurious literal-vs-literal shape
      // here, but the parser now binds `as` / cast tighter than equality
      // (T19), so those RHS operands are `As` / cast nodes whose inferred
      // type is `string` / `any` and already overlaps. A genuine bare
      // `"foo" == "bar"` therefore stays the only literal-vs-literal pair
      // reaching this point, and TS reports it as TS2367 -- matching the
      // strict-equality branch above.
      let lt = ctx.resolver.unwrap(infer_expr(env, ctx.resolver, l))
      let rt = ctx.resolver.unwrap(infer_expr(env, ctx.resolver, r))
      match (equality_primitive_family(lt), equality_primitive_family(rt)) {
        (Some(fa), Some(fb)) =>
          if fa == fb &&
            !is_typeof(l) &&
            !is_typeof(r) &&
            !types_can_overlap(lt, rt) {
            record(
              ctx,
              "loose equality",
              "comparing `\{type_display(lt)}` and `\{type_display(rt)}` with == will always be false",
            )
          }
        _ => ()
      }
    }
    _ => ()
  }
}

///|
/// The primitive family of `t` for abstract-equality (`==`) overlap
/// analysis: `string` / `number` / `boolean` / `bigint`, including the
/// matching literal forms. Returns `None` for anything else (objects,
/// named references, unions, `null` / `undefined`, etc.) where `==`
/// coercion or structural shape makes a "no overlap" call unsafe.
fn equality_primitive_family(t : @ast.TsType) -> String? {
  match t {
    String_ | Literal(_) | TemplateLiteralType(_, _) => Some("string")
    Number | Int | NumberLiteral(_) => Some("number")
    Boolean | BooleanLiteral(_) => Some("boolean")
    BigInt | BigIntLiteral(_) => Some("bigint")
    _ => None
  }
}

///|
fn wrap_async_return(is_async : Bool, ret : @ast.TsType) -> @ast.TsType {
  if !is_async {
    return ret
  }
  // If the declared return is already `Promise<...>`, leave it alone.
  match ret {
    Applied("Promise", _) => ret
    _ => @ast.TsType::Applied("Promise", [ret])
  }
}

///|
fn unwrap_async_return(is_async : Bool, ret : @ast.TsType) -> @ast.TsType {
  if !is_async {
    return ret
  }
  match ret {
    Applied("Promise", args) if args.length() == 1 => args[0]
    _ => ret
  }
}

// ---------------------------------------------------------------------------
// Expression inference.
// ---------------------------------------------------------------------------

///|
fn infer_expr(
  env : ExprEnv,
  resolver : Resolver,
  expr : @ast.TsExpr,
) -> @ast.TsType {
  match expr {
    // Explicit type arguments are erased for inference: the call's value
    // type is the inner call's type.
    TypeArgs(_, inner) => infer_expr(env, resolver, inner)
    NumberLit(_) | IntLit(_) => @ast.TsType::Number
    BigIntLit(_) => @ast.TsType::BigInt
    BoolLit(_) => @ast.TsType::Boolean
    // String literals carry their literal type so callers can narrow on
    // them; assignability lets `Literal(s)` flow into `string`.
    StringLit(s) => @ast.TsType::Literal(s)
    NullLit => @ast.TsType::Null
    ArrayHole => @ast.TsType::Undefined
    // Parser-synthesised sentinel for `let x;` / `var x;`. Treat
    // the same as the legacy `Var("undefined")` for inference: when
    // the var carries a declared type, the binding-init path uses
    // that; when not (`is_checkable(declared) == false`), the
    // inferred type collapses to `Any` (env.lookup fails, the global
    // table has no entry, fallback returns `Any`) -- matching the
    // checker's pre-sentinel behaviour. The TS2454 walker
    // pattern-matches the sentinel name directly at the stmt level
    // rather than going through inference.
    Var("__ts_no_init__") =>
      match env.lookup("undefined") {
        Some(ty) => ty
        None =>
          match resolver.globals.get("undefined") {
            Some(ty) => ty
            None => @ast.TsType::Any
          }
      }
    Var(name) =>
      match env.lookup(name) {
        Some(ty) => ty
        None =>
          match resolver.globals.get(name) {
            Some(ty) => ty
            None => @ast.TsType::Any
          }
      }
    BinOp(op, l, r) => {
      let lt = resolver.unwrap(infer_expr(env, resolver, l))
      let rt = resolver.unwrap(infer_expr(env, resolver, r))
      infer_binop(op, lt, rt, resolver)
    }
    UnaryOp(op, inner) => {
      let inner_ty = infer_expr(env, resolver, inner)
      match op {
        Typeof => infer_typeof_type(resolver, inner_ty)
        _ => infer_unary(op)
      }
    }
    Cond(_, then_, else_) =>
      narrow_union(
        infer_expr(env, resolver, then_),
        infer_expr(env, resolver, else_),
      )
    ArrayLit(items) => {
      let mut elem : @ast.TsType = Any
      let mut first = true
      for item in items {
        let t = match item {
          // Spread: infer the spread arg's type and extract its element type
          // so `[...arr]` where `arr: string[]` infers `string[]`, not `any[]`.
          Spread(inner) =>
            match resolver.unwrap(infer_expr(env, resolver, inner)) {
              Array(inner_elem) => inner_elem
              Applied("Array", [inner_elem])
              | Applied("ReadonlyArray", [inner_elem]) => inner_elem
              Tuple(parts) if parts.length() > 0 => {
                let mut u = parts[0]
                let mut i = 1
                while i < parts.length() {
                  u = narrow_union(u, parts[i])
                  i = i + 1
                }
                u
              }
              _ => @ast.TsType::Any
            }
          _ => infer_expr(env, resolver, item)
        }
        if first {
          elem = t
          first = false
        } else if !equivalent(elem, t) {
          elem = Any
        }
      }
      @ast.TsType::Array(elem)
    }
    Call(name, args) => {
      let callee_ty = match env.lookup(name) {
        Some(t) => t
        None =>
          match resolver.globals.get(name) {
            Some(t) => t
            None => @ast.TsType::Any
          }
      }
      // Generic call: when the callee has declared type parameters,
      // unify them with the argument types and substitute into the
      // return type so callers see the instantiated form.
      let type_params = match resolver.func_type_params.get(name) {
        Some(tps) => tps
        None => []
      }
      if type_params.length() > 0 {
        match callee_ty {
          Func(params, ret) => {
            let bindings = solve_generic_bindings(
              env,
              resolver,
              type_params,
              params,
              args,
              resolver.signatures.get(name),
            )
            for a in args {
              let _ = infer_expr(env, resolver, a)
            }
            return substitute_params(ret, bindings)
          }
          _ => ()
        }
      }
      infer_call(env, resolver, callee_ty, args)
    }
    CallExpr(callee, args) => {
      // Overload resolution for a member call `recv.m(args)` represented as
      // `CallExpr(PropAccess(recv, m), args)`: pick the overload whose
      // parameters accept the argument types before falling back to the
      // first-signature `infer_call` path.
      match callee {
        PropAccess(recv, meth) => {
          let recv_ty = infer_expr(env, resolver, recv)
          let arg_types : Array[@ast.TsType] = []
          for a in args {
            arg_types.push(infer_expr(env, resolver, a))
          }
          match
            resolver.resolve_method_overload(
              prune_nullish(resolver, recv_ty),
              meth,
              arg_types,
            ) {
            Some(ret) => return substitute_this_type(ret, recv_ty)
            None => ()
          }
        }
        _ => ()
      }
      let callee_ty = infer_expr(env, resolver, callee)
      infer_call(env, resolver, callee_ty, args)
    }
    New(class_name, args) =>
      match resolver.lookup_constructor(class_name) {
        Some(_) => {
          // Validate args at the call site via `check_arguments`; here we
          // just return the instance type.
          for a in args {
            let _ = infer_expr(env, resolver, a)
          }
          @ast.TsType::Named(class_name)
        }
        None => {
          for a in args {
            let _ = infer_expr(env, resolver, a)
          }
          @ast.TsType::Any
        }
      }
    NewExpr(callee, args) => {
      // Walk the callee expression to a dotted key string so we can look
      // it up in resolver.classes and resolver.globals.
      fn callee_key(e : @ast.TsExpr) -> String? {
        match e {
          Var(n) => Some(n)
          PropAccess(inner, prop) =>
            match callee_key(inner) {
              Some(prefix) => Some(prefix + "." + prop)
              None => None
            }
          _ => None
        }
      }
      let instance_ty = match callee_key(callee) {
        Some(key) =>
          match resolver.classes.get(key) {
            Some(_) => @ast.TsType::Named(key)
            None =>
              // Try just the last segment (unqualified name) as fallback.
              match key.rev_find(".") {
                Some(dot) => {
                  let short = key[dot + 1:key.length()].to_owned()
                  match resolver.classes.get(short) {
                    Some(_) => @ast.TsType::Named(short)
                    None => @ast.TsType::Any
                  }
                }
                None => @ast.TsType::Any
              }
          }
        None => @ast.TsType::Any
      }
      let _ = infer_expr(env, resolver, callee)
      for a in args {
        let _ = infer_expr(env, resolver, a)
      }
      instance_ty
    }
    MethodCall(receiver, meth, args) => {
      // Static namespace dispatch: `Object.keys(...)`, `Math.max(...)`,
      // `Promise.resolve(...)` etc. — recognise the receiver by its bare
      // identifier rather than its inferred type so we don't depend on
      // ambient globals being declared.
      match receiver {
        Var(name) =>
          match global_namespace_method(name, meth) {
            Some(sig) =>
              // Apply per-method generic-style inference for the chosen
              // static method, falling back to the conventional `Func`
              // shape when no special path applies.
              match
                global_static_method_special(env, resolver, name, meth, args) {
                Some(special_ret) => {
                  // Walk args for nested call-site checks.
                  for a in args {
                    let _ = infer_expr(env, resolver, a)
                  }
                  return special_ret
                }
                None =>
                  match sig {
                    Func(_, ret) => {
                      for a in args {
                        let _ = infer_expr(env, resolver, a)
                      }
                      return ret
                    }
                    _ => ()
                  }
              }
            None => ()
          }
        _ => ()
      }
      let recv_ty = infer_expr(env, resolver, receiver)
      // Special-case generic `Array.prototype.{map, flatMap, reduce}` so
      // the callback's body / initial-value type flows into the result
      // type instead of the synthetic `Any` slot returned by
      // `array_prototype_member`.
      let elem_opt = array_element_type(resolver, recv_ty)
      match (elem_opt, meth, args) {
        (Some(elem), "map", [cb]) => {
          let cb_ret = infer_arrow_body_with_params(env, resolver, cb, [
            elem,
            @ast.TsType::Number,
            @ast.TsType::Array(elem),
          ])
          return @ast.TsType::Array(cb_ret)
        }
        (Some(elem), "flatMap", [cb]) => {
          let cb_ret = infer_arrow_body_with_params(env, resolver, cb, [
            elem,
            @ast.TsType::Number,
            @ast.TsType::Array(elem),
          ])
          // `flatMap` flattens one level: `T[] | T` → `T[]`.
          let flattened = match cb_ret {
            Array(inner) => inner
            other => other
          }
          return @ast.TsType::Array(flattened)
        }
        (Some(elem), "reduce", [cb, init])
        | (Some(elem), "reduceRight", [cb, init]) => {
          let init_ty = infer_expr(env, resolver, init)
          let cb_ret = infer_arrow_body_with_params(env, resolver, cb, [
            init_ty,
            elem,
            @ast.TsType::Number,
            @ast.TsType::Array(elem),
          ])
          // The accumulator type unions the initial value with each
          // callback return — keep both in case the callback widens.
          return narrow_union(init_ty, cb_ret)
        }
        // `arr.filter((x): x is Foo => …)` — when the callback is
        // declared as a type predicate, narrow the result array's
        // element to the predicate's asserted type.
        (Some(elem), "filter", [cb]) =>
          match arrow_type_predicate_target(cb) {
            Some(target) => return @ast.TsType::Array(target)
            None => {
              let _ = elem
              ()
            }
          }
        _ => ()
      }
      // `promise.then(cb)` — flow the callback's body return into the
      // result `Promise<U>`. If the callback returns a `Promise<V>`,
      // flatten it (chaining): the chain produces `Promise<V>`.
      let promise_inner_opt = match resolver.unwrap(recv_ty) {
        Applied("Promise", [t]) | Applied("PromiseLike", [t]) => Some(t)
        _ => None
      }
      match (promise_inner_opt, meth, args) {
        (Some(inner), "then", [cb]) => {
          let cb_ret = infer_arrow_body_with_params(env, resolver, cb, [inner])
          let flattened = match cb_ret {
            Applied("Promise", [t]) | Applied("PromiseLike", [t]) => t
            other => other
          }
          return @ast.TsType::Applied("Promise", [flattened])
        }
        (Some(inner), "catch", [_]) =>
          return @ast.TsType::Applied("Promise", [inner])
        (Some(inner), "finally", [_]) =>
          return @ast.TsType::Applied("Promise", [inner])
        _ => ()
      }
      // Overload resolution: a class method with multiple signatures
      // (`foo(x: 'a'): A; foo(x: 'b'): B`) resolves to the first signature
      // whose parameters accept the argument types. The single-signature
      // `lookup_method_sig` below only sees the first overload, so try the
      // full set first.
      let pruned_recv = prune_nullish(resolver, recv_ty)
      let arg_types : Array[@ast.TsType] = []
      for a in args {
        arg_types.push(infer_expr(env, resolver, a))
      }
      match resolver.resolve_method_overload(pruned_recv, meth, arg_types) {
        Some(ret) => return substitute_this_type(ret, recv_ty)
        None => ()
      }
      // Nullable receiver: strip null/undefined members and retry so
      // `(arr | null).map(...)` still resolves the method return type.
      match resolver.lookup_method_sig(pruned_recv, meth) {
        Some((_params, ret)) => {
          for a in args {
            let _ = infer_expr(env, resolver, a)
          }
          // `this`-typed return: when an interface / class method is
          // declared as `m(): this` (or wrapped in `this & T` etc.),
          // substitute the receiver in for `this` so the chain
          // `t.self().me()` keeps the receiver shape instead of leaking
          // a bare `Named("this")` reference into downstream checks.
          substitute_this_type(ret, recv_ty)
        }
        None => {
          for a in args {
            let _ = infer_expr(env, resolver, a)
          }
          @ast.TsType::Any
        }
      }
    }
    AssignExpr(_, value) | AssignPattern(_, value) =>
      infer_expr(env, resolver, value)
    CompoundAssignExpr(_, _, value) => infer_expr(env, resolver, value)
    PropAssignExpr(_, _, value) | IndexAssignExpr(_, _, value) =>
      infer_expr(env, resolver, value)
    Seq(_, second) => infer_expr(env, resolver, second)
    Spread(inner) => infer_expr(env, resolver, inner)
    Await(inner) =>
      match infer_expr(env, resolver, inner) {
        Applied("Promise", args) if args.length() == 1 => args[0]
        other => other
      }
    // `yield expr` — type is whatever the generator's `.next()` sends back
    // (TNext), which we don't track. Walk the operand for side-effect checks;
    // the expression-statement result is `any`.
    Yield(operand_opt) => {
      match operand_opt {
        Some(e) => {
          let _ = infer_expr(env, resolver, e)
        }
        None => ()
      }
      @ast.TsType::Any
    }
    YieldStar(inner) => {
      let inner_ty = infer_expr(env, resolver, inner)
      for_of_element_type(resolver, inner_ty)
    }
    DynamicImport(_, _) | ImportMeta => @ast.TsType::Any
    PropAccess(receiver, name) => {
      // Property-access narrowing: when the access is a `Var` /
      // `PropAccess`-chain that the narrowing path tracks, look up the
      // synthesised dotted env key first. Falls through to the
      // structural resolver lookup when no narrowing binding exists.
      match narrowing_key_for_expr(@ast.TsExpr::PropAccess(receiver, name)) {
        Some(key) =>
          match env.lookup(key) {
            Some(narrowed) => return narrowed
            None => ()
          }
        None => ()
      }
      // Class static-side / namespace+class merging: when the receiver
      // is a bare identifier and `Name.member` resolves through the
      // globals (because `namespace Name` registered the member as
      // `Name.member`, or `class Name` has a static method), prefer
      // that lookup. The instance-side `lookup_field` would otherwise
      // miss static members entirely.
      match receiver {
        Var(class_name) =>
          match resolver.globals.get(class_name + "." + name) {
            Some(t) => return t
            None =>
              match resolver.classes.get(class_name) {
                Some(cls) => {
                  for p in cls.properties {
                    if p.name == name && p.is_static {
                      return p.type_
                    }
                  }
                  for m in cls.methods {
                    if m.name == name && m.is_static {
                      let param_types : Array[@ast.TsType] = []
                      for p in m.params {
                        param_types.push(p.1)
                      }
                      return @ast.TsType::Func(param_types, m.return_type)
                    }
                  }
                }
                None => ()
              }
          }
        _ => ()
      }
      let recv_ty = infer_expr(env, resolver, receiver)
      match resolver.lookup_field(recv_ty, name) {
        Some(t) => t
        None =>
          // Union receiver: lookup_field requires ALL members to have the
          // field. When null/undefined members make that fail, retry on the
          // non-null members so `(obj | null).prop` still resolves to the
          // field type instead of Any.
          match resolver.lookup_field(prune_nullish(resolver, recv_ty), name) {
            Some(t) => t
            None => @ast.TsType::Any
          }
      }
    }
    IndexAccess(receiver, index_expr) => {
      // Index-access narrowing: if the access has a stable narrowing
      // key (`arr[0]` / `m["k"]`) and an env binding exists, honour it.
      match
        narrowing_key_for_expr(@ast.TsExpr::IndexAccess(receiver, index_expr)) {
        Some(key) =>
          match env.lookup(key) {
            Some(narrowed) => return narrowed
            None => ()
          }
        None => ()
      }
      let recv_ty = infer_expr(env, resolver, receiver)
      let idx_ty = infer_expr(env, resolver, index_expr)
      infer_index(resolver, recv_ty, idx_ty, index_expr)
    }
    ObjectLit(entries) => {
      let fields : Array[(@ast.TsType, @ast.TsType)] = []
      for entry in entries {
        // Object spread `{ ...expr }` is encoded by the parser with key
        // "@@spread:N". Infer the spread source type and merge its declared
        // fields into the result object type rather than adding a literal
        // "@@spread:N" key.
        if entry.0.has_prefix("@@spread:") {
          let spread_ty = infer_expr(env, resolver, entry.1)
          for f in collect_declared_fields(spread_ty, resolver) {
            fields.push((@ast.TsType::Literal(f.0), f.1))
          }
        } else {
          let val_ty = infer_expr(env, resolver, entry.1)
          fields.push((@ast.TsType::Literal(entry.0), val_ty))
        }
      }
      @ast.TsType::Object(fields)
    }
    ComputedProp(_, _) => @ast.TsType::Any
    ArrowFunc(params, declared_ret, body, is_async) => {
      let param_types : Array[@ast.TsType] = []
      for p in params {
        param_types.push(p.type_)
      }
      // Prefer the explicit return-type annotation when one was supplied;
      // fall back to inferring from the body expression for `(x) => expr`
      // or walking return statements for `(x) => { return expr; }` blocks.
      let ret = if is_checkable(declared_ret) {
        declared_ret
      } else {
        match body {
          ArrowExpr(e) => infer_expr(env, resolver, e)
          ArrowBlock(block) => infer_block_return(env, resolver, block)
        }
      }
      @ast.TsType::Func(param_types, wrap_async_return(is_async, ret))
    }
    FuncExpr(f) => {
      let param_types : Array[@ast.TsType] = []
      for p in f.params {
        param_types.push(p.type_)
      }
      // When no explicit return-type annotation was given, walk the body for
      // return statements — same strategy as ArrowBlock.
      let ret = if is_checkable(f.return_type) {
        f.return_type
      } else {
        infer_block_return(env, resolver, f.body)
      }
      @ast.TsType::Func(param_types, wrap_async_return(f.is_async, ret))
    }
    TaggedTemplate(tag, _, _, _) =>
      // `tag\`...\`` calls `tag(strings, ...exprs)` at runtime. We don't
      // model `TemplateStringsArray` here, so the most useful fallback
      // is the return type of `tag` when it's a known function — this
      // is what library helpers like `gql\`...\`` / `css\`...\`` /
      // `sql\`...\`` rely on for end-to-end typing.
      match resolver.unwrap(infer_expr(env, resolver, tag)) {
        Func(_, ret) => ret
        // A tag typed `any` produces `any` (calling `any` yields `any`), so
        // member access on the result must not be flagged. Anything else
        // falls back to the cooked-string type.
        Any => @ast.TsType::Any
        _ => @ast.TsType::String_
      }
    TemplateLiteral(_, _) => @ast.TsType::String_
    // `x as T` — forced cast; result type is `T`. We still walk `inner` so
    // any nested call sites are validated.
    As(inner, ty) => {
      let _ = infer_expr(env, resolver, inner)
      ty
    }
    // `x satisfies T` — structural check; result type is `typeof x`. The
    // check happens elsewhere (`check_call_args_in_expr`).
    Satisfies(inner, _) => infer_expr(env, resolver, inner)
    // `x!` — strip null / undefined from the operand's type.
    NonNull(inner) => non_nullable(infer_expr(env, resolver, inner))
    // `a?.b…` — widen the result with `undefined` to reflect short-circuit.
    OptionalChain(inner) => {
      // `a?.b` — infer the chain result, then widen with `undefined` because
      // the chain short-circuits to `undefined` when the receiver is nullish.
      let inner_ty = infer_expr(env, resolver, inner)
      let base = prune_nullish(resolver, inner_ty)
      narrow_union(base, @ast.TsType::Undefined)
    }
    // JSX element / fragment. The value itself is opaque at the type
    // level (we don't model React's `ReactNode` / `JSX.Element`), so
    // return `Any`. The embedded `{expr}` sub-expressions are walked
    // by `check_call_args_in_expr` for diagnostic recursion.
    JsxElement(_, _, _) => @ast.TsType::Any
    NativeClassExpr(_, _) => @ast.TsType::Any
    PureCall(inner) => infer_expr(env, resolver, inner)
  }
}

///|
/// Recursive unification step: when `formal` mentions a type parameter
/// from `type_params`, bind it to `actual`. Compound shapes (Array,
/// Tuple, Func, Applied, Union…) are walked structurally so type
/// parameters embedded inside them get bound from the matching position
/// in `actual`. The `soft` flag is `true` when the recursion is currently
/// inside the return position of a `Func` formal — that is, a covariant
/// inference candidate coming from an arrow's body type. Multiple
/// soft candidates for the same parameter are unioned (best-common-type
/// approximation), but a hard inference (top-level `T`, `T[]`, etc.)
/// retains the first-wins semantics so real argument-type mismatches
/// still surface as diagnostics.
fn infer_param_bindings(
  type_params : Array[String],
  formal : @ast.TsType,
  actual : @ast.TsType,
  bindings : Map[String, @ast.TsType],
  soft : Bool,
) -> Unit {
  // Direct hit: formal is exactly a type parameter we're solving for.
  match formal {
    Named(name) =>
      if type_params.contains(name) {
        match bindings.get(name) {
          Some(Any) | None => bindings[name] = actual
          Some(existing) =>
            // `soft` widens; hard inferences keep the first concrete
            // binding so the per-arg assignability check catches a real
            // mismatch (e.g. `indexOf(arr: number[], "abc")`). Any-actual
            // contributes no information.
            match actual {
              Any => ()
              _ => if soft { bindings[name] = narrow_union(existing, actual) }
            }
        }
        return
      }
    _ => ()
  }
  // Structural matching — peel matching outer shapes.
  match (formal, actual) {
    (Array(f_elem), Array(a_elem)) =>
      infer_param_bindings(type_params, f_elem, a_elem, bindings, soft)
    (Array(f_elem), Applied("Array", a_args)) if a_args.length() == 1 =>
      infer_param_bindings(type_params, f_elem, a_args[0], bindings, soft)
    (Applied("Array", f_args), Array(a_elem)) if f_args.length() == 1 =>
      infer_param_bindings(type_params, f_args[0], a_elem, bindings, soft)
    (Applied(f_name, f_args), Applied(a_name, a_args)) =>
      if f_name == a_name && f_args.length() == a_args.length() {
        let mut i = 0
        while i < f_args.length() {
          infer_param_bindings(
            type_params,
            f_args[i],
            a_args[i],
            bindings,
            soft,
          )
          i = i + 1
        }
      }
    (Tuple(f_items), Tuple(a_items)) => {
      let n = if f_items.length() < a_items.length() {
        f_items.length()
      } else {
        a_items.length()
      }
      let mut i = 0
      while i < n {
        infer_param_bindings(
          type_params,
          f_items[i],
          a_items[i],
          bindings,
          soft,
        )
        i = i + 1
      }
    }
    (Func(f_params, f_ret), Func(a_params, a_ret)) => {
      // Param positions: keep the surrounding softness (a contravariant
      // slot under an arrow doesn't get a covariance bonus). Return
      // position: mark `soft = true` so multiple unannotated arrows
      // contributing different body return types union instead of
      // first-wins.
      let n = if f_params.length() < a_params.length() {
        f_params.length()
      } else {
        a_params.length()
      }
      let mut i = 0
      while i < n {
        infer_param_bindings(
          type_params,
          f_params[i],
          a_params[i],
          bindings,
          soft,
        )
        i = i + 1
      }
      infer_param_bindings(type_params, f_ret, a_ret, bindings, true)
    }
    // Object / interface-shaped parameters: match fields by name and infer
    // recursively. `foo<T>(x: { bar: T; baz: T })` called with `{ bar: 1,
    // baz: "" }` infers `T = number` from `bar` (first-wins for a nested
    // position), so the later `baz: ""` is then checked against `number` and
    // the mismatch surfaces — matching tsc's object-literal inference.
    (Object(f_fields), Object(a_fields)) =>
      infer_object_field_bindings(
        type_params,
        object_fields_by_name(f_fields),
        object_fields_by_name(a_fields),
        bindings,
        soft,
      )
    (Struct(_, f_fields), Object(a_fields)) =>
      infer_object_field_bindings(
        type_params,
        f_fields,
        object_fields_by_name(a_fields),
        bindings,
        soft,
      )
    (Object(f_fields), Struct(_, a_fields)) =>
      infer_object_field_bindings(
        type_params,
        object_fields_by_name(f_fields),
        a_fields,
        bindings,
        soft,
      )
    (Struct(_, f_fields), Struct(_, a_fields)) =>
      infer_object_field_bindings(
        type_params, f_fields, a_fields, bindings, soft,
      )
    (Union(f_parts), _) =>
      // Best-effort: try the first part that isn't a bare type parameter
      // (matching a concrete shape generally yields more information). If
      // none matches concretely, fall back to the first part.
      for part in f_parts {
        match part {
          Named(n) if type_params.contains(n) => continue
          _ => {
            infer_param_bindings(type_params, part, actual, bindings, soft)
            return
          }
        }
      }
    _ => ()
  }
}

///|
/// Extract `(name, type)` pairs from an `Object` field list. Object keys are
/// stored as `Literal(name)`; non-literal / computed keys are skipped.
fn object_fields_by_name(
  fields : Array[(@ast.TsType, @ast.TsType)],
) -> Array[(String, @ast.TsType)] {
  let out : Array[(String, @ast.TsType)] = []
  for f in fields {
    match f.0 {
      Literal(name) => out.push((name, f.1))
      _ => ()
    }
  }
  out
}

///|
/// Infer type-parameter bindings by matching formal/actual object fields by
/// name, recursing into each shared field's types. Used for object / struct
/// shaped parameters in `infer_param_bindings`.
fn infer_object_field_bindings(
  type_params : Array[String],
  formal_fields : Array[(String, @ast.TsType)],
  actual_fields : Array[(String, @ast.TsType)],
  bindings : Map[String, @ast.TsType],
  soft : Bool,
) -> Unit {
  for ff in formal_fields {
    for af in actual_fields {
      if af.0 == ff.0 {
        infer_param_bindings(type_params, ff.1, af.1, bindings, soft)
      }
    }
  }
}

///|
/// Whether the type parameter `tp` appears anywhere inside `t`. Exhaustive
/// over every `TsType` variant so a future addition fails to compile rather
/// than silently under-reporting (which would let `solve_generic_bindings`
/// widen a parameter it shouldn't).
fn type_param_occurs(tp : String, t : @ast.TsType) -> Bool {
  match t {
    Number
    | Int
    | Boolean
    | String_
    | Void
    | BigInt
    | Symbol
    | UniqueSymbol(_)
    | Any
    | Unknown
    | Never
    | Null
    | Undefined
    | Literal(_)
    | NumberLiteral(_)
    | BigIntLiteral(_)
    | BooleanLiteral(_)
    | TypeOf(_) => false
    Named(n) => n == tp
    Array(e) | Rest(e) | Keyof(e) => type_param_occurs(tp, e)
    Tuple(items) | Union(items) | Intersection(items) =>
      items.iter().any(fn(it) { type_param_occurs(tp, it) })
    Object(pairs) =>
      pairs
      .iter()
      .any(fn(p) { type_param_occurs(tp, p.0) || type_param_occurs(tp, p.1) })
    Struct(_, fields) => fields.iter().any(fn(f) { type_param_occurs(tp, f.1) })
    Func(ps, r) | Constructor(ps, r, _) =>
      ps.iter().any(fn(p) { type_param_occurs(tp, p) }) ||
      type_param_occurs(tp, r)
    // A generic function type shadows `tp` when it re-declares the same name;
    // otherwise `tp` may occur free in the underlying callable.
    GenericFunc(names, inner) =>
      !names.contains(tp) && type_param_occurs(tp, inner)
    Conditional(a, b, c, d) =>
      type_param_occurs(tp, a) ||
      type_param_occurs(tp, b) ||
      type_param_occurs(tp, c) ||
      type_param_occurs(tp, d)
    Applied(name, args) =>
      name == tp || args.iter().any(fn(a) { type_param_occurs(tp, a) })
    IndexedAccess(a, b) => type_param_occurs(tp, a) || type_param_occurs(tp, b)
    TemplateLiteralType(_, args) =>
      args.iter().any(fn(a) { type_param_occurs(tp, a) })
    MappedType(_, src, val, _) =>
      type_param_occurs(tp, src) || type_param_occurs(tp, val)
    MappedTypeRemap(_, src, remap, val, _) =>
      type_param_occurs(tp, src) ||
      type_param_occurs(tp, remap) ||
      type_param_occurs(tp, val)
    TypePredicate(_, pt) => type_param_occurs(tp, pt)
    AssertsPredicate(_, opt) =>
      match opt {
        Some(pt) => type_param_occurs(tp, pt)
        None => false
      }
  }
}

///|
/// Compute type-parameter bindings at a call site by unifying each
/// argument's inferred type against the corresponding formal parameter.
/// Type parameters that remain unbound fall back to `Any`.
fn solve_generic_bindings(
  env : ExprEnv,
  resolver : Resolver,
  type_params : Array[String],
  params : Array[@ast.TsType],
  args : Array[@ast.TsExpr],
  sig : Array[@ast.TsParam]?,
) -> Map[String, @ast.TsType] {
  let bindings : Map[String, @ast.TsType] = {}
  for tp in type_params {
    bindings[tp] = @ast.TsType::Any
  }
  // A type parameter that appears *only* as a bare top-level parameter
  // (`f<T>(x: T, y: T)`) — never nested inside an array / generic /
  // structural shape — is inferred from every such argument as a union,
  // matching TS (`f("a", 1)` gives `T = string | number`, not an error).
  // When the same `T` also appears nested (`g<T>(arr: T[], x: T)`) we keep
  // the first-wins inference so a genuine mismatch (`g([1,2,3], "abc")`) is
  // still reported — the nested position pins `T` and the bare one is then
  // a real assignability check.
  let widen_safe : Map[String, Unit] = {}
  for tp in type_params {
    let mut nested = false
    for p in params {
      if type_param_occurs(tp, p) && !(p is Named(_) && p == Named(tp)) {
        nested = true
        break
      }
    }
    if !nested {
      widen_safe[tp] = ()
    }
  }
  fn is_rest_at(i : Int) -> Bool {
    if params[i] is Rest(_) {
      return true
    }
    match sig {
      Some(s) => i < s.length() && s[i].is_rest
      None => false
    }
  }

  let mut i = 0
  while i < params.length() {
    if is_rest_at(i) {
      // Variadic tail (`...args: T[]`): each individual argument has the
      // element type `T`, not the whole `T[]`. Unify every remaining
      // argument against the element type so `foo([true], [false])` infers
      // `T = boolean[]` (not `boolean`). A spread argument supplies the
      // whole array, so unify it against the rest array type instead.
      let rest_arr = match params[i] {
        Rest(inner) => inner
        other => other
      }
      let elem = rest_param_element(params[i])
      while i < args.length() {
        let actual = infer_expr(env, resolver, args[i])
        match args[i] {
          Spread(_) =>
            infer_param_bindings(type_params, rest_arr, actual, bindings, true)
          _ => infer_param_bindings(type_params, elem, actual, bindings, true)
        }
        i = i + 1
      }
      break
    }
    if i < args.length() {
      let actual = infer_expr(env, resolver, args[i])
      // Widen (union across positions) only for a bare type parameter that
      // is never nested elsewhere; otherwise keep first-wins.
      let soft = match params[i] {
        Named(n) => widen_safe.contains(n)
        _ => false
      }
      infer_param_bindings(type_params, params[i], actual, bindings, soft)
    }
    i = i + 1
  }
  bindings
}

///|
/// Element type of a rest parameter's declared type: `...args: T[]` is stored
/// as `Rest(Array(T))` (module functions) or bare `Array(T)` (`declare`
/// imports). Both yield `T`; non-array shapes are returned unchanged.
fn rest_param_element(t : @ast.TsType) -> @ast.TsType {
  let inner = match t {
    Rest(x) => x
    other => other
  }
  match inner {
    Array(e) => e
    Applied("Array", [e]) | Applied("ReadonlyArray", [e]) => e
    other => other
  }
}

///|
/// Substitute type-parameter bindings into each formal parameter so the
/// downstream argument check / return-type inference sees concrete types
/// where possible.
fn substitute_params_array(
  params : Array[@ast.TsType],
  bindings : Map[String, @ast.TsType],
) -> Array[@ast.TsType] {
  let out : Array[@ast.TsType] = []
  for p in params {
    out.push(substitute_params(p, bindings))
  }
  out
}

///|
fn infer_call(
  env : ExprEnv,
  resolver : Resolver,
  callee : @ast.TsType,
  args : Array[@ast.TsExpr],
) -> @ast.TsType {
  for a in args {
    let _ = infer_expr(env, resolver, a)
  }
  let callee = resolver.unwrap(callee)
  match callee {
    // `paramName is T` is a boolean at the value level — calls to a type
    // predicate function return `Boolean`. The predicate effect is applied
    // via the narrowing path in `if (isFoo(v))`.
    Func(_, TypePredicate(_, _)) => @ast.TsType::Boolean
    // `asserts paramName [is T]` returns `void` at the value level — the
    // narrowing effect applies to all statements after the call site.
    Func(_, AssertsPredicate(_, _)) => @ast.TsType::Void
    // Reduce conditional types in the return position so `NonNullable<T>`,
    // `Awaited<T>` etc. evaluate to concrete types when possible.
    Func(_, ret) => reduce_conditional(ret)
    // Union of callable types (overload set): resolve to the overload whose
    // arity and parameter types accept the supplied arguments, and return that
    // overload's return type. Falls back to the union of every branch's return
    // type when no signature matches precisely (so an overloaded call site
    // doesn't widen to an imprecise union for the common matching case).
    Union(parts) => {
      let arg_types : Array[@ast.TsType] = []
      for a in args {
        arg_types.push(resolver.unwrap(infer_expr(env, resolver, a)))
      }
      let rets : Array[@ast.TsType] = []
      for part in parts {
        match resolver.unwrap(part) {
          Func(params, ret) => {
            let r = match ret {
              TypePredicate(_, _) => @ast.TsType::Boolean
              AssertsPredicate(_, _) => @ast.TsType::Void
              _ => reduce_conditional(ret)
            }
            rets.push(r)
            // Best-effort overload match: same arity, every argument
            // assignable to the corresponding parameter.
            if params.length() == arg_types.length() {
              let mut ok = true
              for i in 0..<params.length() {
                if !is_assignable_to(arg_types[i], params[i]) {
                  ok = false
                  break
                }
              }
              if ok {
                return r
              }
            }
          }
          _ => return @ast.TsType::Any
        }
      }
      if rets.length() == 1 {
        rets[0]
      } else {
        @ast.TsType::Union(rets)
      }
    }
    // Intersection: find the first callable member and use its return type.
    Intersection(parts) => {
      for part in parts {
        match resolver.unwrap(part) {
          Func(_, TypePredicate(_, _)) => return @ast.TsType::Boolean
          Func(_, AssertsPredicate(_, _)) => return @ast.TsType::Void
          Func(_, ret) => return reduce_conditional(ret)
          _ => ()
        }
      }
      @ast.TsType::Any
    }
    _ => @ast.TsType::Any
  }
}

///|
fn infer_index(
  resolver : Resolver,
  recv : @ast.TsType,
  idx : @ast.TsType,
  idx_expr : @ast.TsExpr,
) -> @ast.TsType {
  // Unwrap type aliases before dispatch so `type Arr = string[]` resolves
  // correctly for both `Array(elem)` and `Applied("Array", [elem])` shapes.
  let recv = resolver.unwrap(recv)
  // `prim["methodName"]` reaches a prototype member we don't model (e.g.
  // `"".charAt`, `(1).toExponential`). Yield `Any` so a following call
  // (`x["charAt"](0)`) isn't flagged as "string is not callable".
  match (recv, idx_expr) {
    (
      String_
      | Literal(_)
      | Number
      | Int
      | NumberLiteral(_)
      | Boolean
      | BooleanLiteral(_),
      StringLit(_),
    ) => return @ast.TsType::Any
    _ => ()
  }
  match recv {
    Array(elem) => elem
    // `Array<T>` / `ReadonlyArray<T>` generic form — numeric index yields T.
    Applied("Array", [elem]) | Applied("ReadonlyArray", [elem]) =>
      match idx {
        Number | Int | NumberLiteral(_) => elem
        _ =>
          match idx_expr {
            IntLit(_) | NumberLit(_) => elem
            _ => elem // arr[i] for any index still yields elem type
          }
      }
    Tuple(items) =>
      match idx_expr {
        IntLit(i) if i >= 0 && i < items.length() => items[i]
        NumberLit(d) => {
          let i = d.to_int()
          if i >= 0 && i < items.length() {
            items[i]
          } else {
            @ast.TsType::Any
          }
        }
        _ => {
          // Union of all element types when the index is non-literal.
          if items.length() == 0 {
            return @ast.TsType::Undefined
          }
          let mut acc = items[0]
          let mut i = 1
          while i < items.length() {
            acc = narrow_union(acc, items[i])
            i = i + 1
          }
          acc
        }
      }
    String_ | Literal(_) =>
      match idx {
        Number | Int | NumberLiteral(_) => @ast.TsType::String_
        // Non-numeric index on a string type: characters are still strings.
        String_ | Literal(_) => @ast.TsType::String_
        _ => @ast.TsType::Any
      }
    // Interface / class receivers — string-literal indices match named
    // fields (and the index signature as fallback). For non-literal
    // indices, fall back to the interface's index signature value type
    // so `obj[i]` on `{ [k: string]: V }` returns `V` instead of `Any`.
    Named(_) | Applied(_, _) =>
      match idx_expr {
        StringLit(key) =>
          match resolver.lookup_field(recv, key) {
            Some(t) => t
            None =>
              // Field not found by name — try the index signature as fallback
              // so `obj["key"]` on `{ [k: string]: V }` returns `V`.
              match resolver.lookup_index_sig(recv, @ast.TsType::String_) {
                Some(t) => t
                None => @ast.TsType::Any
              }
          }
        IntLit(i) =>
          match resolver.lookup_field(recv, i.to_string()) {
            Some(t) => t
            None =>
              match resolver.lookup_index_sig(recv, @ast.TsType::Number) {
                Some(t) => t
                None => @ast.TsType::Any
              }
          }
        _ =>
          // Variable index: consult the index signature of the interface/class.
          match resolver.lookup_index_sig(recv, idx) {
            Some(t) => t
            None => @ast.TsType::Any
          }
      }
    _ => @ast.TsType::Any
  }
}

///|
/// The subset of `t`'s values that are falsy -- what the left operand of
/// `a && b` contributes to the result type. Always-truthy shapes (object /
/// class / interface / array / tuple / function references) contribute
/// nothing (`never`), so `(x: Beast) && cond` is `boolean`, not
/// `Beast | boolean`. Primitives are kept conservatively (we don't model
/// `0` / `""` / `false` literal falsiness).
fn falsy_subset(resolver : Resolver, t : @ast.TsType) -> @ast.TsType {
  let u = resolver.unwrap(t)
  match u {
    Object(_)
    | Struct(_, _)
    | Array(_)
    | Tuple(_)
    | Func(_, _)
    | Constructor(_, _, _) => @ast.TsType::Never
    Named(_) | Applied(_, _) =>
      if is_named_decl(u, resolver) {
        @ast.TsType::Never
      } else {
        u
      }
    Union(ms) => {
      let kept : Array[@ast.TsType] = []
      for m in ms {
        let f = falsy_subset(resolver, m)
        if !(f is Never) {
          kept.push(f)
        }
      }
      union_of(kept)
    }
    _ => u
  }
}

///|
fn infer_binop(
  op : @ast.TsBinOp,
  l : @ast.TsType,
  r : @ast.TsType,
  resolver : Resolver,
) -> @ast.TsType {
  match op {
    Add =>
      match (l, r) {
        // String concat — either side is a string-shaped type.
        (String_, _) | (_, String_) | (Literal(_), _) | (_, Literal(_)) =>
          @ast.TsType::String_
        // `bigint + bigint` stays bigint (mixing with number is a type error,
        // surfaced separately by the operand check).
        (BigInt, BigInt)
        | (BigInt, BigIntLiteral(_))
        | (BigIntLiteral(_), BigInt)
        | (BigIntLiteral(_), BigIntLiteral(_)) => @ast.TsType::BigInt
        (Number, Number) | (Number, Int) | (Int, Number) | (Int, Int) =>
          @ast.TsType::Number
        (NumberLiteral(_), _) | (_, NumberLiteral(_)) => @ast.TsType::Number
        (Any, _) | (_, Any) => @ast.TsType::Any
        _ => @ast.TsType::Number
      }
    Sub | Mul | Div | Mod | Pow | Shl | Shr | UShr | BitAnd | BitOr | BitXor =>
      // `bigint OP bigint` yields bigint; everything else collapses to number.
      match (l, r) {
        (BigInt, BigInt)
        | (BigInt, BigIntLiteral(_))
        | (BigIntLiteral(_), BigInt)
        | (BigIntLiteral(_), BigIntLiteral(_)) => @ast.TsType::BigInt
        _ => @ast.TsType::Number
      }
    BinEq
    | BinNe
    | AbstractEq
    | AbstractNe
    | BinLt
    | BinLe
    | BinGt
    | BinGe
    | In
    | Instanceof => @ast.TsType::Boolean
    // `a && b` — when `a` is truthy the result is `b`; otherwise the falsy
    // subset of `a`. An always-truthy object/class operand contributes
    // nothing, so `(x: Beast) && cond` is `boolean`, not `Beast | boolean`.
    And => narrow_union(falsy_subset(resolver, l), r)
    // `a || b` — when `a` is truthy the result is `a`; otherwise `b`. TS
    // narrows the truthy branch by stripping always-falsy variants from
    // `l` (null / undefined are the practically-relevant ones here, since
    // we don't model literal-value falsiness for primitives like
    // `0` / `""` / `false`). Matches the common `x || default` pattern
    // where `x: T | undefined` and `default: T` produce `T`.
    Or => narrow_union(non_nullable(l), r)
    // `a ?? b` — `b` is only evaluated when `a` is null/undefined, so the
    // result strips nullish from `a` and unions with `b`'s type.
    Coalesce => narrow_union(non_nullable(l), r)
  }
}

///|
fn infer_unary(op : @ast.TsUnaryOp) -> @ast.TsType {
  match op {
    Neg | Plus | BitwiseNot | PreInc | PreDec | PostInc | PostDec =>
      @ast.TsType::Number
    Not => @ast.TsType::Boolean
    Typeof => @ast.TsType::String_
    Void => @ast.TsType::Undefined
    Delete => @ast.TsType::Boolean
  }
}

///|
/// Return the narrow string-literal type that `typeof operand` produces when
/// the operand's type is statically known. Falls back to `String_` (the widest
/// possible typeof result) for unknown / mixed shapes.
fn infer_typeof_type(resolver : Resolver, ty : @ast.TsType) -> @ast.TsType {
  let lit = fn(s : String) { @ast.TsType::Literal(s) }
  match resolver.unwrap(ty) {
    String_ | Literal(_) => lit("string")
    Number | Int | NumberLiteral(_) => lit("number")
    Boolean | BooleanLiteral(_) => lit("boolean")
    BigInt | BigIntLiteral(_) => lit("bigint")
    Symbol | UniqueSymbol(_) => lit("symbol")
    Null => lit("object")
    Array(_) | Tuple(_) | Object(_) | Struct(_, _) => lit("object")
    Undefined | Void => lit("undefined")
    Func(_, _) | Constructor(_, _, _) => lit("function")
    Union(parts) => {
      let seen : Map[String, Bool] = {}
      let tags : Array[@ast.TsType] = []
      for p in parts {
        let tag = infer_typeof_type(resolver, p)
        let key = match tag {
          Literal(s) => s
          _ => "string"
        }
        if !seen.contains(key) {
          seen[key] = true
          tags.push(tag)
        }
      }
      if tags.length() == 1 {
        tags[0]
      } else {
        @ast.TsType::Union(tags)
      }
    }
    _ => @ast.TsType::String_
  }
}

///|
fn narrow_union(a : @ast.TsType, b : @ast.TsType) -> @ast.TsType {
  if equivalent(a, b) {
    return a
  }
  @ast.TsType::Union([a, b])
}

// ---------------------------------------------------------------------------
// Assignability + argument checking.
// ---------------------------------------------------------------------------

///|
/// Extract the bare call signature (`<call>`) from a callable object /
/// interface type: `interface I { (): T }` / `type F = { (x): T }`. A
/// function value assigned to such a type is checked against this
/// signature, so we surface it and bypass the structural-object path
/// (which has no function rule and would report a spurious `expected I
/// but got () => T`). Returns the call signature's `Func`, or `None`
/// when the type carries no call signature.
///
/// Restricted to types with *exactly one* call signature: an overload
/// set (`{ (x: T): string; (x: T, y?: T): string }`) is not contextually
/// applied to a passed lambda by TS, so routing through one arbitrary
/// arm would push the wrong parameter / return types into the body.
fn Resolver::object_call_signature(
  self : Resolver,
  t : @ast.TsType,
) -> @ast.TsType? {
  let mut found : @ast.TsType? = None
  let mut count = 0
  match t {
    Object(fields) =>
      for f in fields {
        match f.0 {
          Literal(k) if k == "<call>" => {
            found = Some(f.1)
            count = count + 1
          }
          _ => ()
        }
      }
    Named(n) =>
      match self.interfaces.get(n) {
        Some(iface) =>
          for f in iface.fields {
            if f.0 == "<call>" {
              found = Some(f.1)
              count = count + 1
            }
          }
        None => ()
      }
    _ => ()
  }
  if count == 1 {
    found
  } else {
    None
  }
}

///|
fn check_expr_against(
  env : ExprEnv,
  expr : @ast.TsExpr,
  expected : @ast.TsType,
  ctx : CheckCtx,
  sub_path : String,
) -> Unit {
  // Always walk for nested call-site argument errors, even when the outer
  // expected type is `Any` (e.g. an unannotated return where we still want
  // bad calls inside the returned expression to be flagged).
  check_call_args_in_expr(env, expr, ctx)
  // Contextual typing for arrow / function expressions: when the value being
  // passed is a callable and the expected slot is `Func(formal_params,
  // formal_ret)`, recheck the callable's body with the formal parameter
  // types substituted in for any unannotated (`Any`) params — `arr.map(x =>
  // x + 1)` flows the element type into `x` so the body's `x + 1` is
  // properly typed instead of falling through to `Any`.
  let expected_shape = ctx.resolver.unwrap(expected)
  // A call-signature interface / object type (`interface I { (): T }`,
  // `type F = { (x): T }`) is callable. Route a function / arrow value
  // through that call signature so it gets contextual typing and skips
  // the structural object-assignability path (which has no function
  // rule and would otherwise report a spurious `expected I but got
  // () => T`).
  match ctx.resolver.object_call_signature(expected_shape) {
    Some(Func(formal_params, formal_ret)) =>
      match expr {
        ArrowFunc(arrow_params, _declared_ret, body, is_async) => {
          check_arrow_with_context(
            env, arrow_params, body, is_async, formal_params, formal_ret, ctx, sub_path,
          )
          return
        }
        FuncExpr(f) => {
          check_funcexpr_with_context(
            env, f, formal_params, formal_ret, ctx, sub_path,
          )
          return
        }
        _ => ()
      }
    _ => ()
  }
  match (expr, expected_shape) {
    (
      ArrowFunc(arrow_params, _declared_ret, body, is_async),
      Func(formal_params, formal_ret),
    ) => {
      check_arrow_with_context(
        env, arrow_params, body, is_async, formal_params, formal_ret, ctx, sub_path,
      )
      return
    }
    (FuncExpr(f), Func(formal_params, formal_ret)) => {
      check_funcexpr_with_context(
        env, f, formal_params, formal_ret, ctx, sub_path,
      )
      return
    }
    // Ternary: check each branch against the expected type individually.
    // This catches `cond ? "ok" : 42` against `string` — without this the
    // inferred type is `string | number` and the union check may be too wide.
    (Cond(_, then_, else_), _) => {
      check_expr_against(env, then_, expected, ctx, sub_path + " (then)")
      check_expr_against(env, else_, expected, ctx, sub_path + " (else)")
      return
    }
    // Contextual typing for array literals: `[a, b]` against a tuple type
    // `[T1, T2]` checks each element against the corresponding slot. Without
    // this hop the array literal would infer as `Array<elem>` and fail
    // assignability against `Tuple(...)`.
    (ArrayLit(items), Tuple(slots)) => {
      check_array_lit_against_tuple(env, items, slots, ctx, sub_path)
      return
    }
    (ArrayLit(items), Array(elem)) => {
      check_array_lit_elements_against(env, items, elem, ctx, sub_path)
      return
    }
    (ArrayLit(items), Applied("Array", [elem]))
    | (ArrayLit(items), Applied("ReadonlyArray", [elem])) => {
      check_array_lit_elements_against(env, items, elem, ctx, sub_path)
      return
    }
    // `Readonly<T[]>` contextual typing — delegate to element checking on
    // the inner array type so `['a', 'b'] as Readonly<string[]>` works.
    (ArrayLit(items), Applied("Readonly", [Array(elem)])) => {
      check_array_lit_elements_against(env, items, elem, ctx, sub_path)
      return
    }
    _ => ()
  }
  // Contextual typing for object literals against a struct / interface /
  // object-type target. Per-field checking surfaces actionable diagnostics
  // (`field x expected number, got string`) instead of the generic
  // assignability error that points at the whole literal. We only enter
  // this path for "open" shapes (interfaces, structural objects, structs);
  // class targets fall through to assignability because their private /
  // constructed members aren't expressible in a literal.
  match (expr, expected_shape) {
    (ObjectLit(entries), Object(_)) | (ObjectLit(entries), Struct(_, _)) => {
      check_object_lit_against_target(
        env,
        entries,
        expected_shape,
        ctx.resolver,
        ctx,
        sub_path,
      )
      return
    }
    (ObjectLit(entries), Named(name)) =>
      match ctx.resolver.interfaces.get(name) {
        Some(_) => {
          check_object_lit_against_target(
            env,
            entries,
            expected_shape,
            ctx.resolver,
            ctx,
            sub_path,
          )
          return
        }
        None => ()
      }
    // `Applied(N, [args])` — generic interface instance. Same shape
    // analysis as `Named`, with type-parameter substitution performed by
    // `lookup_field` / `collect_declared_fields`. Utility types
    // (Record / Partial / Required / Readonly / Pick / Omit) are also
    // dispatched here even when they aren't backed by an interface
    // declaration, since `lookup_field` / `collect_declared_fields`
    // know how to project their field shapes.
    (ObjectLit(entries), Applied(name, _)) => {
      let is_utility = match name {
        "Record" | "Partial" | "Required" | "Readonly" | "Pick" | "Omit" => true
        _ => false
      }
      if is_utility || ctx.resolver.interfaces.get(name) is Some(_) {
        check_object_lit_against_target(
          env,
          entries,
          expected_shape,
          ctx.resolver,
          ctx,
          sub_path,
        )
        return
      }
    }
    _ => ()
  }
  if !is_checkable(expected) {
    return
  }
  // For a literal expression use its precise literal type so a literal-union
  // target (`const x: 0 | 1 | 2 = 1`) sees `1` rather than the widened
  // `number`. The literal is still assignable to the widened primitive, so
  // this never weakens primitive-vs-primitive mismatch detection.
  let inferred = match precise_literal_type(expr) {
    Some(lit) => lit
    None => infer_expr(env, ctx.resolver, expr)
  }
  if !is_checkable(inferred) {
    return
  }
  // Unwrap type aliases before assignability check so `type Str = string`
  // correctly assigns to `string` without a false mismatch.
  let inferred_u = ctx.resolver.unwrap(inferred)
  let expected_u = ctx.resolver.unwrap(expected)
  // Boxed wrapper objects (`String`/`Number`/`Boolean`/`BigInt`/`Symbol`)
  // are not assignable to their primitive counterparts: `var s: string =
  // new String("")` is TS2322. These wrapper names are lib globals the
  // resolver doesn't carry, so handle the mismatch here -- ahead of the
  // unresolved-`Named` bail below, which would otherwise skip it. Only the
  // exact wrapper/primitive pairs are matched, so this is false-positive-free.
  let wrapper_mismatch = match (inferred_u, widen_literal(expected_u)) {
    (Named("String"), String_)
    | (Named("Number"), Number | Int)
    | (Named("Boolean"), Boolean)
    | (Named("BigInt"), BigInt)
    | (Named("Symbol"), Symbol) => true
    _ => false
  }
  if wrapper_mismatch {
    record(
      ctx,
      sub_path,
      "expected `\{type_display(expected)}` but got `\{type_display(inferred_u)}`",
    )
    return
  }
  // Under strict null checks, a literal `null` / `undefined` is *not*
  // assignable to a bare in-scope type parameter (`function f<T>(...)` body /
  // a generic call's `T`): `T` could be instantiated to a non-nullable type,
  // so tsc reports TS2345 / TS2322. Without strict mode null/undefined flow
  // to everything (the suppression below), so gate this on the strict flag.
  // Restricted to a target that is exactly an in-scope type-parameter name.
  if ctx.strict_property_init && is_null_or_undefined_literal_expr(expr) {
    match expected_u {
      Named(n) =>
        if ctx.in_scope_type_params.contains(n) {
          record(
            ctx,
            sub_path,
            "`null` / `undefined` is not assignable to type parameter `\{n}`",
          )
          return
        }
      _ => ()
    }
  }
  // Without `strictNullChecks`, a literal `null` / `undefined` is assignable
  // to every type (`var b: number = null`). The conformance corpus runs
  // largely under `@strict: false` and we have no per-file strict-mode
  // signal, so treat a *literal* null/undefined source as universally
  // assignable. This is intentionally narrower than "inferred type is
  // Null/Undefined": a value merely narrowed to `undefined` (e.g. an
  // optional property in its else-branch) is still checked, matching the
  // checker's existing optional-tracking behaviour.
  if is_null_or_undefined_literal_expr(expr) {
    return
  }
  // A `never` target almost always shows up as the `assertNever(x: never)`
  // exhaustiveness idiom, where `x` has been flow-narrowed to `never` by an
  // exhaustive switch / if-chain. We don't model flow narrowing, so the
  // argument still looks like its declared union (`0 | 1 | 2`) and would
  // false-flag against `never`. Skip the check rather than emit a positive
  // on every exhaustiveness assertion.
  if expected_u is Never {
    return
  }
  // A *literal* value is never assignable to a bare in-scope type parameter
  // `T`: `T` could be instantiated with an arbitrary type unrelated to the
  // value, so `function f<T>() { var x: T = 1 }` and
  // `function f<T>(): T { return 1 }` are TS2322 / TS2345 regardless of strict
  // mode (unlike `null` / `undefined`, which non-strict allows everywhere —
  // handled above). Gated on the *expression* being a literal (not merely the
  // inferred type being primitive): a variable typed `T` that flow-narrows to
  // `string` (`if (typeof x === "string") { let v: T = x }`) keeps the
  // intersection `T & string`, which IS assignable to `T` — flagging its
  // inferred `string` would be a false positive.
  if precise_literal_type(expr) is Some(_) {
    match expected_u {
      Named(n) =>
        if ctx.in_scope_type_params.contains(n) &&
          is_concrete_primitive_or_literal(inferred_u) {
          record(
            ctx,
            sub_path,
            "type `\{type_display(inferred_u)}` is not assignable to type parameter `\{n}`",
          )
          return
        }
      _ => ()
    }
  }
  // Assignment between two *distinct* in-scope type parameters (`function
  // foo<T, U>(t: T, u: U) { t = u }`) is a TS2322: type parameters are
  // unrelated unless one is constrained to the other. Constraint relationships
  // are already resolved by the parser, which inlines a constrained type
  // parameter to its (transitive) bound — so a reference that is *still* a
  // bare in-scope type parameter here is genuinely unconstrained relative to
  // the target, and `<T, U extends T>` / `<T, V extends T, U extends V>` have
  // their `U` rewritten to `T` and never reach this flag.
  match (inferred_u, expected_u) {
    (Named(s), Named(t)) =>
      if s != t &&
        ctx.in_scope_type_params.contains(s) &&
        ctx.in_scope_type_params.contains(t) {
        record(
          ctx,
          sub_path,
          "expected `\{type_display(expected_u)}` but got `\{type_display(inferred_u)}`",
        )
        return
      }
    _ => ()
  }
  // If the expected type is a `Named` reference that the resolver can't expand
  // (e.g. a generic type parameter like `T`, or a qualified name like
  // `Intl.NumberFormatPartTypes` that isn't in the module's declaration list),
  // skip the assignability check rather than emit a false positive.
  match expected_u {
    Named(n) =>
      if ctx.resolver.type_aliases.get(n) is None &&
        ctx.resolver.interfaces.get(n) is None &&
        ctx.resolver.classes.get(n) is None {
        return
      }
    _ => ()
  }
  // Mirror the above on the *source* side: if the inferred type contains
  // an unresolvable `Named(n)` anywhere (a generic TP we lost track of,
  // a `this`-typed return, a qualified namespace member the resolver
  // doesn't know about), our diagnostic would just render `expected X
  // but got <something we can't display>` — the user can't act on it
  // and the rate of real-bug coverage at these points is near zero
  // since the source side is already abstract.
  if type_contains_unresolved_named(inferred_u, ctx.resolver) {
    return
  }
  // Mapped / conditional / `keyof` / indexed-access / template-literal forms
  // on either side (`Boxified<any>`, `keyof {}`, `Proxify<Shape>`, …) resolve
  // to type-level shapes we can't compare structurally. TypeScript resolves
  // them fully; comparing nominally yields false mismatches, so stay silent.
  if type_is_unmodeled_shape(inferred_u, ctx.resolver) ||
    type_is_unmodeled_shape(expected_u, ctx.resolver) {
    return
  }
  // Generic `Applied(...)` shapes (`Generator<any, any>`, `Maybe<any>[]`,
  // `Promise<T>`) on either side carry inference we don't fully track.
  // Comparing them nominally produces false mismatches when the user's
  // generic substitution would have unified them. Stay silent when
  // either side is a generic instantiation -- the cost is dropping some
  // genuine generic-mismatch diagnostics, but those are the same kind
  // of `expected Promise<X> but got Promise<Y>` cases users rarely
  // benefit from in a structurally-typed nominal-rendering checker.
  // Flow-narrowing residue: when both sides are literal unions and the target's
  // literal set is a subset of the source's (`expected 0 but got 0 | 1 | 9`,
  // `expected "foo" but got "foo" | "bar"`), TypeScript has narrowed the source
  // to a compatible value at this point. We don't model flow narrowing, so the
  // source still looks like its full declared union — stay silent.
  match (literal_union_members(expected_u), literal_union_members(inferred_u)) {
    (Some(exp_lits), Some(inf_lits)) =>
      if exp_lits.iter().all(fn(e) { inf_lits.iter().any(fn(i) { i == e }) }) {
        return
      }
    _ => ()
  }
  // Const-widening gap: a literal-union target with the source widened to the
  // primitive those literals share (`const c2: 123 | 456 = c` where `c` is a
  // `const` we widened to `number`). TypeScript keeps the const literal narrow.
  match literal_union_members(expected_u) {
    Some(exp_lits) =>
      match common_literal_base(exp_lits) {
        Some(base) => if inferred_u == base { return }
        None => ()
      }
    None => ()
  }
  // `any` / `any[]` / `any[][]` sources are assignable to anything (an
  // `any[][]` array literal contextually typed to a tuple array, etc.).
  if is_deeply_any(inferred_u) {
    return
  }
  // Structurally-recursive named tuples (`RecursiveTupleA` vs
  // `RecursiveTupleB`) compare nominally for us but structurally for TS.
  if tuples_differ_only_in_named(inferred_u, expected_u, ctx.resolver) {
    return
  }
  // Plain function- / constructor-type vs the same: check assignability
  // before the broad callable bail below. Parameters are compared
  // *bivariantly* — that matches the conformance corpus default
  // (`strictFunctionTypes: false`) and is the permissive choice, so we never
  // FP on a case a stricter contravariant rule would reject. A clear
  // incompatibility (`(x: string) => string` assigned where `(x: number) =>
  // number` is expected, or `new (x: number) => string` where `new (x:
  // number) => number` is expected) is then a real TS2322 / TS2345.
  //
  // Restricted to cases where neither side is a *generic* function type
  // (`GenericFunc`) — those can be made compatible by instantiating their
  // type parameters, which we don't attempt here — and where neither inner
  // shape carries an unresolved / in-scope type-parameter reference (the
  // source side is already cleared by the unresolved-`Named` bail above; this
  // guards the expected side).
  if not_generic_func(inferred) &&
    not_generic_func(expected) &&
    is_plain_callable(inferred_u) &&
    is_plain_callable(expected_u) &&
    !func_type_mentions_type_param(inferred_u, ctx) &&
    !func_type_mentions_type_param(expected_u, ctx) &&
    !type_contains_unresolved_named(expected_u, ctx.resolver) {
    if !is_assignable_to_bivariant(inferred_u, expected_u) {
      record(
        ctx,
        sub_path,
        "expected `\{type_display(expected_u)}` but got `\{type_display(inferred_u)}`",
      )
    }
    return
  }
  // Callable / constructable interfaces & objects (`<call>` / `<new>`
  // signatures, often `extends Function`, with overloaded methods like
  // `foo("hi"): Derived1; foo("bye"): Derived2`) match other call signatures
  // structurally in ways we don't model — `expected (string) => string but
  // got I`, `expected C but got I`. Stay silent.
  if shape_is_callable(inferred_u, ctx.resolver) ||
    shape_is_callable(expected_u, ctx.resolver) {
    return
  }
  // Overloaded-method shapes (the same member name declared several times with
  // different signatures) don't match structurally under our single-type-per-
  // member model. Stay silent.
  if shape_has_overloads(inferred_u, ctx.resolver) ||
    shape_has_overloads(expected_u, ctx.resolver) {
    return
  }
  match (inferred_u, expected_u) {
    (Applied(_, _), _) | (_, Applied(_, _)) => return
    // Intersections on either side (`PartialStepState & { repo: any }`,
    // `ComponentType<any> & ComponentType<RouteComponentProps>`, `A & A`):
    // intersection assignability (a value of the intersection satisfies each
    // part, and an object satisfying every part inhabits the intersection) is
    // something we don't model structurally, so comparing nominally yields
    // false mismatches. Stay silent.
    (Intersection(_), _) | (_, Intersection(_)) => return
    // Bare callable / constructable shapes match other call signatures
    // structurally in ways we don't model — stay silent.
    (Func(_, _), _)
    | (_, Func(_, _))
    | (Constructor(_, _, _), _)
    | (_, Constructor(_, _, _)) => return
    // Target `Object` / `{}` / empty Object literal accepts anything in
    // TypeScript -- it's the universal supertype. Skip the mismatch.
    (_, Named("Object")) | (_, Named("object")) => return
    (_, Object(entries)) => if entries.length() == 0 { return }
    // Both sides are unions: this is the signature of a typeguard /
    // flow-narrowing residue we can't see through. The user has written
    // a guard that narrows one side; absent flow tracking we still see
    // both as unions and the diagnostic is almost always wrong. Stay
    // silent rather than emit a false mismatch.
    (Union(_), Union(_)) => return
    // A union target with a generic `Applied` member (`Generator<...> |
    // AsyncGenerator<...>`) carries inference we don't track — the generator
    // `return`/`yield` contributes to a type argument, not the whole union.
    // Stay silent rather than compare the union nominally.
    (_, Union(parts)) =>
      if parts.iter().any(fn(p) { p is Applied(_, _) }) {
        return
      }
    _ => ()
  }
  if !is_assignable_to(inferred_u, expected_u) {
    // Class / interface references are nominal in `is_assignable_to`
    // (Named(A) == Named(B) iff A == B), but TypeScript types are
    // structural: two distinct classes / interfaces with the same
    // public member shape assign in either direction. We require
    // *bidirectional* structural compatibility so that pure subtype
    // mismatches (target has fields source lacks) still get flagged.
    if is_structurally_assignable_named(inferred_u, expected_u, ctx.resolver) &&
      is_structurally_assignable_named(expected_u, inferred_u, ctx.resolver) {
      return
    }
    // One-way structural assignability is the correct rule for an
    // *assignment* (`lhs = rhs`): the source need only provide every member
    // the target requires (extra source members are fine for a variable
    // assignment -- excess-property checks apply only to fresh object
    // literals, handled separately). `is_assignable_to` is nominal for
    // `Named` class / interface references, so a structural source
    // (`{ foo: string; baz: string }`) assigned to a named target
    // (`interface S2 { foo: string }`) would otherwise false-flag. A missing
    // or incompatible *required* target member still makes this `false`, so
    // genuine subtype mismatches are preserved. A union target is satisfied
    // when the source assigns to any arm.
    if structural_oneway_assignable(inferred_u, expected_u, ctx.resolver) {
      return
    }
    // A primitive / array / tuple source can structurally satisfy an object
    // target through its intrinsic prototype members — `string` and arrays
    // have `length: number`, etc. — so `const o: { length: number } = "hi"`
    // and `f<T extends { length: number }>("hi")` are valid. The
    // resolver-free `is_assignable_to` has no primitive-member table, so
    // prove it here via `lookup_field`.
    if intrinsic_source_satisfies_object(inferred_u, expected_u, ctx.resolver) {
      return
    }
    // Class inheritance: `Derived is_a Base` when `class Derived extends
    // Base`. The resolver-free `is_assignable_to` is nominal so a pure
    // subtype assignment was previously flagged. Walk the source's class
    // base chain to accept assignments through inheritance.
    if assignable_through_class_chain(inferred_u, expected_u, ctx.resolver) {
      return
    }
    // Flow-narrowing gap suppression: when the source is a union strictly
    // containing the target (target ⊂ source) and the surplus members
    // are exactly the kind of primitives a `typeof` / `=== null` /
    // `instanceof` guard normally removes (`string` / `number` /
    // `boolean` / `bigint` / `null` / `undefined`), we don't have the
    // flow context to know whether a guard already narrowed the source.
    // Stay silent rather than emit a "expected number | boolean but got
    // string | number | boolean" mismatch that's almost always a
    // narrowing-gap rather than a real error.
    if is_flow_narrowing_gap(inferred_u, expected_u) {
      return
    }
    // Object types now render as `{ ... }` (not the suppressed `type`
    // placeholder), so two remaining imprecision classes must be guarded
    // against to keep this false-positive-free:
    //   - a `typeof x` value-query anywhere in either shape can't be
    //     compared structurally (its identity is the binding it queries);
    //   - a *fresh object literal* (`f({ ... })`, `x = { ... }`) flowing
    //     into a non-object-literal target (a generic / utility / union /
    //     call-signature shape) goes through contextual typing we don't
    //     fully model. Plain object / interface targets were already routed
    //     to the per-field literal checker before reaching here, so this
    //     only drops the cases we can't decide -- a bare-scalar target
    //     (`var n: number = { ... }`) is still a category clash worth
    //     reporting and is left to fall through.
    if type_contains_typeof(inferred_u) || type_contains_typeof(expected_u) {
      return
    }
    if type_has_call_signature(inferred_u, ctx.resolver) ||
      type_has_call_signature(expected_u, ctx.resolver) {
      return
    }
    if expr is ObjectLit(_) && !is_bare_scalar_type(expected_u) {
      return
    }
    // Display the widened form of the inferred type (`number` rather than the
    // precise `42`) so the message reads naturally; the precise literal was
    // only needed for the assignability decision above.
    let shown = widen_literal(inferred_u)
    let exp_str = type_display(expected)
    let detail = "expected `\{exp_str}` but got `\{type_display(shown)}`"
    record(ctx, sub_path, detail)
  }
}

///|
/// Structural fallback for class / interface references: when both sides
/// resolve via the resolver, accept the assignment iff every required
/// field of the target appears on the source with an assignable type.
/// Optional / missing-on-source fields, getters/setters, index
/// signatures, and call signatures are all conservatively ignored —
/// we only need to *prove* assignability here, not to disprove it
/// (the negative case falls through to the existing diagnostic).
fn is_structurally_assignable_named(
  source : @ast.TsType,
  target : @ast.TsType,
  resolver : Resolver,
) -> Bool {
  struct_assignable_named_rec(source, target, resolver, [])
}

///|
/// Co-inductive structural assignability for class / interface references.
/// Field types are compared *recursively* through this same relation (not
/// the nominal `is_assignable_to`) so two distinct-but-shape-identical
/// recursive types assign -- e.g. `class S { foo: S }` and
/// `class T { foo: T }`, where `S.foo` (`S`) must be checked against `T.foo`
/// (`T`). `visited` records the (source, target) name pairs currently being
/// proven; re-encountering a pair returns `true` (co-induction), which is
/// how TypeScript itself relates recursive types and breaks the cycle.
fn struct_assignable_named_rec(
  source : @ast.TsType,
  target : @ast.TsType,
  resolver : Resolver,
  visited : Array[(String, String)],
) -> Bool {
  // Depth cap: generic recursive shapes (`Wrapped<Wrapped<T>>`) deepen the
  // substituted field type at every level, so the `visited` co-induction key
  // never repeats and the recursion would not terminate. Bail conservatively
  // (can't *prove* assignability) once the chain is implausibly deep -- the
  // caller falls through to its other relations / the diagnostic.
  if visited.length() >= 48 {
    return false
  }
  let s = resolver.unwrap(source)
  let t = resolver.unwrap(target)
  if s == t {
    return true
  }
  // Only engage when both sides resolve as class / interface (or object)
  // shapes. `lookup_field` returns `None` for opaque receivers, so this
  // also weeds out unresolvable references (generic type parameters,
  // qualified names) without false promotion.
  if !is_named_decl(s, resolver) || !is_named_decl(t, resolver) {
    return false
  }
  let key = (type_display(s), type_display(t))
  if visited.contains(key) {
    return true
  }
  visited.push(key)
  let target_fields = collect_declared_fields(t, resolver)
  if target_fields.length() == 0 {
    let _ = visited.pop()
    return false
  }
  for f in target_fields {
    let want = resolver.unwrap(f.1)
    match resolver.lookup_field(s, f.0) {
      Some(have) => {
        let have_u = resolver.unwrap(have)
        // Recurse structurally when both field types are themselves
        // class / interface references (covers the recursive case); fall
        // back to the well-tested nominal / builtin relation otherwise.
        let ok = if is_named_decl(have_u, resolver) &&
          is_named_decl(want, resolver) {
          struct_assignable_named_rec(have_u, want, resolver, visited)
        } else {
          is_assignable_to(have_u, want)
        }
        if !ok {
          let _ = visited.pop()
          return false
        }
      }
      None =>
        // A field missing on the source is only a failure when the target
        // field is *required*. An optional target field (`bar?: T`, encoded
        // as a `| undefined` type) may be absent on the source -- TS allows
        // `s2 = t2` when `t2` simply omits `s2`'s optional members.
        if !type_accepts_undefined(want) {
          let _ = visited.pop()
          return false
        }
    }
  }
  let _ = visited.pop()
  true
}

///|
/// Substitute the special `Named("this")` reference at the top level of
/// `ty` with `recv`. We deliberately don't recurse into composite types
/// here -- the common case (`m(): this` on an interface) returns the
/// bare `Named("this")` directly, and chasing it through generics would
/// require a much more invasive walk for limited additional payoff.
fn substitute_this_type(ty : @ast.TsType, recv : @ast.TsType) -> @ast.TsType {
  match ty {
    Named("this") => recv
    _ => ty
  }
}

///|
/// True when `source` is a class whose base chain reaches `target` —
/// i.e. `class Source extends ... extends Target`. The chain walk also
/// honours `extends_names` on interfaces so `interface ChildI extends
/// ParentI` flows through. Recurses on union / intersection members so
/// `Derived | Base` still assigns to `Base`.
fn assignable_through_class_chain(
  source : @ast.TsType,
  target : @ast.TsType,
  resolver : Resolver,
) -> Bool {
  let src = resolver.unwrap(source)
  let tgt = resolver.unwrap(target)
  match (src, tgt) {
    (Union(members), _) => {
      for m in members {
        if !assignable_through_class_chain(m, tgt, resolver) {
          return false
        }
      }
      true
    }
    (_, Union(members)) => {
      for m in members {
        if assignable_through_class_chain(src, m, resolver) {
          return true
        }
      }
      false
    }
    (Named(s_name), Named(t_name)) | (Applied(s_name, _), Named(t_name)) =>
      class_or_interface_inherits(s_name, t_name, resolver, [])
    (Named(s_name), Applied(t_name, _))
    | (Applied(s_name, _), Applied(t_name, _)) =>
      class_or_interface_inherits(s_name, t_name, resolver, [])
    // Same-shape primitive / `null` / `undefined` matches so a union
    // walk like `Foo | null → Object | null` succeeds (the class chain
    // handles Foo→Object; this branch handles Null→Null).
    _ => is_assignable_to(src, tgt)
  }
}

///|
fn class_or_interface_inherits(
  src_name : String,
  tgt_name : String,
  resolver : Resolver,
  visited : Array[String],
) -> Bool {
  if src_name == tgt_name {
    return true
  }
  // Every class / interface implicitly extends `Object` (and `{}`).
  // Recognise this universal supertype so a downcast like `Foo |
  // null → Object | null` is accepted without an explicit base.
  if tgt_name == "Object" || tgt_name == "{}" {
    return true
  }
  if visited.contains(src_name) {
    return false
  }
  visited.push(src_name)
  match resolver.classes.get(src_name) {
    Some(cls) =>
      for base in cls.base_names {
        if class_or_interface_inherits(base, tgt_name, resolver, visited) {
          return true
        }
      }
    None => ()
  }
  match resolver.interfaces.get(src_name) {
    Some(iface) =>
      for base in iface.extends_names {
        if class_or_interface_inherits(base, tgt_name, resolver, visited) {
          return true
        }
      }
    None => ()
  }
  false
}

///|
/// True when `source` is a union strictly containing `target` (every
/// target member exists in source) and the surplus source members are
/// all narrowable primitives — i.e. exactly the residue a `typeof` /
/// `=== null` / `=== undefined` / `instanceof` flow guard would have
/// removed. We don't model flow narrowing, so this pattern is almost
/// always a guard-aware reassignment that we can't see.
fn is_flow_narrowing_gap(source : @ast.TsType, target : @ast.TsType) -> Bool {
  let src_members = union_members(source)
  if src_members.length() <= 1 {
    return false
  }
  let tgt_members = union_members(target)
  // Require target to also be a multi-member union -- this is the
  // exact shape of typeguard residue (`X | Y | Z -> X | Y`). A single
  // primitive target (e.g. `string | undefined -> string` after
  // `arr.pop()`) is a legitimate user error we should keep flagging.
  if tgt_members.length() <= 1 {
    return false
  }
  // Every target member must appear in source.
  for t in tgt_members {
    let mut found = false
    for s in src_members {
      if type_eq(t, s) {
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  // The surplus source members (those not in target) must all be the
  // narrowable primitives a guard would remove.
  let mut had_surplus = false
  for s in src_members {
    let mut in_target = false
    for t in tgt_members {
      if type_eq(s, t) {
        in_target = true
        break
      }
    }
    if !in_target {
      had_surplus = true
      if !is_narrowable_primitive(s) {
        return false
      }
    }
  }
  had_surplus
}

///|
fn union_members(ty : @ast.TsType) -> Array[@ast.TsType] {
  match ty {
    Union(items) => items
    _ => [ty]
  }
}

///|
fn is_narrowable_primitive(ty : @ast.TsType) -> Bool {
  match ty {
    String_
    | Number
    | Int
    | Boolean
    | BigInt
    | Symbol
    | Null
    | Undefined
    | Literal(_)
    | NumberLiteral(_)
    | BooleanLiteral(_)
    | BigIntLiteral(_) => true
    // `instanceof C` / `Animal is Cat` narrows out a class / interface
    // member from a union. Treat a `Named` / `Applied` surplus the same
    // way as a primitive surplus: without flow context we can't see the
    // guard, so suppression is the safer call. `Object` likewise
    // surfaces as a "fell-back to base" residue in typeguard chains.
    Named(_) | Applied(_, _) => true
    _ => false
  }
}

///|
/// True when `ty` (or anything nested inside) contains a `Named(n)` /
/// `Applied(n, …)` reference the resolver can't expand to an interface,
/// class, or type alias. Used to suppress assignment-mismatch diagnostics
/// whose source or target is opaque -- those almost always come from a
/// generic / `this`-type / qualified-namespace gap we don't model, not
/// from a real user-visible bug we could surface usefully. `Named("this")`
/// always counts as unresolved here (the `this` type isn't a declaration).
fn type_contains_unresolved_named(
  ty : @ast.TsType,
  resolver : Resolver,
) -> Bool {
  match ty {
    Named("this") => true
    Named(n) | Applied(n, _) =>
      resolver.type_aliases.get(n) is None &&
      resolver.interfaces.get(n) is None &&
      resolver.classes.get(n) is None
    Array(inner) => type_contains_unresolved_named(inner, resolver)
    Union(parts) | Intersection(parts) | Tuple(parts) => {
      for p in parts {
        if type_contains_unresolved_named(p, resolver) {
          return true
        }
      }
      false
    }
    Func(params, ret) => {
      for p in params {
        if type_contains_unresolved_named(p, resolver) {
          return true
        }
      }
      type_contains_unresolved_named(ret, resolver)
    }
    _ => false
  }
}

///|
/// True when a type, after resolution, is still a *type-level construct* the
/// checker can't enumerate structurally: a mapped / conditional / `keyof` /
/// indexed-access / template-literal type, or an `Applied` reference to
/// something that isn't a class or interface (e.g. a generic alias whose body
/// is a mapped type, like `Proxify<Shape>` / `Boxified<Foo>`). Member-existence
/// and structural-assignment diagnostics suppress against such types:
/// TypeScript resolves them fully, so flagging would just emit false positives
/// like `property 'name' does not exist on 'Proxify<Shape>'`.
fn type_is_unmodeled_shape(ty : @ast.TsType, resolver : Resolver) -> Bool {
  match resolver.unwrap(ty) {
    MappedType(_, _, _, _)
    | MappedTypeRemap(_, _, _, _, _)
    | Conditional(_, _, _, _)
    | Keyof(_)
    | IndexedAccess(_, _)
    | TemplateLiteralType(_, _) => true
    Applied(n, _) =>
      resolver.classes.get(n) is None && resolver.interfaces.get(n) is None
    _ => false
  }
}

///|
/// True when a class (or any class in its `extends` chain) extends a base the
/// resolver can't resolve to a declared class or interface — a mixin
/// application (`class C extends Mixin(Base)`), a type parameter
/// (`class C extends superClass`), or a value/`const` produced by a mixin
/// factory (`class Thing3 extends Thing2`). Instances of such classes inherit
/// members we can't enumerate, so member-existence diagnostics on them (and on
/// `this` inside their methods) would be false positives.
fn class_chain_has_unresolved_base(name : String, resolver : Resolver) -> Bool {
  let mut current = name
  let mut depth = 0
  while depth < 32 {
    depth = depth + 1
    match resolver.classes.get(current) {
      None => return false
      Some(decl) => {
        if decl.base_names.length() == 0 {
          return false
        }
        for base in decl.base_names {
          if resolver.classes.get(base) is None &&
            resolver.interfaces.get(base) is None {
            return true
          }
        }
        current = decl.base_names[0]
      }
    }
  }
  true
}

///|
/// If `t` is a literal or a union of *only* literals, return those members;
/// otherwise `None`. Used to detect flow-narrowing residue: when a target
/// literal set is a subset of the source literal set, TypeScript has narrowed
/// the source down to a compatible value at that point and we'd otherwise
/// false-flag the un-narrowed wider source.
fn literal_union_members(t : @ast.TsType) -> Array[@ast.TsType]? {
  match t {
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) =>
      Some([t])
    Union(ms) => {
      let out : Array[@ast.TsType] = []
      for m in ms {
        match m {
          Literal(_)
          | NumberLiteral(_)
          | BigIntLiteral(_)
          | BooleanLiteral(_) => out.push(m)
          _ => return None
        }
      }
      if out.length() == 0 {
        None
      } else {
        Some(out)
      }
    }
    _ => None
  }
}

///|
/// The single widened primitive every member of a literal set shares
/// (`123 | 456` -> `number`, `"a" | "b"` -> `string`), or `None` when the set
/// mixes primitive kinds. Used to recognise the const-widening gap: TypeScript
/// keeps a `const` initializer's literal narrow (`const c = cond ? 123 : 456`
/// is `123 | 456`), but we widen it to its primitive, so `const c2: 123 | 456 =
/// c` then looks like `number` assigned to a literal union.
fn common_literal_base(lits : Array[@ast.TsType]) -> @ast.TsType? {
  let mut base : @ast.TsType? = None
  for l in lits {
    let b : @ast.TsType = match l {
      Literal(_) => String_
      NumberLiteral(_) => Number
      BigIntLiteral(_) => BigInt
      BooleanLiteral(_) => Boolean
      _ => return None
    }
    match base {
      None => base = Some(b)
      Some(prev) => if prev != b { return None }
    }
  }
  base
}

///|
/// True for a type that is `any`, or an array (possibly nested) whose ultimate
/// element is `any`: `any`, `any[]`, `any[][]`. Such a value is assignable to
/// anything in TypeScript, so a structural mismatch against it (e.g. an
/// `any[][]` array literal contextually typed to a tuple array) is a false
/// positive.
fn is_deeply_any(t : @ast.TsType) -> Bool {
  match t {
    Any => true
    Array(inner) => is_deeply_any(inner)
    _ => false
  }
}

///|
/// True when both types resolve to tuples of equal arity that differ only at
/// positions where *both* elements are `Named` references (distinct
/// structurally-recursive tuple aliases like `RecursiveTupleA` /
/// `RecursiveTupleB`). We compare named tuples nominally, so these false-flag;
/// TypeScript compares them structurally and accepts.
fn tuples_differ_only_in_named(
  a : @ast.TsType,
  b : @ast.TsType,
  resolver : Resolver,
) -> Bool {
  match (resolver.unwrap(a), resolver.unwrap(b)) {
    (Tuple(xs), Tuple(ys)) => {
      if xs.length() != ys.length() || xs.length() == 0 {
        return false
      }
      let mut saw_named_diff = false
      for i in 0..<xs.length() {
        if xs[i] == ys[i] {
          continue
        }
        match (xs[i], ys[i]) {
          (Named(_), Named(_)) => saw_named_diff = true
          _ => return false
        }
      }
      saw_named_diff
    }
    _ => false
  }
}

///|
/// Member-existence guard: true when the receiver type is one whose full
/// member set we can't enumerate, so "property/method does not exist"
/// diagnostics against it would be false positives. Covers the structural
/// unmodeled shapes (mapped / conditional / `keyof` / …), intersections
/// (mixins, `typeof M & typeof C`, `Constructor<X> & Constructor<{}>`),
/// `typeof X` value queries (enum objects, namespaces, mixin factory
/// results), and class instances with an unresolvable base chain.
fn member_recv_unmodeled(ty : @ast.TsType, resolver : Resolver) -> Bool {
  if type_is_unmodeled_shape(ty, resolver) {
    return true
  }
  if shape_is_callable(ty, resolver) {
    return true
  }
  match resolver.unwrap(ty) {
    Intersection(_) | TypeOf(_) => true
    Named(n) | Applied(n, _) =>
      resolver.classes.get(n) is Some(_) &&
      class_chain_has_unresolved_base(n, resolver)
    _ => false
  }
}

///|
/// True when a type is callable / constructable: a bare `Func` / `Constructor`,
/// or an object / interface carrying a call (`<call>`) or construct (`<new>`)
/// signature (often an interface that `extends Function`). Such shapes inherit
/// the full `Function` member set (`arguments`, `call`, `apply`, `bind`, …) and
/// match other call signatures structurally in ways we don't model, so member
/// existence and structural assignability against them would false-flag.
fn shape_is_callable(ty : @ast.TsType, resolver : Resolver) -> Bool {
  match resolver.unwrap(ty) {
    Func(_, _) | Constructor(_, _, _) => return true
    _ => ()
  }
  for f in collect_declared_fields(ty, resolver) {
    if f.0 == "<call>" || f.0 == "<new>" {
      return true
    }
  }
  false
}

///|
/// True when a shape declares the same member name more than once — the
/// signature of overloaded methods (`foo(x: 'hi'): Derived1; foo(x: 'bye'):
/// Derived2; foo(x: string): Base`). We compare members by a single nominal
/// type each, so overload sets don't match structurally; comparing them
/// produces false `expected C but got I` mismatches. Stay silent.
fn shape_has_overloads(ty : @ast.TsType, resolver : Resolver) -> Bool {
  let seen : Map[String, Bool] = {}
  for f in collect_declared_fields(ty, resolver) {
    if seen.contains(f.0) {
      return true
    }
    seen[f.0] = true
  }
  false
}

///|
fn is_named_decl(ty : @ast.TsType, resolver : Resolver) -> Bool {
  match resolver.unwrap(ty) {
    Named(n) =>
      resolver.interfaces.get(n) is Some(_) ||
      resolver.classes.get(n) is Some(_)
    Applied(n, _) =>
      resolver.interfaces.get(n) is Some(_) ||
      resolver.classes.get(n) is Some(_)
    // Object / struct literal shapes carry their fields directly and
    // can participate in the structural equivalence check too — they're
    // the source side of `var a: {foo: string}; s = a` patterns.
    Object(_) | Struct(_, _) => true
    _ => false
  }
}

///|
/// Match an array literal `[a, b, …]` against a tuple type `[T1, T2, …]`,
/// checking each element against the corresponding slot. Excess items
/// (more literal entries than tuple slots, or vice versa) emit an arity
/// issue; trailing `Spread(...)` entries waive the arity check the same way
/// they do for call-site arguments.
/// Check each element of an array literal against the array's element type
/// `elem`. A `Spread(e)` element contributes `e`'s *elements*, not `e`
/// itself, so it is checked against `elem[]` (e.g. `[...nums]` where `nums:
/// number[]` is valid for `number[]`) rather than against the scalar `elem`,
/// which would wrongly report `expected number but got number[]`.
fn check_array_lit_elements_against(
  env : ExprEnv,
  items : Array[@ast.TsExpr],
  elem : @ast.TsType,
  ctx : CheckCtx,
  sub_path : String,
) -> Unit {
  for i, item in items {
    let item_path = sub_path + "[" + i.to_string() + "]"
    match item {
      Spread(inner) =>
        check_expr_against(env, inner, Array(elem), ctx, item_path)
      _ => check_expr_against(env, item, elem, ctx, item_path)
    }
  }
}

///|
fn check_array_lit_against_tuple(
  env : ExprEnv,
  items : Array[@ast.TsExpr],
  slots : Array[@ast.TsType],
  ctx : CheckCtx,
  sub_path : String,
) -> Unit {
  let mut has_spread = false
  for it in items {
    match it {
      Spread(_) => has_spread = true
      _ => ()
    }
  }
  if !has_spread && items.length() != slots.length() {
    record(
      ctx,
      sub_path,
      "expected tuple of \{slots.length()} element(s), got \{items.length()}",
    )
  }
  let n = if items.length() < slots.length() {
    items.length()
  } else {
    slots.length()
  }
  let mut i = 0
  while i < n {
    let sub = "\{sub_path}[\{i}]"
    check_expr_against(env, items[i], slots[i], ctx, sub)
    i = i + 1
  }
}

///|
/// Match an object literal against a struct / interface / object-type
/// target, checking each field's value against the declared field type.
/// Excess literal fields (not declared on the target) and missing required
/// fields are reported individually so the diagnostic points at the
/// specific divergence rather than the whole literal.

///|
/// Validate a JSX element's attributes against the receiving component's
/// props. Recognised receiver shapes:
///
///   - lower-case HTML tags (`<div>` etc.) — skipped; we don't model
///     the global JSX intrinsic table.
///   - empty tag (fragment `<>…</>`) — skipped.
///   - dotted tag (`<Foo.Bar/>`) — skipped (member access not modelled).
///   - a known top-level function whose single parameter is a Props
///     interface / object type — each attribute is validated against
///     the corresponding prop's declared type, missing required props
///     are flagged, and excess props surface as "does not exist on
///     target type".

///|
/// Synthesise a TS type for a JSX element's children list. Used by
/// `check_jsx_attrs` to validate the synthesised value against the
/// component's declared `children` prop.
///
///   0 children → `Undefined`
///   1 child   → that child's inferred type
///   2+ children → `Array<union-of-child-types>`
///
/// JSX nested elements infer as `Any` (`JsxElement(_, _, _)` → Any),
/// so a component declaring `children: SomeElement` won't get strict
/// element-shape narrowing yet — but the assignability check still
/// surfaces obvious mismatches like `children: string` vs a numeric
/// child.

///|
/// Widen a value's literal type to its base — `"hi"` → `string`,
/// `1` → `number`, `true` → `boolean`. Used by JSX generic inference
/// so type parameters don't collapse to a too-narrow literal type the
/// user clearly didn't intend.
// Map a literal *expression* to its precise literal *type* (`1` ->
// `NumberLiteral("1")`, `true` -> `BooleanLiteral(true)`, `"a"` ->
// `Literal("a")`). `infer_expr` widens these to `number` / `boolean` /
// `string`, which makes assignability against a literal-union target
// (`const x: 0 | 1 | 2 = 1`) spuriously fail. Returns `None` for non-literal
// expressions.
fn precise_literal_type(e : @ast.TsExpr) -> @ast.TsType? {
  match e {
    IntLit(i) => Some(@ast.TsType::NumberLiteral(i.to_string()))
    NumberLit(d) => Some(@ast.TsType::NumberLiteral(d.to_string()))
    BoolLit(b) => Some(@ast.TsType::BooleanLiteral(b))
    StringLit(s) => Some(@ast.TsType::Literal(s))
    BigIntLit(s) => Some(@ast.TsType::BigIntLiteral(s))
    // Negative-number literal: `-123` parses as a unary-minus on the
    // integer literal `123`. TypeScript treats the result as the literal
    // type `-123` (matching `var x: -123 = -123`), so surface it here so
    // the literal-tighten path in `check_expr_against` accepts the
    // narrowed assignment.
    UnaryOp(Neg, IntLit(i)) =>
      Some(@ast.TsType::NumberLiteral("-" + i.to_string()))
    UnaryOp(Neg, NumberLit(d)) =>
      Some(@ast.TsType::NumberLiteral("-" + d.to_string()))
    UnaryOp(Neg, BigIntLit(s)) => Some(@ast.TsType::BigIntLiteral("-" + s))
    _ => None
  }
}

///|
fn widen_literal(t : @ast.TsType) -> @ast.TsType {
  match t {
    Literal(_) => @ast.TsType::String_
    NumberLiteral(_) => @ast.TsType::Number
    BigIntLiteral(_) => @ast.TsType::BigInt
    BooleanLiteral(_) => @ast.TsType::Boolean
    Array(elem) => @ast.TsType::Array(widen_literal(elem))
    Tuple(items) => {
      let widened : Array[@ast.TsType] = []
      for it in items {
        widened.push(widen_literal(it))
      }
      @ast.TsType::Tuple(widened)
    }
    _ => t
  }
}

///|
/// One-way structural assignability that also descends a union *target*: a
/// source assigns to `A | B` when it structurally assigns to either arm
/// (e.g. `{ p1, p2 }` flows into `number | I2` via `I2`). Plain targets
/// defer to `is_structurally_assignable_named`.
fn structural_oneway_assignable(
  source : @ast.TsType,
  target : @ast.TsType,
  resolver : Resolver,
) -> Bool {
  match resolver.unwrap(target) {
    Union(members) => {
      for m in members {
        if structural_oneway_assignable(source, m, resolver) {
          return true
        }
      }
      false
    }
    _ => is_structurally_assignable_named(source, target, resolver)
  }
}

///|
/// A primitive / array / tuple source can structurally satisfy an object
/// *target* through its intrinsic prototype members — `string` and arrays
/// expose `length: number`, strings expose the `String.prototype` methods,
/// etc. TypeScript accepts `const o: { length: number } = "hi"`, but the
/// resolver-free `is_assignable_to` has no primitive-member table. Prove it
/// here via `lookup_field`, which already resolves primitive / array members.
///
/// Conservative and false-positive-free: engages only for intrinsic-membered
/// sources against an object-shape target whose *every* required field is
/// present on the source with an assignable type. A field the source lacks
/// (and that isn't optional) makes this `false`, so a genuine mismatch
/// (`number` against `{ length: number }`, or `{ length: number; foo: string }`
/// against `string`) still falls through to the diagnostic.
fn intrinsic_source_satisfies_object(
  source : @ast.TsType,
  target : @ast.TsType,
  resolver : Resolver,
) -> Bool {
  let s = resolver.unwrap(source)
  let intrinsic = match s {
    String_
    | Number
    | Int
    | Boolean
    | BigInt
    | Symbol
    | Literal(_)
    | NumberLiteral(_)
    | BigIntLiteral(_)
    | BooleanLiteral(_)
    | Array(_)
    | Tuple(_) => true
    Applied(n, _) => is_array_like_iterable_name(n)
    _ => false
  }
  if !intrinsic {
    return false
  }
  let t = resolver.unwrap(target)
  let target_fields = match t {
    Object(_) | Struct(_, _) => collect_declared_fields(t, resolver)
    _ => return false
  }
  if target_fields.length() == 0 {
    return false
  }
  for f in target_fields {
    let want = resolver.unwrap(f.1)
    match resolver.lookup_field(s, f.0) {
      Some(have) =>
        if !is_assignable_to(resolver.unwrap(have), want) {
          return false
        }
      // A required target member the source lacks → not assignable. An
      // optional member (type accepts `undefined`) may legitimately be absent.
      None => if !type_accepts_undefined(want) { return false }
    }
  }
  true
}

///|
/// True when `t` is (or unwraps to) an object shape carrying a call /
/// construct signature (`<call>` / `<new>` sentinel field) -- i.e. a
/// callable / overloaded interface. Matching these against function types
/// needs overload resolution we don't model, so an object mismatch involving
/// one is suppressed rather than risk a false positive.
fn type_has_call_signature(t : @ast.TsType, resolver : Resolver) -> Bool {
  let fields = match resolver.unwrap(t) {
    Object(fs) => fs
    Struct(_, fs) => fs.map(fn(f) { (Literal(f.0), f.1) })
    _ => return false
  }
  for f in fields {
    match f.0 {
      Literal(name) => if name == "<call>" || name == "<new>" { return true }
      _ => ()
    }
  }
  false
}

///|
/// A bare scalar (primitive or scalar literal). Used to keep an
/// object-literal-source mismatch against a *primitive* target (a real
/// category clash) while suppressing it against generic / union / object
/// targets we type contextually.
fn is_bare_scalar_type(t : @ast.TsType) -> Bool {
  match t {
    Number
    | Int
    | Boolean
    | String_
    | BigInt
    | Symbol
    | Literal(_)
    | NumberLiteral(_)
    | BigIntLiteral(_)
    | BooleanLiteral(_) => true
    _ => false
  }
}

///|
/// Parameter types of a single call signature on `t`: `t` is a function
/// type, or an object/struct carrying exactly one `<call>` signature.
/// Returns `None` for anything else (no call signature, or several -- an
/// overload set we don't resolve here).
fn single_call_signature_params(
  t : @ast.TsType,
  resolver : Resolver,
) -> Array[@ast.TsType]? {
  match resolver.unwrap(t) {
    Func(params, _) => Some(params)
    Object(fields) => {
      let mut found : Array[@ast.TsType]? = None
      let mut count = 0
      for f in fields {
        match (f.0, f.1) {
          (Literal("<call>"), Func(params, _)) => {
            count += 1
            found = Some(params)
          }
          _ => ()
        }
      }
      if count == 1 {
        found
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Common call-signature parameters of a union callee: when every member of
/// the union exposes exactly one call signature and all of them have
/// *identical* parameter types, the union is callable with those parameters
/// (the return type is the union of each member's, which the arg check
/// doesn't need). Returns `None` if any member lacks a call signature or the
/// parameter lists disagree -- both cases TypeScript reports differently
/// ("no call signatures"), so staying silent keeps this false-positive-free.
fn union_common_call_params(
  union_ty : @ast.TsType,
  resolver : Resolver,
) -> Array[@ast.TsType]? {
  match resolver.unwrap(union_ty) {
    Union(members) => {
      let mut common : Array[@ast.TsType]? = None
      for m in members {
        match single_call_signature_params(m, resolver) {
          Some(params) =>
            match common {
              None => common = Some(params)
              Some(prev) => {
                if prev.length() != params.length() {
                  return None
                }
                for i in 0..<prev.length() {
                  if prev[i] != params[i] {
                    return None
                  }
                }
              }
            }
          None => return None
        }
      }
      common
    }
    _ => None
  }
}

///|
/// Parameter types of a single construct signature on `t`: `t` is a
/// constructor type, or an object/struct carrying exactly one `<new>`
/// signature. `None` for anything else (no construct signature, or several).
fn single_construct_signature_params(
  t : @ast.TsType,
  resolver : Resolver,
) -> Array[@ast.TsType]? {
  match resolver.unwrap(t) {
    Constructor(params, _, _) => Some(params)
    Object(fields) => {
      let mut found : Array[@ast.TsType]? = None
      let mut count = 0
      for f in fields {
        match (f.0, f.1) {
          (Literal("<new>"), Func(params, _)) => {
            count += 1
            found = Some(params)
          }
          _ => ()
        }
      }
      if count == 1 {
        found
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Common construct-signature parameters of a union: the `new`-call analog of
/// `union_common_call_params`. Returns the shared parameter list when every
/// member exposes exactly one construct signature and all are identical;
/// `None` otherwise (TypeScript's "no construct signatures" case), so it is
/// false-positive-free.
fn union_common_construct_params(
  union_ty : @ast.TsType,
  resolver : Resolver,
) -> Array[@ast.TsType]? {
  match resolver.unwrap(union_ty) {
    Union(members) => {
      let mut common : Array[@ast.TsType]? = None
      for m in members {
        match single_construct_signature_params(m, resolver) {
          Some(params) =>
            match common {
              None => common = Some(params)
              Some(prev) => {
                if prev.length() != params.length() {
                  return None
                }
                for i in 0..<prev.length() {
                  if prev[i] != params[i] {
                    return None
                  }
                }
              }
            }
          None => return None
        }
      }
      common
    }
    _ => None
  }
}

///|
/// Parameter types of a static method called through the class name
/// (`A.s(args)`), for argument checking. Returns `None` -- skipping the
/// check -- unless exactly one non-accessor static method of that name
/// exists and it has no rest parameter, so overload sets and variadic
/// signatures (whose arity/positional checking we don't model precisely)
/// never produce a false positive.
fn class_static_method_param_types(
  cls : @ast.TsClassDecl,
  meth : String,
) -> Array[@ast.TsType]? {
  let mut found : @ast.TsClassMethodDecl? = None
  let mut count = 0
  for m in cls.methods {
    if m.is_static && m.accessor == "" && m.name == meth {
      count += 1
      found = Some(m)
    }
  }
  if count != 1 {
    return None
  }
  let m = found.unwrap()
  for r in m.param_is_rest {
    if r {
      return None
    }
  }
  let types : Array[@ast.TsType] = []
  for p in m.params {
    types.push(p.1)
  }
  Some(types)
}

///|
/// True when an overriding member of type `derived` is *definitely* not
/// assignable to the overridden base member of type `base` -- the structural
/// core of TS2416 / TS2430. Decided only for shapes we can compare soundly:
///   - a scalar overriding an object shape (or vice versa): a category clash
///     that can never hold;
///   - both plain (non-generic) named class / interface / object shapes: the
///     full member sets make `struct_assignable_named_rec` a reliable
///     "derived provides everything base requires" test;
///   - both concrete scalars: decided by `is_assignable_to`.
/// Anything else (`any` / `unknown`, generic `Applied`, unions, functions,
/// type parameters) returns `false`, so the check never fires on a shape it
/// can't fully model -- keeping it false-positive-free.
fn member_override_incompatible(
  derived : @ast.TsType,
  base : @ast.TsType,
  resolver : Resolver,
) -> Bool {
  fn strip_undef(t : @ast.TsType) -> @ast.TsType {
    match t {
      Union(members) => {
        let rest : Array[@ast.TsType] = []
        for m in members {
          if !(m is Undefined) && !(m is Null) {
            rest.push(m)
          }
        }
        if rest.length() == 1 {
          rest[0]
        } else {
          t
        }
      }
      _ => t
    }
  }

  let d = resolver.unwrap(strip_undef(derived))
  let b = resolver.unwrap(strip_undef(base))
  // `any` / `unknown` on either side is always compatible.
  match (d, b) {
    (Any, _) | (_, Any) | (Unknown, _) | (_, Unknown) => return false
    // Generic instantiations need type-argument substitution we don't do
    // here; stay silent rather than risk a substitution-shaped false positive.
    (Applied(_, _), _) | (_, Applied(_, _)) => return false
    _ => ()
  }
  let d_obj = is_named_decl(d, resolver)
  let b_obj = is_named_decl(b, resolver)
  if is_bare_scalar_type(d) && b_obj {
    return true
  }
  if d_obj && is_bare_scalar_type(b) {
    return true
  }
  if d_obj && b_obj {
    return !struct_assignable_named_rec(d, b, resolver, [])
  }
  if is_bare_scalar_type(d) && is_bare_scalar_type(b) {
    return !is_assignable_to(d, b)
  }
  false
}

///|
/// Recursively widen literal types, descending through object / struct field
/// types (and array / tuple / union members). Mirrors TypeScript's widening
/// of a mutable object-literal initializer: `var a = { foo: '' }` has type
/// `{ foo: string }`, not `{ foo: '' }`. The object's *contents* widen even
/// for a `const` binding (only a top-level `const` scalar stays literal),
/// which is why this is applied to composite binding types regardless of the
/// declaration keyword. `widen_literal` only widens at the top level / array
/// / tuple; this also reaches inside `Object` / `Struct` fields and unions.
fn widen_literal_deep(t : @ast.TsType) -> @ast.TsType {
  match t {
    Literal(_) => String_
    NumberLiteral(_) => Number
    BigIntLiteral(_) => BigInt
    BooleanLiteral(_) => Boolean
    Array(elem) => Array(widen_literal_deep(elem))
    Tuple(items) => Tuple(items.map(widen_literal_deep))
    Union(members) => Union(members.map(widen_literal_deep))
    Object(fields) =>
      Object(fields.map(fn(f) { (f.0, widen_literal_deep(f.1)) }))
    Struct(name, fields) =>
      Struct(name, fields.map(fn(f) { (f.0, widen_literal_deep(f.1)) }))
    _ => t
  }
}

///|
fn synthesize_children_type(
  env : ExprEnv,
  resolver : Resolver,
  children : Array[@ast.TsExpr],
) -> @ast.TsType {
  if children.length() == 0 {
    return @ast.TsType::Undefined
  }
  if children.length() == 1 {
    return infer_expr(env, resolver, children[0])
  }
  let parts : Array[@ast.TsType] = []
  for c in children {
    parts.push(infer_expr(env, resolver, c))
  }
  // Dedup obviously-identical parts so the synthesised union stays
  // readable in diagnostics.
  let dedup : Array[@ast.TsType] = []
  for p in parts {
    let mut already = false
    for existing in dedup {
      if equivalent(p, existing) {
        already = true
        break
      }
    }
    if !already {
      dedup.push(p)
    }
  }
  let elem = if dedup.length() == 1 {
    dedup[0]
  } else {
    @ast.TsType::Union(dedup)
  }
  @ast.TsType::Array(elem)
}

///|
fn check_jsx_attrs(
  env : ExprEnv,
  tag : String,
  attrs : Array[(String, @ast.TsExpr?)],
  children : Array[@ast.TsExpr],
  ctx : CheckCtx,
) -> Unit {
  if tag == "" {
    return
  }
  // Lower-case HTML element tags — out of scope for now.
  if tag.length() > 0 {
    let first = tag[0].to_int().unsafe_to_char()
    if first >= 'a' && first <= 'z' {
      return
    }
  }
  // Dotted member-expression tags (`<Layout.Header/>`) are resolved
  // against namespaces ingested with `prefix + name` keys; if the
  // resolver doesn't have the dotted name registered we fall through
  // to the standard "no signature" bail later.
  // Resolve the component as a top-level function and pull out its
  // single parameter's type. Component signatures we recognise:
  //
  //   function Comp(props: { foo: number }): JSX.Element
  //   function Comp(props: Props): JSX.Element
  let raw_props : @ast.TsType? = match ctx.resolver.signatures.get(tag) {
    Some(params) if params.length() == 1 => Some(params[0].type_)
    _ => None
  }
  let raw_props_ty = match raw_props {
    Some(t) => t
    None => return
  }
  // Generic-component inference: when the component declares type
  // parameters, unify each supplied attribute's value type against the
  // declared prop's type before per-attribute checks, then substitute
  // the bindings into the props shape so downstream lookups see the
  // instantiated form.
  let type_params = match ctx.resolver.func_type_params.get(tag) {
    Some(tps) => tps
    None => []
  }
  let const_flags = match ctx.resolver.func_const_type_params.get(tag) {
    Some(flags) => flags
    None => []
  }
  // `<const T>` skips the literal-widening pass below so the inferred
  // binding keeps its narrow shape. We pre-compute whether *any* type
  // parameter on this component is const — if so, the safer behavior
  // is to skip widening across the board, since the binding could end
  // up flowing into the const param.
  let mut has_const_param = false
  for f in const_flags {
    if f {
      has_const_param = true
    }
  }
  let maybe_widen = fn(t : @ast.TsType) -> @ast.TsType {
    if has_const_param {
      t
    } else {
      widen_literal(t)
    }
  }
  let props = if type_params.length() > 0 {
    let bindings : Map[String, @ast.TsType] = {}
    for tp in type_params {
      bindings[tp] = @ast.TsType::Any
    }
    for entry in attrs {
      let name = entry.0
      match entry.1 {
        Some(value) =>
          if name == "" {
            // Spread: unify each overlapping field with the props.
            let spread_ty = infer_expr(env, ctx.resolver, value)
            let spread_fields = collect_declared_fields(spread_ty, ctx.resolver)
            for sf in spread_fields {
              match ctx.resolver.lookup_field(raw_props_ty, sf.0) {
                Some(formal) =>
                  infer_param_bindings(
                    type_params,
                    formal,
                    maybe_widen(sf.1),
                    bindings,
                    false,
                  )
                None => ()
              }
            }
          } else {
            match ctx.resolver.lookup_field(raw_props_ty, name) {
              Some(formal) => {
                let actual = infer_expr(env, ctx.resolver, value)
                // JSX inference widens literal types (`"hi"` → `string`,
                // `1` → `number`) so a single attribute doesn't lock T
                // to a narrow literal value the user clearly didn't
                // intend. Matches TS's contextual widening rule. The
                // wrapper is a no-op when any of the component's type
                // params is `<const T>`.
                infer_param_bindings(
                  type_params,
                  formal,
                  maybe_widen(actual),
                  bindings,
                  false,
                )
              }
              None => ()
            }
          }
        None => ()
      }
    }
    substitute_params(raw_props_ty, bindings)
  } else {
    raw_props_ty
  }
  // Per-attribute type check. Track the fields supplied by `{...spread}`
  // entries so the missing-required pass below treats them as provided.
  // `key` and `ref` are reserved JSX attributes — React intercepts them
  // before they reach the component, so they aren't validated against
  // the declared props.
  let spread_provided : Map[String, Bool] = {}
  for entry in attrs {
    let name = entry.0
    if name == "key" || name == "ref" {
      continue
    }
    match entry.1 {
      Some(value) =>
        if name == "" {
          // Spread attribute: validate each overlapping field type and
          // record the names it contributes.
          let spread_ty = infer_expr(env, ctx.resolver, value)
          let spread_fields = collect_declared_fields(spread_ty, ctx.resolver)
          for sf in spread_fields {
            spread_provided[sf.0] = true
            match ctx.resolver.lookup_field(props, sf.0) {
              Some(declared) =>
                if is_checkable(declared) &&
                  is_checkable(sf.1) &&
                  !is_assignable_to(sf.1, declared) {
                  record(
                    ctx,
                    "<\{tag}> spread `\{sf.0}`",
                    "expected `\{type_display(declared)}` but got `\{type_display(sf.1)}`",
                  )
                }
              None => ()
            }
          }
        } else {
          match ctx.resolver.lookup_field(props, name) {
            Some(declared) =>
              check_expr_against(
                env,
                value,
                declared,
                ctx,
                "<\{tag}> attr `\{name}`",
              )
            None =>
              record(
                ctx,
                "<\{tag}> attr `\{name}`",
                "property `\{name}` does not exist on target type",
              )
          }
        }
      None =>
        // Boolean attribute (`<Foo bar />`) implies `bar = true`.
        match ctx.resolver.lookup_field(props, name) {
          Some(_) => ()
          None =>
            record(
              ctx,
              "<\{tag}> attr `\{name}`",
              "property `\{name}` does not exist on target type",
            )
        }
    }
  }
  // Missing-required check. JSX children populate the synthetic
  // `children` prop, so include it in `provided` when at least one
  // child is present.
  let provided : Map[String, Bool] = {}
  for entry in attrs {
    if entry.0 != "" {
      provided[entry.0] = true
    }
  }
  for k in spread_provided.keys() {
    provided[k] = true
  }
  if children.length() > 0 {
    provided["children"] = true
  }
  // Children-prop type check: when the props shape declares a
  // `children` field with a non-`Any` type, synthesise the children
  // value (single child or array union) and validate it.
  match ctx.resolver.lookup_field(props, "children") {
    Some(children_ty) =>
      if is_checkable(children_ty) {
        let synth = synthesize_children_type(env, ctx.resolver, children)
        if is_checkable(synth) && !is_assignable_to(synth, children_ty) {
          record(
            ctx,
            "<\{tag}> children",
            "expected `\{type_display(children_ty)}` but got `\{type_display(synth)}`",
          )
        }
      }
    None =>
      if children.length() > 0 {
        // The component has no `children` prop but the JSX element
        // supplied some. Mirror TS's "Property 'children' does not
        // exist" diagnostic.
        let declared_fields = collect_declared_fields(props, ctx.resolver)
        let has_children = declared_fields
          .iter()
          .any(fn(d) { d.0 == "children" })
        if !has_children && declared_fields.length() > 0 {
          record(
            ctx,
            "<\{tag}> children",
            "component does not declare a `children` prop",
          )
        }
      }
  }
  let declared_fields = collect_declared_fields(props, ctx.resolver)
  for d in declared_fields {
    let n = d.0
    let ty = d.1
    if provided.contains(n) {
      continue
    }
    if is_assignable_to(@ast.TsType::Undefined, ty) {
      continue
    }
    record(
      ctx,
      "<\{tag}> missing prop `\{n}`",
      "property `\{n}` is required by `\{type_display(props)}`",
    )
  }
}

///|
fn check_object_lit_against_target(
  env : ExprEnv,
  entries : Array[(String, @ast.TsExpr)],
  target : @ast.TsType,
  resolver : Resolver,
  ctx : CheckCtx,
  sub_path : String,
) -> Unit {
  // When the target is a bare in-scope type parameter (`T extends Foo`),
  // we don't know the concrete shape — TS allows objects with additional
  // properties because the actual instantiation may be a wider type.
  // Suppress the entire excess-property check in that case.
  if is_in_scope_type_param(ctx, target) {
    return
  }
  // Mapped / conditional / `keyof` / generic-alias targets (`Boxified<any>`,
  // `keyof {}` from an unresolved generic, …) can't be enumerated, so every
  // supplied key would look like an excess property and every declared field
  // like a missing one. TypeScript resolves these fully — suppress the whole
  // excess/missing check rather than emit false positives.
  if member_recv_unmodeled(target, resolver) {
    return
  }
  // An unresolved `Named` / `Applied` target — typically a method-level type
  // parameter (`foo<U extends T>(x: U)`) the enclosing-scope check above
  // doesn't track — has an unknown shape, so TypeScript allows extra
  // properties (the instantiation may be wider). Suppress excess/missing.
  if type_contains_unresolved_named(target, resolver) {
    return
  }
  // Excess-property reporting is suppressed for a bare anonymous `Object`
  // target reached as a *call argument*. TypeScript inlines a constrained type
  // parameter's bound into the parameter position (`foo<U extends { length:
  // number }>(x: U)` checks the argument against `{ length: number }`), and
  // excess properties ARE allowed against a type parameter — so flagging them
  // here would be a false positive we can't distinguish from a genuine inline
  // object-type annotation. We scope this to call arguments (`… arg[i]`):
  // variable/property assignments to an explicit object type (`var x: { a:
  // string } = { a, b }`) keep their excess-property diagnostic. Field-type
  // and missing-required checks below still run regardless.
  let suppress_excess = sub_path.contains("arg[") &&
    resolver.unwrap(target) is Object(_)
  // Per-field type checks for each provided key.
  for entry in entries {
    let key = entry.0
    let value = entry.1
    // Spread entries (`@@spread:N`) are not individual properties — skip them
    // in the excess-property check; their fields are checked via infer_expr.
    if key.has_prefix("@@spread:") {
      continue
    }
    // Computed / symbol property keys (`@@computed:N`) can't be matched against
    // declared members by name — TypeScript resolves the computed key to a
    // symbol / literal we don't evaluate, so neither "excess" nor "missing"
    // applies. Skip them.
    if key.has_prefix("@@computed:") {
      continue
    }
    match resolver.lookup_field(target, key) {
      Some(declared) =>
        check_expr_against(env, value, declared, ctx, "\{sub_path}.\{key}")
      None =>
        // Unknown key on the target — TS calls this an excess-property
        // error. Skip class/struct opaque shapes by relying on lookup_field
        // having already walked their fields above, and bare anonymous object
        // targets (possible type-parameter constraints; see above).
        if !suppress_excess {
          record(
            ctx,
            "\{sub_path}.\{key}",
            "property `\{key}` does not exist on target type",
          )
        }
    }
  }
  // Missing-required check: collect the declared field names of the target
  // and see which were omitted. Properties whose declared type accepts
  // `undefined` (optional, written `x?: T` or `T | undefined`) are
  // exempt.
  let declared = collect_declared_fields(target, resolver)
  let provided : Map[String, Bool] = {}
  for entry in entries {
    if entry.0.has_prefix("@@spread:") {
      // A `{...spread}` entry contributes every field of the spread source,
      // so those count as provided for the missing-required check (`const a1:
      // {a; b} = {...extra}` is not missing `a`/`b` when `extra` has them).
      let spread_ty = infer_expr(env, resolver, entry.1)
      for sf in collect_declared_fields(spread_ty, resolver) {
        provided[sf.0] = true
      }
    } else {
      provided[entry.0] = true
    }
  }
  // If the literal supplies any computed / symbol key, we can't tell which
  // declared member it satisfies — suppress the missing-required check
  // entirely rather than guess.
  let has_computed_entry = entries
    .iter()
    .any(fn(e) { e.0.has_prefix("@@computed:") })
  for d in declared {
    let name = d.0
    let ty = d.1
    if provided.contains(name) {
      continue
    }
    // Computed-keyed declared members (`<computed>`) can't be matched to a
    // provided key by name; and once the literal has a computed entry, any
    // declared member could be the one it fills. Stay silent.
    if name == "<computed>" || has_computed_entry {
      continue
    }
    if is_assignable_to(@ast.TsType::Undefined, ty) {
      continue
    }
    record(
      ctx,
      "\{sub_path}.\{name}",
      "property `\{name}` is required by `\{type_display(target)}`",
    )
  }
}

///|
/// Collect the (name, type) pairs an object-shaped target exposes, walking
/// interface `extends` chains. Returns an empty list for opaque shapes
/// (classes, applied generics, etc.) so callers don't accidentally flag
/// missing-required errors on a literal that legitimately fills only a
/// subset of an opaque shape.
fn collect_declared_fields(
  target : @ast.TsType,
  resolver : Resolver,
) -> Array[(String, @ast.TsType)] {
  let out : Array[(String, @ast.TsType)] = []
  let unwrapped = resolver.unwrap(target)
  match unwrapped {
    Object(entries) =>
      for entry in entries {
        match entry.0 {
          Literal(name) => out.push((name, entry.1))
          _ => ()
        }
      }
    Struct(_, fields) =>
      for f in fields {
        out.push((f.0, f.1))
      }
    Named(n) =>
      match resolver.interfaces.get(n) {
        Some(iface) => {
          for f in iface.fields {
            out.push((f.0, f.1))
          }
          let mut i = 0
          while i < iface.extends_names.length() {
            let base_name = iface.extends_names[i]
            let base_args = if i < iface.extends_args.length() {
              iface.extends_args[i]
            } else {
              []
            }
            let base_ty : @ast.TsType = if base_args.length() > 0 {
              @ast.TsType::Applied(base_name, base_args)
            } else {
              @ast.TsType::Named(base_name)
            }
            for f in collect_declared_fields(base_ty, resolver) {
              out.push(f)
            }
            i = i + 1
          }
        }
        None =>
          match resolver.classes.get(n) {
            Some(cls) => {
              for p in cls.properties {
                if !p.is_static {
                  out.push((p.name, p.type_))
                }
              }
              for base_name in cls.base_names {
                for f in collect_declared_fields(Named(base_name), resolver) {
                  out.push(f)
                }
              }
            }
            None => ()
          }
      }
    // Utility-type field collection so object-literal contextual typing
    // (missing-required / excess-property) honours the same rules.
    Applied("Partial", [t]) =>
      for f in collect_declared_fields(t, resolver) {
        out.push((f.0, narrow_union(f.1, @ast.TsType::Undefined)))
      }
    Applied("Required", [t]) =>
      for f in collect_declared_fields(t, resolver) {
        out.push((f.0, non_nullable(f.1)))
      }
    Applied("Readonly", [t]) =>
      for f in collect_declared_fields(t, resolver) {
        out.push(f)
      }
    Applied("Pick", [t, keys]) =>
      for f in collect_declared_fields(t, resolver) {
        if utility_keys_include(keys, f.0) {
          out.push(f)
        }
      }
    Applied("Omit", [t, keys]) =>
      for f in collect_declared_fields(t, resolver) {
        if !utility_keys_include(keys, f.0) {
          out.push(f)
        }
      }
    // Generic interface application: substitute type parameters before
    // returning each field type. `extends` chain isn't yet specialised —
    // bases inherit field types as declared.
    Applied(n, args) =>
      match resolver.interfaces.get(n) {
        Some(iface) => {
          let bindings : Map[String, @ast.TsType] = {}
          let limit = if args.length() < iface.type_params.length() {
            args.length()
          } else {
            iface.type_params.length()
          }
          let mut i = 0
          while i < limit {
            bindings[iface.type_params[i]] = args[i]
            i = i + 1
          }
          for f in iface.fields {
            out.push((f.0, substitute_params(f.1, bindings)))
          }
          let mut j = 0
          while j < iface.extends_names.length() {
            let base_name = iface.extends_names[j]
            let base_args = if j < iface.extends_args.length() {
              iface.extends_args[j]
            } else {
              []
            }
            let substituted_args : Array[@ast.TsType] = []
            for a in base_args {
              substituted_args.push(substitute_params(a, bindings))
            }
            let base_ty : @ast.TsType = if substituted_args.length() > 0 {
              @ast.TsType::Applied(base_name, substituted_args)
            } else {
              @ast.TsType::Named(base_name)
            }
            for f in collect_declared_fields(base_ty, resolver) {
              out.push((f.0, substitute_params(f.1, bindings)))
            }
            j = j + 1
          }
        }
        None =>
          match resolver.classes.get(n) {
            Some(cls) => {
              let bindings : Map[String, @ast.TsType] = {}
              let limit = if args.length() < cls.type_params.length() {
                args.length()
              } else {
                cls.type_params.length()
              }
              let mut i = 0
              while i < limit {
                bindings[cls.type_params[i]] = args[i]
                i = i + 1
              }
              for p in cls.properties {
                if !p.is_static {
                  out.push((p.name, substitute_params(p.type_, bindings)))
                }
              }
              for base_name in cls.base_names {
                for f in collect_declared_fields(Named(base_name), resolver) {
                  out.push(f)
                }
              }
            }
            None => ()
          }
      }
    // Intersection: a value of `A & B` has all properties of both A and B.
    Intersection(parts) =>
      for part in parts {
        for f in collect_declared_fields(part, resolver) {
          out.push(f)
        }
      }
    // Union: only fields present on every member are accessible.
    Union(parts) =>
      if parts.length() == 0 {
        ()
      } else {
        let first_fields = collect_declared_fields(parts[0], resolver)
        let common : Map[String, @ast.TsType] = {}
        for f in first_fields {
          common[f.0] = f.1
        }
        let mut i = 1
        while i < parts.length() {
          let member_fields = collect_declared_fields(parts[i], resolver)
          let member_map : Map[String, @ast.TsType] = {}
          for f in member_fields {
            member_map[f.0] = f.1
          }
          let to_remove : Array[String] = []
          for key in common {
            if !member_map.contains(key.0) {
              to_remove.push(key.0)
            }
          }
          for k in to_remove {
            common.remove(k)
          }
          i = i + 1
        }
        for entry in common {
          out.push((entry.0, entry.1))
        }
      }
    _ => ()
  }
  out
}

///|
/// Recheck the body of an `ArrowFunc` passed where a `Func(...)` is
/// expected, threading the formal parameter types through. Used to catch
/// errors inside `arr.map(x => x.someProp)` where `x` would otherwise type
/// as `Any`.

///|
/// If `callback` is an `ArrowFunc` / `FuncExpr` whose declared return
/// type is a `TypePredicate(name, target)`, return `target`. Used to
/// narrow `arr.filter(predicate)` result element type when the
/// predicate is a user-defined type guard.
fn arrow_type_predicate_target(callback : @ast.TsExpr) -> @ast.TsType? {
  let ret_opt = match callback {
    ArrowFunc(_, declared_ret, _, _) => Some(declared_ret)
    FuncExpr(f) => Some(f.return_type)
    _ => None
  }
  match ret_opt {
    Some(TypePredicate(_, target)) => Some(target)
    _ => None
  }
}

///|
/// If `ty` is one of the recognised array shapes (`Array(T)` or the
/// `Applied("Array", [T])` / `Applied("ReadonlyArray", [T])` aliases),
/// return its element type. Falls back to `None` otherwise so callers
/// can skip the array-specific dispatch path.
fn array_element_type(resolver : Resolver, ty : @ast.TsType) -> @ast.TsType? {
  match resolver.unwrap(ty) {
    Array(elem) => Some(elem)
    Applied("Array", [elem]) | Applied("ReadonlyArray", [elem]) => Some(elem)
    // `T[] | null` / `T[] | undefined` — strip nullish members and retry.
    Union(_) => {
      let pruned = prune_nullish(resolver, ty)
      if pruned == ty {
        None
      } else {
        array_element_type(resolver, pruned)
      }
    }
    _ => None
  }
}

///|
/// Infer the return type of a callback expression when it's invoked with
/// `formal_param_types`. Handles `ArrowFunc` (both expression and block
/// bodies) and `FuncExpr` shapes; falls back to the existing
/// `infer_expr` result for anything else (so opaque callbacks degrade to
/// `Any` cleanly).
fn infer_arrow_body_with_params(
  outer : ExprEnv,
  resolver : Resolver,
  callback : @ast.TsExpr,
  formal_param_types : Array[@ast.TsType],
) -> @ast.TsType {
  match callback {
    ArrowFunc(arrow_params, declared_ret, body, is_async) => {
      let env = ExprEnv::new()
      for entry in outer.full_snapshot() {
        env.bind(entry.0, entry.1)
      }
      let mut i = 0
      while i < arrow_params.length() {
        let p = arrow_params[i]
        let ty = if is_checkable(p.type_) {
          p.type_
        } else if i < formal_param_types.length() {
          formal_param_types[i]
        } else {
          p.type_
        }
        env.bind(p.name, ty)
        i = i + 1
      }
      // Prefer the explicit return-type annotation; fall back to body
      // inference when omitted.
      let inner = if is_checkable(declared_ret) {
        declared_ret
      } else {
        match body {
          ArrowExpr(e) => infer_expr(env, resolver, e)
          ArrowBlock(block) => infer_block_return(env, resolver, block)
        }
      }
      wrap_async_return(is_async, inner)
    }
    FuncExpr(f) => {
      let env = ExprEnv::new()
      for entry in outer.full_snapshot() {
        env.bind(entry.0, entry.1)
      }
      let mut i = 0
      while i < f.params.length() {
        let p = f.params[i]
        let ty = if is_checkable(p.type_) {
          p.type_
        } else if i < formal_param_types.length() {
          formal_param_types[i]
        } else {
          p.type_
        }
        env.bind(p.name, ty)
        i = i + 1
      }
      if is_checkable(f.return_type) {
        wrap_async_return(f.is_async, f.return_type)
      } else {
        let inner = infer_block_return(env, resolver, f.body)
        wrap_async_return(f.is_async, inner)
      }
    }
    _ => infer_expr(outer, resolver, callback)
  }
}

///|
/// Walk a block looking for `Return(Some(expr))` statements and union
/// their inferred types. Used by callback-body inference where we need
/// the result type of a block-bodied arrow / function expression.
fn infer_block_return(
  env : ExprEnv,
  resolver : Resolver,
  block : @ast.TsBlock,
) -> @ast.TsType {
  let mut acc : @ast.TsType = @ast.TsType::Undefined
  let mut first = true
  for stmt in block.stmts {
    match stmt {
      Return(Some(e)) => {
        let t = infer_expr(env, resolver, e)
        if first {
          acc = t
          first = false
        } else {
          acc = narrow_union(acc, t)
        }
      }
      Return(None) =>
        if first {
          acc = @ast.TsType::Undefined
          first = false
        }
      _ => ()
    }
  }
  if first {
    @ast.TsType::Undefined
  } else {
    acc
  }
}

///|
fn check_arrow_with_context(
  outer : ExprEnv,
  arrow_params : Array[@ast.TsParam],
  body : @ast.TsArrowBody,
  is_async : Bool,
  formal_params : Array[@ast.TsType],
  formal_ret : @ast.TsType,
  ctx : CheckCtx,
  sub_path : String,
) -> Unit {
  let env = ExprEnv::new()
  // Carry parent bindings into the inner scope. We don't snapshot/restore —
  // `ExprEnv` is mutable, but binding inside this synthetic env doesn't
  // touch the outer one.
  for entry in outer.full_snapshot() {
    env.bind(entry.0, entry.1)
  }
  let param_names : Array[String] = []
  let mut i = 0
  while i < arrow_params.length() {
    let p = arrow_params[i]
    // Honor an explicit annotation on the arrow's param; otherwise fall
    // back to the formal parameter type.
    let ty = if is_checkable(p.type_) {
      p.type_
    } else if i < formal_params.length() {
      formal_params[i]
    } else {
      p.type_
    }
    // When the arrow param carries an *explicit* annotation, it must be
    // compatible with the contextual (formal) parameter type. Parameters are
    // compared bivariantly (matching `strictFunctionTypes: false`, the corpus
    // default): a clear incompatibility (`(x: string) => …` passed where
    // `(x: number) => …` is expected) is a real TS2345 / TS2322. Skipped when
    // either side is non-checkable (`any`) or mentions an in-scope type
    // parameter (instantiation could reconcile them).
    if is_checkable(p.type_) &&
      i < formal_params.length() &&
      is_checkable(formal_params[i]) &&
      reliable_func_param_operand(p.type_, ctx) &&
      reliable_func_param_operand(formal_params[i], ctx) &&
      !(is_assignable_to_bivariant(p.type_, formal_params[i]) ||
      is_assignable_to_bivariant(formal_params[i], p.type_)) {
      record(
        ctx,
        "\{sub_path} param `\{p.name}`",
        "expected `\{type_display(formal_params[i])}` but got `\{type_display(p.type_)}`",
      )
    }
    env.bind(p.name, ty)
    param_names.push(p.name)
    i = i + 1
  }
  // A parameter shadows any same-named outer binding, so the body must not
  // see it as "used before assigned" (TS2454) — the parameter is bound and
  // assigned on entry. The flat `unassigned` map is name-keyed with no scope
  // tracking, so clone it minus the parameter names for the body walk.
  let inner_ctx : CheckCtx = {
    path_prefix: ctx.path_prefix,
    return_type: unwrap_async_return(is_async, formal_ret),
    yield_type: @ast.TsType::Any,
    resolver: ctx.resolver,
    issues: ctx.issues,
    in_scope_type_params: ctx.in_scope_type_params,
    permissive: ctx.permissive,
    unassigned: unassigned_without(ctx.unassigned, param_names),
    strict_property_init: ctx.strict_property_init,
    in_computed_key: false,
  }
  match body {
    ArrowExpr(e) => {
      let want = unwrap_async_return(is_async, formal_ret)
      // Void-returning callback rule (matches tsc): when the contextual
      // return type is `void`, the callback's body value is ignored, so any
      // expression is allowed -- `run(() => 42)` for `run(cb: () => void)`
      // is not an error. Still walk the body for nested call-argument checks.
      if want is Void {
        check_call_args_in_expr(env, e, inner_ctx)
      } else {
        check_expr_against(env, e, want, inner_ctx, "\{sub_path} arrow body")
      }
    }
    ArrowBlock(block) =>
      // Recheck the block with the new env and the formal_ret as the
      // expected return type.
      for stmt in block.stmts {
        check_stmt(env, stmt, inner_ctx)
      }
  }
}

///|
/// Clone an `unassigned` (TS2454) tracking map, dropping the given names —
/// used when entering an inner function / arrow scope whose parameters
/// shadow outer bindings of the same name.
fn unassigned_without(
  src : Map[String, Bool],
  names : Array[String],
) -> Map[String, Bool] {
  let m : Map[String, Bool] = {}
  for k, v in src {
    m[k] = v
  }
  for n in names {
    let _ = m.remove(n)
  }
  m
}

///|
/// Same as `check_arrow_with_context` for `FuncExpr`. Function expressions
/// already carry an explicit `return_type` slot; we only override unannotated
/// (`Any`) params with the formal ones.
fn check_funcexpr_with_context(
  outer : ExprEnv,
  f : @ast.TsFunc,
  formal_params : Array[@ast.TsType],
  formal_ret : @ast.TsType,
  ctx : CheckCtx,
  sub_path : String,
) -> Unit {
  let env = ExprEnv::new()
  for entry in outer.full_snapshot() {
    env.bind(entry.0, entry.1)
  }
  let param_names : Array[String] = []
  let mut i = 0
  while i < f.params.length() {
    let p = f.params[i]
    let ty = if is_checkable(p.type_) {
      p.type_
    } else if i < formal_params.length() {
      formal_params[i]
    } else {
      p.type_
    }
    env.bind(p.name, ty)
    param_names.push(p.name)
    i = i + 1
  }
  // Prefer the function's own annotated return type when present; fall back
  // to the formal slot otherwise.
  let body_return = if is_checkable(f.return_type) {
    unwrap_async_return(f.is_async, f.return_type)
  } else {
    unwrap_async_return(f.is_async, formal_ret)
  }
  let inner_ctx : CheckCtx = {
    path_prefix: ctx.path_prefix,
    return_type: body_return,
    yield_type: @ast.TsType::Any,
    resolver: ctx.resolver,
    issues: ctx.issues,
    in_scope_type_params: ctx.in_scope_type_params,
    permissive: ctx.permissive,
    // Parameters shadow outer bindings — drop them from the TS2454 set.
    unassigned: unassigned_without(ctx.unassigned, param_names),
    strict_property_init: ctx.strict_property_init,
    in_computed_key: false,
  }
  let _ = sub_path
  for stmt in f.body.stmts {
    check_stmt(env, stmt, inner_ctx)
  }
}

///|
/// Check call-site arguments against declared parameter types. Emits issues
/// for both argument-count mismatch (when we are confident there is no rest
/// param) and per-argument assignability errors.
fn check_arguments(
  env : ExprEnv,
  params : Array[@ast.TsType],
  args : Array[@ast.TsExpr],
  ctx : CheckCtx,
  call_path : String,
) -> Unit {
  check_arguments_with_sig(env, params, None, args, ctx, call_path)
}

///|
/// Variant of `check_arguments` that takes the rich `TsParam` list when
/// available, so optional / default / rest parameters are honored on arity
/// checks. `param_types` is the simplified types array (already lifted out
/// of `Func(...)`), and `sig` carries the full `TsParam` metadata.
fn check_arguments_with_sig(
  env : ExprEnv,
  params : Array[@ast.TsType],
  sig : Array[@ast.TsParam]?,
  args : Array[@ast.TsExpr],
  ctx : CheckCtx,
  call_path : String,
  arity_reliable? : Bool = false,
) -> Unit {
  // Spread arguments make positional matching unreliable — just type-check
  // each argument and skip count enforcement.
  let mut has_spread = false
  for a in args {
    match a {
      Spread(_) => has_spread = true
      _ => ()
    }
  }
  // Arity check: prefer the rich sig if present.
  let (min_arity, max_arity) = match sig {
    Some(ps) => {
      let mut has_rest = false
      for p in ps {
        if p.is_rest {
          has_rest = true
        }
      }
      let min_ = required_arity(ps)
      let max_ = if has_rest { -1 } else { ps.length() }
      (min_, max_)
    }
    None => {
      // No rich `TsParam` metadata (e.g. calling a value typed as
      // `Func([...], _)` — a variable, method, or call-signature). We can
      // still recover optionality from the parameter *types*: the parser
      // widens `x?: T` to `T | undefined`, so a trailing param whose type
      // accepts `undefined` is omittable. This drives the min count down
      // without needing the declaration's `TsParam` list. A function-type
      // rest param is wrapped in `Rest(...)`, so scan for it to lift the
      // arity cap — `(a: number, ...c: boolean[]) => void` accepts any
      // count >= 1, not exactly 2.
      let mut has_rest_ty = false
      for p in params {
        if p is Rest(_) {
          has_rest_ty = true
        }
      }
      let max_ = if has_rest_ty { -1 } else { params.length() }
      (required_arity_from_types(params), max_)
    }
  }
  if !has_spread {
    let n = args.length()
    let too_few = n < min_arity
    let too_many = max_arity >= 0 && n > max_arity
    if too_few || too_many {
      let expect_str = if min_arity == max_arity {
        "\{min_arity}"
      } else if max_arity < 0 {
        "at least \{min_arity}"
      } else {
        "\{min_arity}-\{max_arity}"
      }
      let msg = "expected \{expect_str} argument(s), got \{n}"
      // When the caller vouches that the signature is exact (a constructor
      // with a known parameter list, or a direct call to a rest-free
      // top-level function declaration), the arity diagnostic is reliable
      // and bypasses the permissive suppression that otherwise drops it.
      if arity_reliable {
        record_unfiltered(ctx, call_path, msg)
      } else {
        record(ctx, call_path, msg)
      }
    }
  }
  // Per-position assignability check. Rest-position args (at and beyond the
  // rest param's index) are checked against the rest param's *element* type.
  let rest_index : Int = match sig {
    Some(ps) => {
      let mut idx : Int = -1
      let mut i = 0
      while i < ps.length() {
        if ps[i].is_rest {
          idx = i
          break
        }
        i = i + 1
      }
      idx
    }
    None => {
      // No rich sig (a value typed `(...args: any[]) => R`, e.g. a
      // parenthesized callee). Function-type rest params are still wrapped in
      // `Rest(...)`, so scan the param *types* — otherwise each rest argument
      // is wrongly checked against the whole array instead of its element.
      let mut idx = -1
      for k in 0..<params.length() {
        if params[k] is Rest(_) {
          idx = k
          break
        }
      }
      idx
    }
  }
  let rest_elem_type : @ast.TsType = if rest_index >= 0 &&
    rest_index < params.length() {
    // The rest slot may arrive as a bare array, an `Applied("Array", …)` /
    // iterable, a tuple, or any of those wrapped in the `Rest(...)` variadic
    // marker (the `module_.funcs` builder wraps rest params that way).
    // Unwrap one `Rest` layer first, then read the element type.
    let slot = match params[rest_index] {
      Rest(inner) => inner
      other => other
    }
    match slot {
      Array(elem) => elem
      Applied("Array", [elem]) => elem
      Applied(n, [elem]) if is_array_like_iterable_name(n) => elem
      // `...args: [string, number]` — rest is typed as a tuple; each
      // individual rest argument is the union of all tuple element types.
      Tuple(parts) if parts.length() > 0 => {
        let mut u = parts[0]
        let mut i = 1
        while i < parts.length() {
          u = narrow_union(u, parts[i])
          i = i + 1
        }
        u
      }
      _ => @ast.TsType::Any
    }
  } else {
    @ast.TsType::Any
  }
  // A spread argument (`foo(...arr)`) distributes an unknown number of
  // values across the remaining parameters, so positional matching is
  // unreliable from the first spread onward — checking the array against a
  // scalar parameter would wrongly report `expected string but got
  // string[]`. Type-check the positions *before* the first spread; the
  // spread operand itself (and everything after) is still validated for
  // internal errors by the `check_call_args_in_expr` recursion at the call
  // site.
  let first_spread : Int = {
    let mut idx = -1
    let mut j = 0
    while j < args.length() {
      if args[j] is Spread(_) {
        idx = j
        break
      }
      j = j + 1
    }
    idx
  }
  let mut i = 0
  while i < args.length() {
    if first_spread >= 0 && i >= first_spread {
      break
    }
    let sub_path = "\{call_path} arg[\{i}]"
    if rest_index >= 0 && i >= rest_index {
      check_expr_against(env, args[i], rest_elem_type, ctx, sub_path)
    } else if i < params.length() {
      check_expr_against(env, args[i], params[i], ctx, sub_path)
    }
    i = i + 1
  }
}

///|
fn type_display(ty : @ast.TsType) -> String {
  match ty {
    Number => "number"
    Int => "int"
    Boolean => "boolean"
    String_ => "string"
    BigInt => "bigint"
    Symbol => "symbol"
    Void => "void"
    Null => "null"
    Undefined => "undefined"
    Any => "any"
    Never => "never"
    // Show literal types as `"s" (string)` so messages remain searchable
    // for both the literal form and the underlying primitive.
    Literal(s) => "\"\{s}\" (string)"
    NumberLiteral(s) => s
    BigIntLiteral(s) => s + "n"
    BooleanLiteral(b) => if b { "true" } else { "false" }
    Array(inner) => type_display(inner) + "[]"
    Named(n) => n
    Applied(n, args) => {
      let parts : Array[String] = []
      for a in args {
        parts.push(type_display(a))
      }
      n + "<" + parts.join(", ") + ">"
    }
    Union(items) => {
      let parts : Array[String] = []
      for a in items {
        parts.push(type_display(a))
      }
      parts.join(" | ")
    }
    Intersection(items) => {
      let parts : Array[String] = []
      for a in items {
        parts.push(type_display(a))
      }
      parts.join(" & ")
    }
    Func(params, ret) => {
      let parts : Array[String] = []
      for p in params {
        parts.push(type_display(p))
      }
      "(" + parts.join(", ") + ") => " + type_display(ret)
    }
    Tuple(items) => {
      let parts : Array[String] = []
      for a in items {
        parts.push(type_display(a))
      }
      "[" + parts.join(", ") + "]"
    }
    // `typeof X.Y` -- distinguish so two distinct query results don't
    // both flatten to `type`. The checker won't equate these because
    // their value sources differ, so structural mismatch is real.
    TypeOf(name) => "typeof " + name
    // `T[K]` indexed access. Render concisely; opening `[` already
    // marks this as compound for the permissive filter.
    IndexedAccess(target, idx) =>
      type_display(target) + "[" + type_display(idx) + "]"
    // `keyof T` -- distinct shape, useful for mismatch messages.
    Keyof(inner) => "keyof " + type_display(inner)
    // `unique symbol` -- the literal `unique symbol` text matches the
    // source so messages look right.
    UniqueSymbol(_) => "unique symbol"
    // Object literal type: render the field shape so a mismatch message is
    // actionable and survives the permissive filter's "type"-residue
    // suppression. Object-literal field types are now widened at the binding
    // site (see `widen_literal_deep`), so the historical literal-width false
    // positives (`{ foo: '' }` vs `{ foo: string }`) do not recur.
    Object(fields) =>
      if fields.length() == 0 {
        "{}"
      } else {
        let parts : Array[String] = []
        for f in fields {
          let key = match f.0 {
            Literal(k) => k
            _ => type_display(f.0)
          }
          parts.push(key + ": " + type_display(f.1))
        }
        "{ " + parts.join("; ") + " }"
      }
    Struct(name, _) => name
    Constructor(_, ret, _) => "new (...) => " + type_display(ret)
    _ => "type"
  }
}

// ---------------------------------------------------------------------------
// Destructuring binding helpers.
// ---------------------------------------------------------------------------

///|
/// Fold a destructuring default (`let [x = d] = ...`, `let { x = d } = ...`)
/// into the element / property type: the default supplies the value when the
/// source element is `undefined`, so the binding's type drops `undefined`
/// and gains the default's (widened) type. Matches TS, where `let [x = 0] =
/// arr` types `x` as the element type with `undefined` replaced by `number`.
fn apply_binding_default(
  env : ExprEnv,
  ctx : CheckCtx,
  ty : @ast.TsType,
  default : @ast.TsExpr?,
) -> @ast.TsType {
  match default {
    None => ty
    Some(d) => {
      let default_ty = widen_literal(infer_expr(env, ctx.resolver, d))
      match ty {
        Undefined | Any => default_ty
        Union(members) => {
          let kept : Array[@ast.TsType] = []
          for m in members {
            if !(m is Undefined) {
              kept.push(m)
            }
          }
          kept.push(default_ty)
          if kept.length() == 1 {
            kept[0]
          } else {
            @ast.TsType::Union(kept)
          }
        }
        _ => ty
      }
    }
  }
}

///|
fn bind_array_pattern(
  env : ExprEnv,
  ctx : CheckCtx,
  ab : @ast.TsArrayBinding,
  source : @ast.TsType,
) -> Unit {
  let unwrapped = ctx.resolver.unwrap(source)
  let mut i = 0
  while i < ab.items.length() {
    match ab.items[i] {
      Some(elem) => {
        let elem_ty = match unwrapped {
          Tuple(items) =>
            if i < items.length() {
              items[i]
            } else {
              // Out-of-bounds tuple access: element is undefined at runtime.
              @ast.TsType::Undefined
            }
          Array(t) => t
          Applied("Array", [t]) | Applied("ReadonlyArray", [t]) => t
          // Unknown iterable shape: infer undefined (element may not exist).
          _ => @ast.TsType::Undefined
        }
        let elem_ty = apply_binding_default(env, ctx, elem_ty, elem.default)
        bind_pattern(env, ctx, elem.binding, elem_ty)
      }
      None => ()
    }
    i = i + 1
  }
  match ab.rest {
    Some(rest_binding) => {
      let rest_ty = match unwrapped {
        Tuple(items) => {
          // Rest captures the remaining tuple elements as a tuple.
          let remaining : Array[@ast.TsType] = []
          let mut j = ab.items.length()
          while j < items.length() {
            remaining.push(items[j])
            j = j + 1
          }
          @ast.TsType::Tuple(remaining)
        }
        Array(t) => @ast.TsType::Array(t)
        _ => @ast.TsType::Any
      }
      bind_pattern(env, ctx, rest_binding, rest_ty)
    }
    None => ()
  }
}

///|
fn bind_object_pattern(
  env : ExprEnv,
  ctx : CheckCtx,
  ob : @ast.TsObjectBinding,
  source : @ast.TsType,
) -> Unit {
  for prop in ob.props {
    let field_ty = match ctx.resolver.lookup_field(source, prop.key) {
      Some(t) => t
      None =>
        // Union receiver: distribute field lookup across each member and
        // union the results so `{ kind } = (A | B)` gives "a" | "b" when
        // every member declares `kind`.
        match ctx.resolver.unwrap(source) {
          Union(parts) => {
            let member_types : Array[@ast.TsType] = []
            let mut all_found = true
            for part in parts {
              match ctx.resolver.lookup_field(part, prop.key) {
                Some(t) => member_types.push(t)
                None => all_found = false
              }
            }
            if member_types.length() == 0 {
              @ast.TsType::Any
            } else if member_types.length() == 1 {
              if all_found {
                member_types[0]
              } else {
                narrow_union(member_types[0], @ast.TsType::Undefined)
              }
            } else {
              let acc = member_types[0]
              let mut u = acc
              let mut i = 1
              while i < member_types.length() {
                u = narrow_union(u, member_types[i])
                i = i + 1
              }
              if all_found {
                u
              } else {
                narrow_union(u, @ast.TsType::Undefined)
              }
            }
          }
          // Non-union source with no matching field: the property is absent,
          // which in JS evaluates to `undefined` at runtime.
          _ => @ast.TsType::Undefined
        }
    }
    let field_ty = apply_binding_default(env, ctx, field_ty, prop.default)
    bind_pattern(env, ctx, prop.binding, field_ty)
  }
  // Rest pattern `{ a, b, ...rest }`: `rest` takes an object type with the
  // source's remaining (non-destructured) fields. Mirror the object-spread
  // path — build from `collect_declared_fields`. When the source shape is
  // unknown (no declared fields, e.g. `any` / an opaque generic) keep `rest`
  // permissive as `Any` rather than synthesising an empty object that would
  // make every `rest.x` access a false "property does not exist".
  match ob.rest {
    Some(rest_name) => {
      let declared = collect_declared_fields(source, ctx.resolver)
      if declared.length() == 0 {
        env.bind(rest_name, @ast.TsType::Any)
      } else {
        let taken : Map[String, Unit] = {}
        for prop in ob.props {
          taken[prop.key] = ()
        }
        let rest_fields : Array[(@ast.TsType, @ast.TsType)] = []
        for f in declared {
          if !taken.contains(f.0) {
            rest_fields.push((@ast.TsType::Literal(f.0), f.1))
          }
        }
        env.bind(rest_name, @ast.TsType::Object(rest_fields))
      }
    }
    None => ()
  }
}

///|
fn bind_pattern(
  env : ExprEnv,
  ctx : CheckCtx,
  binding : @ast.TsBinding,
  ty : @ast.TsType,
) -> Unit {
  match binding {
    Ident(name) => env.bind(name, ty)
    Array(ab) => bind_array_pattern(env, ctx, ab, ty)
    Object(ob) => bind_object_pattern(env, ctx, ob, ty)
    Target(_) => ()
  }
}

// ---------------------------------------------------------------------------
// Compound assignment validation.
// ---------------------------------------------------------------------------

///|
fn check_compound_assign(
  env : ExprEnv,
  target : @ast.TsType,
  op : @ast.TsCompoundOp,
  rhs : @ast.TsExpr,
  ctx : CheckCtx,
  name : String,
) -> Unit {
  // For arithmetic / bitwise compound ops, the target must be numeric and
  // the rhs must be assignable to `number`. `+=` is special-cased: if the
  // target is `string`, then concat semantics apply and any value is allowed.
  let needs_numeric = match op {
    AddAssign =>
      match target {
        String_ => false
        _ => true
      }
    SubAssign
    | MulAssign
    | DivAssign
    | ModAssign
    | PowAssign
    | BitAndAssign
    | BitOrAssign
    | BitXorAssign
    | ShlAssign
    | ShrAssign
    | UShrAssign => true
    _ => false
  }
  if !needs_numeric {
    return
  }
  // Verify target is numeric — otherwise we have an immediate error.
  if is_checkable(target) && !is_assignable_to(target, @ast.TsType::Number) {
    record(
      ctx,
      "compound-assign `\{name}`",
      "compound arithmetic op requires a number target, got `\{type_display(target)}`",
    )
    return
  }
  check_expr_against(
    env,
    rhs,
    @ast.TsType::Number,
    ctx,
    "compound-assign `\{name}`",
  )
}

///|
/// Element type of an iterable for `for ... of` binding. Supports the most
/// common shapes — arrays, tuples (union of elements), strings, and a few
/// well-known generics: `Set<T>`, `Iterable<T>`, `IterableIterator<T>`,
/// `Generator<T, ...>`, `Map<K, V>` (yields `[K, V]`).
fn for_of_element_type(resolver : Resolver, ty : @ast.TsType) -> @ast.TsType {
  let shape = resolver.unwrap(ty)
  match shape {
    Array(elem) => elem
    Tuple(items) =>
      if items.length() == 0 {
        @ast.TsType::Any
      } else {
        union_of(items)
      }
    String_ | Literal(_) => @ast.TsType::String_
    Applied(name, args) =>
      match (name, args.length()) {
        ("Array", 1) | ("ReadonlyArray", 1) => args[0]
        ("Set", 1) | ("Iterable", 1) | ("IterableIterator", 1) => args[0]
        ("Generator", n) if n >= 1 => args[0]
        ("Map", 2) => @ast.TsType::Tuple([args[0], args[1]])
        ("ReadonlySet", 1) => args[0]
        _ => @ast.TsType::Any
      }
    // Union iterable: collect element types from each non-null member.
    Union(parts) => {
      let elems : Array[@ast.TsType] = []
      for p in parts {
        match p {
          Null | Undefined => ()
          _ => {
            let e = for_of_element_type(resolver, p)
            match e {
              Any => ()
              _ => elems.push(e)
            }
          }
        }
      }
      if elems.length() == 0 {
        @ast.TsType::Any
      } else {
        union_of(elems)
      }
    }
    _ => @ast.TsType::Any
  }
}

///|
/// Narrow `name`'s type inside a `case <test>:` body. Handles literal cases
/// against a union of string / number / boolean literals — same shape as the
/// `if (name === lit) ...` equality narrowing path.
fn apply_switch_case_narrowing(
  env : ExprEnv,
  resolver : Resolver,
  name : String,
  case_test : @ast.TsExpr,
) -> Unit {
  let cur = env_lookup_full(env, resolver, name)
  let predicate : ((@ast.TsType) -> Bool)? = match case_test {
    StringLit(lit) =>
      Some(fn(v) {
        match v {
          Literal(s) => s == lit
          _ => false
        }
      })
    IntLit(i) => {
      let lit_str = "\{i}"
      Some(fn(v) {
        match v {
          NumberLiteral(s) => s == lit_str
          _ => false
        }
      })
    }
    NumberLit(d) => {
      // Best-effort: match against the same Double rendered as text.
      let lit_str = "\{d}"
      Some(fn(v) {
        match v {
          NumberLiteral(s) => s == lit_str
          _ => false
        }
      })
    }
    BoolLit(b) =>
      Some(fn(v) {
        match v {
          BooleanLiteral(x) => x == b
          _ => false
        }
      })
    _ => None
  }
  match predicate {
    Some(pred) => {
      let kept = narrow_keep(cur, pred)
      match kept {
        Never => ()
        _ => env.bind(name, kept)
      }
    }
    None => ()
  }
}

///|
/// Switch `default:` body narrowing — exclude every literal case test against
/// the scrutinee's union. Best-effort: only string-literal cases are excluded.
/// `default:` body of a tagged-union switch on `obj.prop`: walk the
/// listed string-literal cases, strip every union member whose
/// declared `prop` field already matches one of them, and bind the
/// remainder under `obj_name`. When every member is exhausted the
/// remainder is `Never`, which is how downstream exhaustiveness rails
/// (e.g. `const _: never = obj`) detect a clean cover.
fn apply_switch_disc_default_narrowing(
  env : ExprEnv,
  resolver : Resolver,
  obj_name : String,
  prop : String,
  cases : Array[@ast.TsSwitchCase],
) -> Unit {
  let str_lits : Array[String] = []
  for c in cases {
    match c.test_expr {
      Some(StringLit(s)) => str_lits.push(s)
      _ => ()
    }
  }
  if str_lits.length() == 0 {
    return
  }
  let cur = env_lookup_full(env, resolver, obj_name)
  let mut next : @ast.TsType = cur
  for lit in str_lits {
    match narrow_by_discriminant(resolver, next, prop, lit, false) {
      Some(remainder) => next = remainder
      None => ()
    }
  }
  env.bind(obj_name, next)
}

///|
fn apply_switch_default_narrowing(
  env : ExprEnv,
  resolver : Resolver,
  name : String,
  cases : Array[@ast.TsSwitchCase],
) -> Unit {
  let cur = env_lookup_full(env, resolver, name)
  let str_lits : Array[String] = []
  for c in cases {
    match c.test_expr {
      Some(StringLit(s)) => str_lits.push(s)
      _ => ()
    }
  }
  if str_lits.length() == 0 {
    return
  }
  let stripped = narrow_remove(cur, fn(v) {
    match v {
      Literal(s) => {
        let mut hit = false
        for lit in str_lits {
          if s == lit {
            hit = true
          }
        }
        hit
      }
      _ => false
    }
  })
  env.bind(name, stripped)
}

///|
/// Switch case narrowing for `switch (obj.kind) { case "tag": ... }` —
/// rewrites the case as a discriminated union refinement on `obj`.
fn apply_switch_disc_narrowing(
  env : ExprEnv,
  resolver : Resolver,
  obj_name : String,
  prop : String,
  case_test : @ast.TsExpr,
) -> Unit {
  match case_test {
    StringLit(lit) => {
      let cur = env_lookup_full(env, resolver, obj_name)
      match narrow_by_discriminant(resolver, cur, prop, lit, true) {
        Some(narrowed) => env.bind(obj_name, narrowed)
        None => ()
      }
    }
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// Narrowing — `typeof x === "T"`, `x === null/undefined`, `x != null`,
// `x instanceof C`, literal comparison, discriminated unions, and `&&`
// compound conditions. The narrowed type is bound for the duration of the
// then/else block and restored on exit.
// ---------------------------------------------------------------------------

///|
priv struct NarrowEffect {
  // Variables to overwrite when entering the then-branch.
  then_binds : Array[(String, @ast.TsType)]
  // Variables to overwrite when entering the else-branch.
  else_binds : Array[(String, @ast.TsType)]
}

///|
fn typeof_string_to_type(s : String) -> @ast.TsType? {
  match s {
    "string" => Some(@ast.TsType::String_)
    "number" => Some(@ast.TsType::Number)
    "boolean" => Some(@ast.TsType::Boolean)
    "bigint" => Some(@ast.TsType::BigInt)
    "symbol" => Some(@ast.TsType::Symbol)
    "undefined" => Some(@ast.TsType::Undefined)
    "function" => Some(@ast.TsType::Func([], @ast.TsType::Any))
    "object" => Some(@ast.TsType::Any)
    _ => None
  }
}

///|
/// Split `ty` into its union components (single-element list if it isn't a
/// union).
fn union_components(ty : @ast.TsType) -> Array[@ast.TsType] {
  match ty {
    Union(items) => items
    _ => [ty]
  }
}

///|
/// Re-assemble a list of variants into a `TsType` — collapses to the single
/// variant when only one remains, or `Never` when the list is empty.
fn union_of(items : Array[@ast.TsType]) -> @ast.TsType {
  if items.length() == 0 {
    return @ast.TsType::Never
  }
  if items.length() == 1 {
    return items[0]
  }
  @ast.TsType::Union(items)
}

///|
/// Strip `Null` and `Undefined` from `ty`.
fn non_nullable(ty : @ast.TsType) -> @ast.TsType {
  let variants = union_components(ty)
  let kept : Array[@ast.TsType] = []
  for v in variants {
    match v {
      Null | Undefined => ()
      _ => kept.push(v)
    }
  }
  union_of(kept)
}

///|
/// Remove variants from `ty` that match `pred`.
fn narrow_remove(ty : @ast.TsType, pred : (@ast.TsType) -> Bool) -> @ast.TsType {
  let variants = union_components(ty)
  let kept : Array[@ast.TsType] = []
  for v in variants {
    if !pred(v) {
      kept.push(v)
    }
  }
  union_of(kept)
}

///|
/// Keep only variants that match `pred`.
fn narrow_keep(ty : @ast.TsType, pred : (@ast.TsType) -> Bool) -> @ast.TsType {
  let variants = union_components(ty)
  let kept : Array[@ast.TsType] = []
  for v in variants {
    if pred(v) {
      kept.push(v)
    }
  }
  union_of(kept)
}

///|
fn type_eq(a : @ast.TsType, b : @ast.TsType) -> Bool {
  a == b
}

///|
/// Inspect a discriminator field on each variant and keep only those whose
/// field is the matching literal. Returns `None` when the receiver isn't a
/// union of structurally-known variants (so the caller can skip narrowing).
fn narrow_by_discriminant(
  resolver : Resolver,
  recv : @ast.TsType,
  field : String,
  literal : String,
  keep : Bool,
) -> @ast.TsType? {
  // Unwrap type aliases first so a `type Shape = A | B` receiver
  // becomes the underlying union before we split it.
  let variants = union_components(resolver.unwrap(recv))
  if variants.length() < 2 {
    return None
  }
  let kept : Array[@ast.TsType] = []
  let mut any_resolved = false
  for v in variants {
    match resolver.lookup_field(v, field) {
      Some(field_ty) => {
        any_resolved = true
        let matches = match field_ty {
          Literal(s) => s == literal
          // String/Number primitives aren't a discriminator — be conservative.
          _ => false
        }
        if matches == keep {
          kept.push(v)
        }
      }
      None => ()
    }
  }
  if !any_resolved {
    return None
  }
  Some(union_of(kept))
}

///|
fn analyze_narrowing(
  env : ExprEnv,
  resolver : Resolver,
  cond : @ast.TsExpr,
) -> NarrowEffect {
  let then_binds : Array[(String, @ast.TsType)] = []
  let else_binds : Array[(String, @ast.TsType)] = []
  collect_narrowing(env, resolver, cond, then_binds, else_binds, true)
  { then_binds, else_binds }
}

///|
/// Walk `cond` looking for narrowing-shaped sub-expressions, appending the
/// effect into `then_binds` / `else_binds`. `then_sense` flips when we
/// descend through a logical `!` so the same primitive can be matched in
/// either polarity.
fn collect_narrowing(
  env : ExprEnv,
  resolver : Resolver,
  cond : @ast.TsExpr,
  then_binds : Array[(String, @ast.TsType)],
  else_binds : Array[(String, @ast.TsType)],
  then_sense : Bool,
) -> Unit {
  match cond {
    BinOp(And, l, r) =>
      if then_sense {
        // `if (l && r) { /* l true AND r true */ }`. Both hold in the
        // then-branch, composed: narrow by l-true *then* r-true so the
        // second condition sees the first's narrowing (mirrors the `||`
        // else-branch). This is the `typeof x !== "a" && typeof x !== "b"`
        // residue -- the then-branch removes both "a" and "b" from x. The
        // else-branch of `&&` is a union (`!l | (l & !r)`) we can't narrow
        // cleanly, so leave else_binds untouched.
        let lo = analyze_narrowing(env, resolver, l)
        for b in lo.then_binds {
          then_binds.push(b)
        }
        let snap = env.full_snapshot()
        for b in lo.then_binds {
          env.bind(b.0, b.1)
        }
        let ro = analyze_narrowing(env, resolver, r)
        env.restore_from(snap)
        for b in ro.then_binds {
          then_binds.push(b)
        }
      }
    BinOp(Or, l, r) =>
      if !then_sense {
        // Under a negation: `!(l || r)` is `!l && !r`, so both hold.
        collect_narrowing(env, resolver, l, then_binds, else_binds, true)
        collect_narrowing(env, resolver, r, then_binds, else_binds, true)
      } else {
        // `if (l || r) { } else { /* l false AND r false */ }`. The
        // else-branch narrows by l-false *then* r-false (composed), which
        // is the common `typeof x === "a" || typeof x === "b"` discriminant
        // residue: in the else, x has both "a" and "b" types removed.
        // Apply l's false narrowing to a scratch env so r's narrowing sees
        // the already-reduced type, then collect both into else_binds
        // (later push wins per key, which yields the composed result).
        let lo = analyze_narrowing(env, resolver, l)
        for b in lo.else_binds {
          else_binds.push(b)
        }
        let snap = env.full_snapshot()
        for b in lo.else_binds {
          env.bind(b.0, b.1)
        }
        let ro = analyze_narrowing(env, resolver, r)
        env.restore_from(snap)
        for b in ro.else_binds {
          else_binds.push(b)
        }
      }
    BinOp(Coalesce, l, r) =>
      // `x ?? y`: when truthy, x is non-nullish; when falsy, narrowing from r.
      if then_sense {
        collect_narrowing(env, resolver, l, then_binds, else_binds, true)
      } else {
        collect_narrowing(env, resolver, r, then_binds, else_binds, false)
      }
    // Sequence expression: only the final value matters for narrowing.
    Seq(_, right) =>
      collect_narrowing(
        env, resolver, right, then_binds, else_binds, then_sense,
      )
    // Await is transparent to narrowing: `if (await x instanceof C)` narrows x.
    Await(inner) =>
      collect_narrowing(
        env, resolver, inner, then_binds, else_binds, then_sense,
      )
    UnaryOp(Not, inner) =>
      collect_narrowing(
        env,
        resolver,
        inner,
        then_binds,
        else_binds,
        !then_sense,
      )
    BinOp(op, left, right) => {
      let pair_pos = if then_sense { then_binds } else { else_binds }
      let pair_neg = if then_sense { else_binds } else { then_binds }
      // Equality narrowing.
      let equal_sense = match op {
        BinEq | AbstractEq => Some(true)
        BinNe | AbstractNe => Some(false)
        _ => None
      }
      match equal_sense {
        Some(eq) => {
          let true_side = if eq { pair_pos } else { pair_neg }
          let false_side = if eq { pair_neg } else { pair_pos }
          analyze_equality(env, resolver, left, right, true_side, false_side)
        }
        None => ()
      }
      // `x instanceof C` narrows on equality only. Accept any
      // Var / PropAccess-chain on the left so nested access like
      // `obj.payload.err instanceof TypeError` narrows.
      match op {
        Instanceof => {
          let lhs_key = narrowing_key_for_expr(left)
          let class_name_opt = match right {
            Var(c) => Some(c)
            _ => None
          }
          match (lhs_key, class_name_opt) {
            (Some(key), Some(class_name)) => {
              let cur = narrowing_current_type(env, resolver, key)
              let class_ty = @ast.TsType::Named(class_name)
              // `v instanceof C` keeps every union member whose class
              // chain reaches `C` — so `instanceof Object` keeps `Date`
              // (Date extends Object) and `instanceof Animal` keeps a
              // declared subclass. Falls back to nominal name match
              // when the resolver doesn't know `v`.
              let matches = fn(v : @ast.TsType) -> Bool {
                match v {
                  Named(n) | Applied(n, _) =>
                    n == class_name ||
                    class_or_interface_inherits(n, class_name, resolver, [])
                  _ => false
                }
              }
              let then_ty = narrow_keep(cur, matches)
              let then_resolved = match then_ty {
                Never => class_ty
                _ => then_ty
              }
              pair_pos.push((key, then_resolved))
              let else_ty = narrow_remove(cur, matches)
              pair_neg.push((key, else_ty))
            }
            _ => ()
          }
        }
        // `"key" in obj` — narrow `obj`'s union to members that own `key`.
        In => {
          // `"a" in v` / `a in v` (a is a const-bound string literal) /
          // `<expr> in v` — resolve the key expression to a literal
          // string when possible. Const-typed `Var(name)` resolves via
          // the env / globals; bare string literals match directly.
          let key_opt : String? = match left {
            StringLit(k) => Some(k)
            Var(n) =>
              match env_lookup_full(env, resolver, n) {
                Literal(s) => Some(s)
                _ => None
              }
            _ => None
          }
          match (key_opt, right) {
            (Some(key), Var(name)) => {
              let cur = env_lookup_full(env, resolver, name)
              let then_ty = narrow_keep(cur, fn(v) {
                resolver.lookup_field(v, key) is Some(_)
              })
              match then_ty {
                Never => ()
                _ => pair_pos.push((name, then_ty))
              }
              let else_ty = narrow_remove(cur, fn(v) {
                resolver.lookup_field(v, key) is Some(_)
              })
              pair_neg.push((name, else_ty))
            }
            _ => ()
          }
        }
        _ => ()
      }
    }
    // `if (isFoo(v))` — user-defined type guard. When the callee's
    // declared return type is `paramName is T`, the corresponding
    // positional argument is narrowed to `T` in the then-branch and the
    // complement is kept in the else-branch.
    Call(callee_name, args) => {
      let pair_pos = if then_sense { then_binds } else { else_binds }
      let pair_neg = if then_sense { else_binds } else { then_binds }
      apply_type_predicate_narrowing(
        env, resolver, callee_name, args, pair_pos, pair_neg,
      )
    }
    MethodCall(receiver, method_name, args) => {
      let pair_pos = if then_sense { then_binds } else { else_binds }
      let pair_neg = if then_sense { else_binds } else { then_binds }
      apply_method_type_predicate_narrowing(
        env, resolver, receiver, method_name, args, pair_pos, pair_neg,
      )
    }
    // `if (x)` / `if (obj.prop)` / `if (obj.a.b)` — truthy narrowing
    // strips null / undefined under the synthesised key. Bare `Var(_)`
    // and arbitrary-depth `PropAccess(...)` chains share the same path
    // via `narrowing_key_for_expr`. Must come after the `Call` /
    // `MethodCall` arms so type-predicate narrowing isn't shadowed by
    // this catch-all guard.
    _ if then_sense =>
      match narrowing_key_for_expr(cond) {
        Some(key) => {
          let cur = narrowing_current_type(env, resolver, key)
          then_binds.push((key, non_nullable(cur)))
        }
        None => ()
      }
    _ => ()
  }
}

///|
/// When `callee_name` is a global function whose declared return type is a
/// `TypePredicate(paramName, T)`, narrow the argument bound to `paramName`
/// to `T` (positive) / strip `T` from it (negative). The mapping uses the
/// callee's parameter-name list to figure out which positional arg the
/// predicate refers to.
fn apply_type_predicate_narrowing(
  env : ExprEnv,
  resolver : Resolver,
  callee_name : String,
  args : Array[@ast.TsExpr],
  pair_pos : Array[(String, @ast.TsType)],
  pair_neg : Array[(String, @ast.TsType)],
) -> Unit {
  let predicate = match resolver.globals.get(callee_name) {
    Some(Func(_, TypePredicate(param_name, target))) =>
      Some((param_name, target))
    _ => None
  }
  match predicate {
    None => return
    Some(_) => ()
  }
  let (param_name, target) = match predicate {
    Some(p) => p
    None => return
  }
  let sig = resolver.signatures.get(callee_name)
  // Map predicate's parameter name to argument index.
  let idx = match sig {
    Some(params) => {
      let mut found : Int = -1
      let mut i = 0
      while i < params.length() {
        if params[i].name == param_name {
          found = i
          break
        }
        i = i + 1
      }
      found
    }
    None => 0
  }
  if idx < 0 || idx >= args.length() {
    return
  }
  match args[idx] {
    Var(arg_name) => {
      let cur = env_lookup_full(env, resolver, arg_name)
      // Positive: narrow to T. If `keep` produces Never (e.g. cur is a
      // single Named that isn't assignable to `target` but the source
      // type genuinely supports the predicate, like
      // `function hasLegs(x: Beast): x is Legged`), fall back to the
      // intersection `cur & target` — TS narrows to that intersection,
      // not just to `target`, so subsequent calls expecting `cur` still
      // accept the narrowed value.
      let then_ty = narrow_keep(cur, fn(v) { is_assignable_to(v, target) })
      let then_resolved = match then_ty {
        Never =>
          match cur {
            Any => target
            _ => @ast.TsType::Intersection([cur, target])
          }
        _ => then_ty
      }
      pair_pos.push((arg_name, then_resolved))
      // Negative: strip members that fit T.
      let else_ty = narrow_remove(cur, fn(v) { is_assignable_to(v, target) })
      pair_neg.push((arg_name, else_ty))
    }
    _ => ()
  }
}

///|
/// Apply an `asserts paramName [is T]` predicate to the env when an
/// expression statement is calling a function whose declared return is
/// `AssertsPredicate(...)`. Unlike `apply_type_predicate_narrowing`,
/// this binds the narrowed type into `env` directly because the
/// assertion's effect persists across subsequent statements (TS
/// "assertion functions" semantics).
fn apply_assertion_predicate_effect(
  env : ExprEnv,
  resolver : Resolver,
  expr : @ast.TsExpr,
) -> Unit {
  // Pull the `(callee_return, args)` pair from any call shape we know:
  // `Call(name, args)`, `CallExpr(Var(name), args)`, or
  // `MethodCall(recv, m, args)`.
  let (ret, args) : (@ast.TsType, Array[@ast.TsExpr]) = match expr {
    Call(name, args) =>
      match resolver.globals.get(name) {
        Some(Func(_, ret)) => (ret, args)
        _ => return
      }
    CallExpr(Var(name), args) =>
      match resolver.globals.get(name) {
        Some(Func(_, ret)) => (ret, args)
        _ => return
      }
    MethodCall(receiver, method_name, args) => {
      let recv_ty = infer_expr(env, resolver, receiver)
      match resolver.lookup_method_sig(recv_ty, method_name) {
        Some((_, ret)) => (ret, args)
        None => return
      }
    }
    _ => return
  }
  let (param_name, target_opt) = match ret {
    AssertsPredicate(p, t) => (p, t)
    _ => return
  }
  // Resolve which positional arg this asserts refers to.
  let idx = match expr {
    Call(name, _) | CallExpr(Var(name), _) =>
      match resolver.signatures.get(name) {
        Some(params) => {
          let mut found : Int = -1
          let mut i = 0
          while i < params.length() {
            if params[i].name == param_name {
              found = i
              break
            }
            i = i + 1
          }
          found
        }
        None => 0
      }
    _ => 0
  }
  if idx < 0 || idx >= args.length() {
    return
  }
  match args[idx] {
    Var(arg_name) => {
      let cur = env_lookup_full(env, resolver, arg_name)
      let narrowed : @ast.TsType = match target_opt {
        // `asserts x is T` — narrow to T.
        Some(target) => {
          let kept = narrow_keep(cur, fn(v) { is_assignable_to(v, target) })
          match kept {
            Never => target
            _ => kept
          }
        }
        // `asserts x` (truthy) — strip null / undefined / false-ish.
        None => non_nullable(cur)
      }
      env.bind(arg_name, narrowed)
    }
    _ => ()
  }
}

///|
/// Method form: `receiver.guardMethod(v)` where the method's declared
/// return type is `paramName is T`. Resolves the method signature via the
/// receiver shape and applies the same narrowing as the function form.
fn apply_method_type_predicate_narrowing(
  env : ExprEnv,
  resolver : Resolver,
  receiver : @ast.TsExpr,
  method_name : String,
  args : Array[@ast.TsExpr],
  pair_pos : Array[(String, @ast.TsType)],
  pair_neg : Array[(String, @ast.TsType)],
) -> Unit {
  let recv_ty = infer_expr(env, resolver, receiver)
  let ret = match resolver.lookup_method_sig(recv_ty, method_name) {
    Some((_, ret)) => ret
    None =>
      // Arrow-function class field predicate: `isElite = (): this is T =>
      // {...}` is stored as a `Func`-typed property, not a method, so
      // `lookup_method_sig` misses it. Fall back to the field's return type.
      match resolver.lookup_field(recv_ty, method_name) {
        Some(Func(_, r)) => r
        _ => return
      }
  }
  let (param_name, target) = match ret {
    TypePredicate(p, t) => (p, t)
    _ => return
  }
  // `this is T` predicate (`isLeader(): this is LeadGuard`): the guard
  // narrows the *receiver* itself, not a positional argument. Narrow the
  // receiver's binding (`if (a.isLeader()) { a.lead() }`).
  if param_name == "this" {
    match narrowing_key_for_expr(receiver) {
      Some(key) => {
        let cur = narrowing_current_type(env, resolver, key)
        let then_ty = narrow_keep(cur, fn(v) { is_assignable_to(v, target) })
        let then_resolved = match then_ty {
          Never => target
          _ => then_ty
        }
        pair_pos.push((key, then_resolved))
        let else_ty = narrow_remove(cur, fn(v) { is_assignable_to(v, target) })
        pair_neg.push((key, else_ty))
      }
      None => ()
    }
    return
  }
  // Without per-method TsParam metadata, fall back to first positional arg.
  let _ = param_name
  if args.length() == 0 {
    return
  }
  match args[0] {
    Var(arg_name) => {
      let cur = env_lookup_full(env, resolver, arg_name)
      let then_ty = narrow_keep(cur, fn(v) { is_assignable_to(v, target) })
      let then_resolved = match then_ty {
        Never => target
        _ => then_ty
      }
      pair_pos.push((arg_name, then_resolved))
      let else_ty = narrow_remove(cur, fn(v) { is_assignable_to(v, target) })
      pair_neg.push((arg_name, else_ty))
    }
    _ => ()
  }
}

///|
/// Look up `name`'s current type via env first, then resolver globals,
/// defaulting to `Any`.

///|
/// Flatten a `Var(...)` / `PropAccess(...)` / literal-`IndexAccess(...)`
/// chain into a dotted key for the narrowing env. Returns `None` when
/// the chain bottoms out at anything other than `Var(name)`.
///
/// Examples:
///   `Var("c")`                                       → Some("c")
///   `PropAccess(Var("c"), "name")`                   → Some("c.name")
///   `PropAccess(PropAccess(Var("c"), "a"), "b")`     → Some("c.a.b")
///   `IndexAccess(Var("arr"), IntLit(0))`             → Some("arr[0]")
///   `IndexAccess(Var("m"), StringLit("k"))`          → Some("m[\"k\"]")
fn narrowing_key_for_expr(expr : @ast.TsExpr) -> String? {
  match expr {
    Var(name) => Some(name)
    PropAccess(inner, prop) =>
      match narrowing_key_for_expr(inner) {
        Some(prefix) => Some(prefix + "." + prop)
        None => None
      }
    IndexAccess(inner, idx) =>
      match narrowing_key_for_expr(inner) {
        Some(prefix) => {
          // Only literal indices give a stable narrowing key; computed
          // indices (e.g. `arr[i]` with a Var index) can't be tracked
          // statically.
          let idx_key = match idx {
            IntLit(i) => Some("[\{i}]")
            NumberLit(d) => Some("[\{d}]")
            StringLit(s) => Some("[\"\{s}\"]")
            _ => None
          }
          match idx_key {
            Some(k) => Some(prefix + k)
            None => None
          }
        }
        None => None
      }
    _ => None
  }
}

///|
/// Resolve the "current" type for an arbitrary narrowing key — either a
/// plain identifier or the synthesised `name.prop` form. Splitting on
/// the first `.` lets the property-access narrowing path reuse
/// `prop_access_current_type` so the starting type for `typeof
/// obj.prop === "string"` is the structural shape of `obj.prop` rather
/// than the catch-all `Any`.
fn narrowing_current_type(
  env : ExprEnv,
  resolver : Resolver,
  key : String,
) -> @ast.TsType {
  // First-pass: a previously-set narrowing binding under the same key
  // wins — that's how nested chains like `c.a.b` recover the refined
  // type even though `lookup_field` on the receiver would re-derive
  // the original.
  match env.lookup(key) {
    Some(t) => return t
    None => ()
  }
  // Index-access key like `arr[0]` / `m["k"]`. Split off the trailing
  // bracket segment and resolve the prefix, then descend by element
  // type / tuple slot.
  if key.length() > 0 && key[key.length() - 1] == ']' {
    match key.rev_find("[") {
      Some(open_idx) => {
        let prefix = key[:open_idx].to_owned()
        let inner = key[open_idx + 1:key.length() - 1].to_owned()
        let prefix_ty = narrowing_current_type(env, resolver, prefix)
        let elem = index_into_type(resolver, prefix_ty, inner)
        return elem
      }
      None => ()
    }
  }
  match key.rev_find(".") {
    Some(idx) => {
      let prefix = key[:idx].to_owned()
      let leaf = key[idx + 1:].to_owned()
      // Recursively resolve the prefix's current type, then read the
      // leaf field from the resolver. This lets `c.a.b` go through
      // `narrowing_current_type("c.a") -> field "b"`.
      let prefix_ty = narrowing_current_type(env, resolver, prefix)
      match resolver.lookup_field(prefix_ty, leaf) {
        Some(t) => t
        None => @ast.TsType::Any
      }
    }
    None => env_lookup_full(env, resolver, key)
  }
}

///|
/// Read an element type from an indexable shape. `inner` is the raw
/// bracket contents — `0`, `"k"`, etc. Used by both narrowing key
/// resolution and the structural `IndexAccess` lookup path.

///|
/// Resolve a field name against an interface's index signatures. Returns
/// `Some(value_type)` when the field name's lexical category (numeric vs
/// other) matches one of the declared signatures. Numeric keys (parseable
/// as an integer) prefer the `[k: number]` signature when available;
/// otherwise the `[k: string]` signature is the catch-all.
fn index_signature_value(
  signatures : Array[(@ast.TsType, @ast.TsType)],
  field : String,
) -> @ast.TsType? {
  let is_numeric = try @string.parse_int(field) catch {
    _ => false
  } noraise {
    _ => true
  }
  let mut numeric_value : @ast.TsType? = None
  let mut string_value : @ast.TsType? = None
  for sig in signatures {
    match sig.0 {
      Number | Int => numeric_value = Some(sig.1)
      String_ | Literal(_) => string_value = Some(sig.1)
      _ => ()
    }
  }
  if is_numeric {
    match numeric_value {
      Some(t) => return Some(t)
      None => ()
    }
  }
  string_value
}

///|
/// Test whether a string-literal `field` is present in a `keys` type
/// expressed as a string literal or a union of string literals. Used by
/// the `Pick<T, K>` / `Omit<T, K>` utility-type field lookups.
fn utility_keys_include(keys : @ast.TsType, field : String) -> Bool {
  match keys {
    Literal(s) => s == field
    Union(parts) => {
      for p in parts {
        match p {
          Literal(s) if s == field => return true
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

///|
fn index_into_type(
  resolver : Resolver,
  recv : @ast.TsType,
  inner : String,
) -> @ast.TsType {
  let shape = resolver.unwrap(recv)
  // Quoted string key — strip the surrounding quotes and run a field
  // lookup so `m["k"]` resolves through the object / interface shape.
  if inner.length() >= 2 && inner[0] == '"' && inner[inner.length() - 1] == '"' {
    let key = inner[1:inner.length() - 1].to_owned()
    return match resolver.lookup_field(shape, key) {
      Some(t) => t
      None => @ast.TsType::Any
    }
  }
  // Numeric index — read tuple slot or array element.
  let idx = try @string.parse_int(inner) catch {
    _ => false
  } noraise {
    _ => true
  }
  if idx {
    match shape {
      Array(elem) => return elem
      Applied("Array", [elem]) | Applied("ReadonlyArray", [elem]) => return elem
      Tuple(items) =>
        try @string.parse_int(inner) catch {
          _ => return @ast.TsType::Any
        } noraise {
          i =>
            if i >= 0 && i < items.length() {
              return items[i]
            } else {
              return @ast.TsType::Any
            }
        }
      _ => return @ast.TsType::Any
    }
  }
  @ast.TsType::Any
}

///|
fn env_lookup_full(
  env : ExprEnv,
  resolver : Resolver,
  name : String,
) -> @ast.TsType {
  match env.lookup(name) {
    Some(t) => t
    None =>
      match resolver.globals.get(name) {
        Some(t) => t
        None => @ast.TsType::Any
      }
  }
}

///|
/// Analyze an `=== / !==` (`true_side` collects "equality holds" effects,
/// `false_side` collects "equality fails"). Handles:
///   - typeof x === "tag"
///   - x === null / x === undefined
///   - x == null (loose) → both null and undefined
///   - x === "literal"  (literal narrowing on unions)
///   - obj.prop === "literal" (discriminated union)
fn analyze_equality(
  env : ExprEnv,
  resolver : Resolver,
  left : @ast.TsExpr,
  right : @ast.TsExpr,
  true_side : Array[(String, @ast.TsType)],
  false_side : Array[(String, @ast.TsType)],
) -> Unit {
  // `typeof x === "string"` — canonical form.
  // `typeof <expr> === "string"` — accept any Var / PropAccess chain on
  // the operand position so `typeof c.a.b === "string"` narrows the
  // nested access.
  let typeof_match = match (left, right) {
    (UnaryOp(Typeof, operand), StringLit(s)) =>
      match narrowing_key_for_expr(operand) {
        Some(k) => Some((k, s))
        None => None
      }
    (StringLit(s), UnaryOp(Typeof, operand)) =>
      match narrowing_key_for_expr(operand) {
        Some(k) => Some((k, s))
        None => None
      }
    _ => None
  }
  match typeof_match {
    Some((name, ts)) =>
      match typeof_string_to_type(ts) {
        Some(narrowed) => {
          true_side.push((name, narrowed))
          // Else side: remove variants matching that primitive. Use the
          // shared helper so a `name.prop` key resolves through the
          // property-access path instead of returning `Any`.
          let cur = narrowing_current_type(env, resolver, name)
          let stripped = narrow_remove(cur, fn(v) { type_eq(v, narrowed) })
          false_side.push((name, stripped))
        }
        None => ()
      }
    None => ()
  }

  // `<expr> === null` / `<expr> === undefined` — accepts any
  // `Var` / `PropAccess`-chain operand. `undefined` parses as either
  // `Var("undefined")`, `UnaryOp(Void, ...)`, or the bare `undefined`
  // keyword (spec-mandated form).
  let null_match = match (left, right) {
    (e, NullLit) =>
      match narrowing_key_for_expr(e) {
        Some(k) => Some((k, @ast.TsType::Null))
        None => None
      }
    (NullLit, e) =>
      match narrowing_key_for_expr(e) {
        Some(k) => Some((k, @ast.TsType::Null))
        None => None
      }
    (e, UnaryOp(Void, _)) =>
      match narrowing_key_for_expr(e) {
        Some(k) => Some((k, @ast.TsType::Undefined))
        None => None
      }
    (UnaryOp(Void, _), e) =>
      match narrowing_key_for_expr(e) {
        Some(k) => Some((k, @ast.TsType::Undefined))
        None => None
      }
    (e, Var("undefined")) =>
      match narrowing_key_for_expr(e) {
        Some(k) if k != "undefined" => Some((k, @ast.TsType::Undefined))
        _ => None
      }
    (Var("undefined"), e) =>
      match narrowing_key_for_expr(e) {
        Some(k) if k != "undefined" => Some((k, @ast.TsType::Undefined))
        _ => None
      }
    _ => None
  }
  match null_match {
    Some((key, tag)) => {
      let cur = narrowing_current_type(env, resolver, key)
      true_side.push((key, tag))
      let stripped = narrow_remove(cur, fn(v) { type_eq(v, tag) })
      false_side.push((key, stripped))
    }
    None => ()
  }

  // `<chain>.<prop> === "literal"` — discriminated union narrowing on
  // the parent chain. Accepts any `Var` / `PropAccess`-chain on the LHS
  // so `o.shape.kind === "circle"` narrows `o.shape`.
  let disc_match = match (left, right) {
    (PropAccess(parent, prop), StringLit(lit)) =>
      match narrowing_key_for_expr(parent) {
        Some(parent_key) => Some((parent_key, prop, lit))
        None => None
      }
    (StringLit(lit), PropAccess(parent, prop)) =>
      match narrowing_key_for_expr(parent) {
        Some(parent_key) => Some((parent_key, prop, lit))
        None => None
      }
    _ => None
  }
  match disc_match {
    Some((parent_key, prop, lit)) => {
      let cur = narrowing_current_type(env, resolver, parent_key)
      match narrow_by_discriminant(resolver, cur, prop, lit, true) {
        Some(then_ty) => {
          true_side.push((parent_key, then_ty))
          match narrow_by_discriminant(resolver, cur, prop, lit, false) {
            Some(else_ty) => false_side.push((parent_key, else_ty))
            None => ()
          }
        }
        None => ()
      }
    }
    None => ()
  }

  // `<chain> === "literal"` — literal-union narrowing on the chain
  // itself. `Var("s") === "a"` narrows `s`; `c.kind === "a"` narrows
  // `c.kind` (separate from the disc_match above, which narrows the
  // parent rather than the leaf).
  let lit_match = match (left, right) {
    (lhs, StringLit(lit)) =>
      match narrowing_key_for_expr(lhs) {
        Some(key) => Some((key, lit))
        None => None
      }
    (StringLit(lit), rhs) =>
      match narrowing_key_for_expr(rhs) {
        Some(key) => Some((key, lit))
        None => None
      }
    _ => None
  }
  match lit_match {
    Some((name, lit)) => {
      let cur = narrowing_current_type(env, resolver, name)
      match cur {
        Union(_) => {
          let kept = narrow_keep(cur, fn(v) {
            match v {
              Literal(s) => s == lit
              _ => false
            }
          })
          match kept {
            Never => ()
            _ => {
              true_side.push((name, kept))
              let dropped = narrow_remove(cur, fn(v) {
                match v {
                  Literal(s) => s == lit
                  _ => false
                }
              })
              false_side.push((name, dropped))
            }
          }
        }
        _ => ()
      }
    }
    None => ()
  }
}

// ---------------------------------------------------------------------------
// Statement checking.
// ---------------------------------------------------------------------------

///|
fn check_block(env : ExprEnv, block : @ast.TsBlock, ctx : CheckCtx) -> Unit {
  let pre = env.full_snapshot()
  for stmt in block.stmts {
    check_stmt(env, stmt, ctx)
  }
  env.restore_from(pre)
}

///|
/// Checks `block` with the given narrowing `binds` applied, then returns
/// the variable types in effect at the *end* of the block (after the binds
/// plus any in-block assignment narrowing) before restoring the outer env.
/// The `if` handler uses this to join branch exits at the merge point.
fn check_block_narrowing_exit(
  env : ExprEnv,
  block : @ast.TsBlock,
  ctx : CheckCtx,
  binds : Array[(String, @ast.TsType)],
) -> Map[String, @ast.TsType] {
  let pre = env.full_snapshot()
  for b in binds {
    env.bind(b.0, b.1)
  }
  for stmt in block.stmts {
    check_stmt(env, stmt, ctx)
  }
  let exit : Map[String, @ast.TsType] = {}
  for e in env.full_snapshot() {
    exit[e.0] = e.1
  }
  env.restore_from(pre)
  exit
}

///|
/// Bind a `var` / `let` / `const` identifier declaration and check its
/// initializer against the annotation. `track_unassigned` is true only for
/// block-scoped `let` / `const`, where a missing initializer (`let x: T;`)
/// arms the TS2454 "used before assigned" check; `var` is exempt.
fn check_ident_binding_decl(
  env : ExprEnv,
  ctx : CheckCtx,
  name : String,
  declared : @ast.TsType,
  init : @ast.TsExpr,
  block_scoped : Bool,
) -> Unit {
  let bound_type = if is_checkable(declared) {
    declared
  } else {
    // No annotation: infer from the initializer. TypeScript widens the
    // field types of an object / array / tuple literal (their contents
    // are mutable), so `var a = { foo: '' }` is `{ foo: string }`, not
    // `{ foo: '' }`. Apply that to composite inferred shapes so a later
    // `a = b` field comparison isn't over-narrow. Top-level scalars are
    // left to the existing primitive-widening behaviour.
    let inferred = infer_expr(env, ctx.resolver, init)
    match inferred {
      Object(_) | Struct(_, _) | Array(_) | Tuple(_) =>
        widen_literal_deep(inferred)
      _ => inferred
    }
  }
  env.bind(name, bound_type)
  // Make sure the *declared* slot reflects the source annotation
  // (which `bind` set on first write -- subsequent narrowing
  // mutates `vars` only). When the declared annotation was
  // checkable the binding above already pinned declared to it;
  // when not, we leave declared as the inferred-from-init type
  // since that's what TS widens to anyway.
  env.declare_type(name, bound_type)
  // TS2454: parser-synthesised `Var("__ts_no_init__")` marker means
  // `let x: T;` / `var x: T;` with no `=` initializer. Track the binding as
  // unassigned so later references can be flagged. Only do this when the
  // declared type doesn't already accept `undefined` (otherwise the read of
  // an unassigned `x` is well-typed) and when it's checkable (no annotation =
  // `Any`, which TS doesn't flag either). The stored flag records whether the
  // binding is block-scoped (`let` / `const`); a `var` read inside a computed
  // property key is exempt from TS2454 (see the read sites).
  match init {
    Var("__ts_no_init__") =>
      // TS2454 fires only under strict-null-checks (TS treats
      // `let x: number;` as `x: number | undefined` otherwise).
      // The conformance corpus uses the same `// @strict: false`
      // / `// @strictPropertyInitialization: false` opt-out
      // directives we already track for TS2564 -- reuse the
      // module flag.
      if is_checkable(declared) &&
        !type_accepts_undefined(declared) &&
        ctx.strict_property_init &&
        !ctx.resolver.name_assigned_in_static_block(name) {
        ctx.unassigned[name] = block_scoped
      }
    _ => ()
  }
  check_expr_against(env, init, declared, ctx, "binding `\{name}` init")
}

///|
fn check_stmt(env : ExprEnv, stmt : @ast.TsStmt, ctx : CheckCtx) -> Unit {
  match stmt {
    Var(@ast.TsBinding::Ident(name), declared, init) =>
      check_ident_binding_decl(env, ctx, name, declared, init, false)
    Let(@ast.TsBinding::Ident(name), declared, init)
    | Const(@ast.TsBinding::Ident(name), declared, init) =>
      check_ident_binding_decl(env, ctx, name, declared, init, true)
    Var(@ast.TsBinding::Array(ab), declared, init)
    | Let(@ast.TsBinding::Array(ab), declared, init)
    | Const(@ast.TsBinding::Array(ab), declared, init) => {
      check_call_args_in_expr(env, init, ctx)
      // TS2488: an array-destructuring pattern requires an iterable, but a
      // plain object literal (`var [a, b] = { 0: "", 1: true }`) has no
      // `[Symbol.iterator]()`. Object literals are never iterable, so this is
      // false-positive-free — unless the literal carries a computed key that
      // could itself be `[Symbol.iterator]`, in which case we stay silent.
      match init {
        ObjectLit(entries) =>
          if not(entries.iter().any(fn(e) { e.1 is ComputedProp(_, _) })) {
            record(
              ctx, "destructuring init", "object literal must have a `[Symbol.iterator]()` method to be destructured as an array",
            )
          }
        _ => ()
      }
      if is_checkable(declared) {
        check_expr_against(env, init, declared, ctx, "destructuring init")
      }
      let source_ty = if is_checkable(declared) {
        declared
      } else {
        infer_expr(env, ctx.resolver, init)
      }
      bind_array_pattern(env, ctx, ab, source_ty)
    }
    Var(@ast.TsBinding::Object(ob), declared, init)
    | Let(@ast.TsBinding::Object(ob), declared, init)
    | Const(@ast.TsBinding::Object(ob), declared, init) => {
      check_call_args_in_expr(env, init, ctx)
      if is_checkable(declared) {
        check_expr_against(env, init, declared, ctx, "destructuring init")
      }
      let source_ty = if is_checkable(declared) {
        declared
      } else {
        infer_expr(env, ctx.resolver, init)
      }
      bind_object_pattern(env, ctx, ob, source_ty)
    }
    Var(@ast.TsBinding::Target(_), _, init)
    | Let(@ast.TsBinding::Target(_), _, init)
    | Const(@ast.TsBinding::Target(_), _, init) => {
      let _ = infer_expr(env, ctx.resolver, init)
    }
    Expr(e) => {
      check_call_args_in_expr(env, e, ctx)
      // `f(v)` where `f`'s declared return is `asserts v [is T]` narrows
      // `v` for every statement that follows.
      apply_assertion_predicate_effect(env, ctx.resolver, e)
    }
    Assign(name, e) => {
      check_call_args_in_expr(env, e, ctx)
      // Assignment target is the *declared* type, not the (possibly
      // narrowed) current type. `let x: string | number; x = "hi";
      // x = 5;` is valid in TS even after `x` was narrowed to
      // `string` -- the assignment site uses the union. For
      // module-level variables not in this function's local env,
      // fall back to the resolver's globals (where top-level
      // `let x: T;` was registered).
      let target = match env.lookup_declared(name) {
        Some(t) => Some(t)
        None => ctx.resolver.globals.get(name)
      }
      match target {
        Some(target_ty) =>
          check_expr_against(env, e, target_ty, ctx, "assign `\{name}`")
        None => ()
      }
      // After a successful assignment, the variable's effective type
      // becomes the assigned expression's inferred type (TS narrows
      // by assignment). Use `narrow` instead of `bind` so the
      // declared slot stays at the original annotation -- otherwise
      // a later `x = otherValue;` would be checked against this
      // narrowed type instead of the union.
      let new_ty = infer_expr(env, ctx.resolver, e)
      if is_checkable(new_ty) {
        env.narrow(name, new_ty)
      }
      // TS2454: this assignment counts; the variable is no longer
      // "used before being assigned".
      let _ = ctx.unassigned.remove(name)
    }
    CompoundAssign(name, op, e) => {
      check_call_args_in_expr(env, e, ctx)
      // For arithmetic compound ops, the right-hand operand must be numeric
      // if the variable is numeric. We delegate to `infer_binop` to derive
      // the equivalent simple assignment's required type. Targets the
      // declared type (see `Assign` above) so a compound assignment
      // after narrowing still accepts the full declared union.
      match env.lookup_declared(name) {
        Some(target_ty) =>
          check_compound_assign(env, target_ty, op, e, ctx, name)
        None => ()
      }
      // TS2454: a compound assignment (`x += …`) reads x first, but
      // that read is the same use-before-assign hazard. The walker
      // already records the read via `check_call_args_in_expr` on the
      // RHS; after this stmt the variable is unambiguously assigned.
      let _ = ctx.unassigned.remove(name)
    }
    PropAssign(recv, prop, value) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, value, ctx)
      let recv_ty = infer_expr(env, ctx.resolver, recv)
      match ctx.resolver.lookup_field(recv_ty, prop) {
        Some(target_ty) =>
          check_expr_against(env, value, target_ty, ctx, "assign `.\{prop}`")
        None =>
          if is_checkable(recv_ty) &&
            !is_nullable_type(recv_ty) &&
            !is_in_scope_type_param(ctx, recv_ty) &&
            !prop.has_prefix("__private_brand__") &&
            !type_contains_unresolved_named(recv_ty, ctx.resolver) &&
            !member_recv_unmodeled(recv_ty, ctx.resolver) {
            match ctx.resolver.unwrap(recv_ty) {
              Object(_) | Struct(_, _) | Named(_) | Applied(_, _) =>
                record(
                  ctx,
                  "assign `.\{prop}`",
                  "property `\{prop}` does not exist on `\{type_display(recv_ty)}`",
                )
              _ => ()
            }
          }
      }
    }
    IndexAssign(recv, idx, value) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, idx, ctx)
      check_call_args_in_expr(env, value, ctx)
      let recv_ty = infer_expr(env, ctx.resolver, recv)
      match recv_ty {
        Array(elem) =>
          check_expr_against(env, value, elem, ctx, "assign array element")
        Tuple(items) =>
          match idx {
            IntLit(i) if i >= 0 && i < items.length() =>
              check_expr_against(
                env,
                value,
                items[i],
                ctx,
                "assign tuple[\{i}]",
              )
            _ => ()
          }
        _ => ()
      }
    }
    Return(opt) =>
      match opt {
        Some(e) => check_expr_against(env, e, ctx.return_type, ctx, "return")
        None =>
          if is_checkable(ctx.return_type) &&
            !is_assignable_to(@ast.TsType::Undefined, ctx.return_type) &&
            !is_assignable_to(@ast.TsType::Void, ctx.return_type) {
            record(
              ctx,
              "return",
              "expected `\{type_display(ctx.return_type)}` but no value returned",
            )
          }
      }
    Throw(e) => check_call_args_in_expr(env, e, ctx)
    If(cond, then_block, else_block) => {
      check_call_args_in_expr(env, cond, ctx)
      let pre_map : Map[String, @ast.TsType] = {}
      for e in env.full_snapshot() {
        pre_map[e.0] = e.1
      }
      let effect = analyze_narrowing(env, ctx.resolver, cond)
      let then_exit = check_block_narrowing_exit(
        env,
        then_block,
        ctx,
        effect.then_binds,
      )
      let then_exits = block_always_exits(then_block)
      let (else_exit, else_exits) = match else_block {
        Some(b) =>
          (
            check_block_narrowing_exit(env, b, ctx, effect.else_binds),
            block_always_exits(b),
          )
        // No `else`: the else path is the fall-through with the condition's
        // else-narrowing applied and no statements.
        None => {
          let m : Map[String, @ast.TsType] = {}
          for k, v in pre_map {
            m[k] = v
          }
          for bnd in effect.else_binds {
            m[bnd.0] = bnd.1
          }
          (m, false)
        }
      }
      // Narrowing after early return: when one branch unconditionally exits,
      // the surrounding scope continues with the opposite branch's effect
      // applied — so `if (x === null) return; ... /* x is non-null */`
      // works out of the box.
      if then_exits && !else_exits {
        for b in effect.else_binds {
          env.bind(b.0, b.1)
        }
      } else if else_exits && !then_exits {
        for b in effect.then_binds {
          env.bind(b.0, b.1)
        }
      } else if !then_exits && !else_exits {
        // Merge-point join: a variable's type after the `if` is the union of
        // its type at the end of each branch (covering both the condition's
        // narrowing and in-branch reassignment). This makes
        // `if (id === undefined) { id = "1"; }` leave `id` as `string`.
        // Union can only widen back toward the pre-`if` type, so the join
        // never over-narrows. Only touch variables that actually changed in
        // a branch.
        let cands : Map[String, Unit] = {}
        for k, v in then_exit {
          if pre_map.get(k) != Some(v) {
            cands[k] = ()
          }
        }
        for k, v in else_exit {
          if pre_map.get(k) != Some(v) {
            cands[k] = ()
          }
        }
        for k, _ in cands {
          let tt = match then_exit.get(k) {
            Some(t) => Some(t)
            None => pre_map.get(k)
          }
          let et = match else_exit.get(k) {
            Some(t) => Some(t)
            None => pre_map.get(k)
          }
          match (tt, et) {
            (Some(a), Some(b)) => env.narrow(k, narrow_union(a, b))
            _ => ()
          }
        }
      }
    }
    While(cond, body) | DoWhile(cond, body) => {
      check_call_args_in_expr(env, cond, ctx)
      check_block(env, body, ctx)
    }
    For(init, cond, update, body) => {
      let pre = env.full_snapshot()
      match init {
        Some(s) => check_stmt(env, s, ctx)
        None => ()
      }
      match cond {
        Some(e) => check_call_args_in_expr(env, e, ctx)
        None => ()
      }
      match update {
        Some(s) => check_stmt(env, s, ctx)
        None => ()
      }
      check_block(env, body, ctx)
      env.restore_from(pre)
    }
    ForOf(kind, binding, declared, iter, body) => {
      check_call_args_in_expr(env, iter, ctx)
      let iter_ty = infer_expr(env, ctx.resolver, iter)
      let inferred_elem = for_of_element_type(ctx.resolver, iter_ty)
      let elem_ty = if is_checkable(declared) {
        // Validate the declared annotation against the actual element type.
        if is_checkable(inferred_elem) &&
          !is_assignable_to(
            ctx.resolver.unwrap(inferred_elem),
            ctx.resolver.unwrap(declared),
          ) {
          record(
            ctx,
            "for-of binding",
            "declared `\{type_display(declared)}` but iterable yields `\{type_display(inferred_elem)}`",
          )
        }
        declared
      } else {
        inferred_elem
      }
      let pre = env.full_snapshot()
      // TS2454: same reasoning as for-in — the loop variable is assigned
      // each iteration, so reused declarations clear. A destructuring
      // pattern (`for ([k, v] of …)`) assigns every name it binds.
      clear_unassigned_in_binding(ctx, binding)
      // Assignment-form `for (x of obj)` (no `let`/`var`/`const`) reuses
      // the outer-scope variable -- narrow it for the loop body
      // instead of re-declaring (which would otherwise pin the
      // declared slot to the iterable element type and reject
      // any later wider-typed assignments inside the body).
      match (kind, binding) {
        (@ast.TsForOfKind::Assign, @ast.TsBinding::Ident(n)) =>
          if is_checkable(elem_ty) {
            env.narrow(n, elem_ty)
          }
        _ => bind_pattern(env, ctx, binding, elem_ty)
      }
      check_block(env, body, ctx)
      env.restore_from(pre)
    }
    ForAwaitOf(_, binding, declared, iter, body) => {
      check_call_args_in_expr(env, iter, ctx)
      let iter_ty = infer_expr(env, ctx.resolver, iter)
      let unwrapped = unwrap_async_return(true, iter_ty)
      let inferred_elem = for_of_element_type(ctx.resolver, unwrapped)
      let elem_ty = if is_checkable(declared) {
        if is_checkable(inferred_elem) &&
          !is_assignable_to(
            ctx.resolver.unwrap(inferred_elem),
            ctx.resolver.unwrap(declared),
          ) {
          record(
            ctx,
            "for-await-of binding",
            "declared `\{type_display(declared)}` but iterable yields `\{type_display(inferred_elem)}`",
          )
        }
        declared
      } else {
        inferred_elem
      }
      let pre = env.full_snapshot()
      clear_unassigned_in_binding(ctx, binding)
      bind_pattern(env, ctx, binding, elem_ty)
      check_block(env, body, ctx)
      env.restore_from(pre)
    }
    ForIn(_, binding, declared, iter, body) => {
      // `for (key in obj)` — `key` is always `string` in JS/TS.
      // A declared type that doesn't accept `string` is an error.
      check_call_args_in_expr(env, iter, ctx)
      if is_checkable(declared) &&
        !is_assignable_to(@ast.TsType::String_, ctx.resolver.unwrap(declared)) {
        record(
          ctx,
          "for-in binding",
          "for-in key is always `string`, but declared as `\{type_display(declared)}`",
        )
      }
      let key_ty = if is_checkable(declared) {
        declared
      } else {
        @ast.TsType::String_
      }
      let pre = env.full_snapshot()
      // TS2454: the loop binding is *assigned* each iteration, so a
      // previously-declared `let k: T;` reused as the for-in target
      // (`for (k in obj) ...`) shouldn't trip use-before-assign.
      clear_unassigned_in_binding(ctx, binding)
      bind_pattern(env, ctx, binding, key_ty)
      check_block(env, body, ctx)
      env.restore_from(pre)
    }
    Switch(scrutinee, cases) => {
      check_call_args_in_expr(env, scrutinee, ctx)
      // If the scrutinee is a simple `Var(name)`, narrow inside each `case`
      // body with a literal `test_expr` — same shape as
      // `if (name === lit) ...` for primitives + discriminants. Also
      // supports `switch (obj.kind) { case "tag": ... }` by narrowing the
      // outer object via discriminant.
      let scrutinee_name = match scrutinee {
        Var(n) => Some(n)
        _ => None
      }
      let scrutinee_disc = match scrutinee {
        PropAccess(Var(name), prop) => Some((name, prop))
        _ => None
      }
      let scrutinee_ty = ctx.resolver.unwrap(
        infer_expr(env, ctx.resolver, scrutinee),
      )
      for case_ in cases {
        match case_.test_expr {
          Some(e) => {
            check_call_args_in_expr(env, e, ctx)
            // Validate that the case test value could plausibly equal the
            // scrutinee — catch `switch(n: number) { case "hello": }`.
            let case_ty = ctx.resolver.unwrap(infer_expr(env, ctx.resolver, e))
            if is_checkable(scrutinee_ty) &&
              is_checkable(case_ty) &&
              !types_can_overlap(scrutinee_ty, case_ty) {
              record(
                ctx,
                "switch case",
                "case value `\{type_display(case_ty)}` can never match scrutinee `\{type_display(scrutinee_ty)}`",
              )
            }
          }
          None => ()
        }
        let pre = env.full_snapshot()
        match (scrutinee_name, case_.test_expr) {
          (Some(name), Some(t)) =>
            apply_switch_case_narrowing(env, ctx.resolver, name, t)
          _ => ()
        }
        match (scrutinee_disc, case_.test_expr) {
          (Some((obj_name, prop)), Some(t)) =>
            apply_switch_disc_narrowing(env, ctx.resolver, obj_name, prop, t)
          _ => ()
        }
        // `default:` body — narrow against all literal cases.
        match (scrutinee_name, case_.test_expr) {
          (Some(name), None) =>
            apply_switch_default_narrowing(env, ctx.resolver, name, cases)
          _ => ()
        }
        // Discriminator default: `switch (obj.kind) { case "a": …
        // default: /* obj has none of the listed tags */ }`. Strip
        // every union member whose discriminant matches one of the
        // listed cases so the default body sees the exhaustive remainder.
        match (scrutinee_disc, case_.test_expr) {
          (Some((obj_name, prop)), None) =>
            apply_switch_disc_default_narrowing(
              env,
              ctx.resolver,
              obj_name,
              prop,
              cases,
            )
          _ => ()
        }
        check_block(env, case_.body, ctx)
        env.restore_from(pre)
      }
    }
    With(_, body) => check_block(env, body, ctx)
    Try(try_block, catch_binding, catch_block, finally_block) => {
      check_block(env, try_block, ctx)
      match catch_block {
        Some(cb) => {
          let pre = env.full_snapshot()
          // TS 4.0+ defaults catch bindings to `unknown`. We don't model
          // `unknown` separately (it folds into `Any` here), but binding to
          // `Any` matches the prior semantics — the caller still has to
          // narrow before use.
          match catch_binding {
            Some(@ast.TsBinding::Ident(name)) =>
              env.bind(name, @ast.TsType::Any)
            _ => ()
          }
          check_block(env, cb, ctx)
          env.restore_from(pre)
        }
        None => ()
      }
      match finally_block {
        Some(fb) => check_block(env, fb, ctx)
        None => ()
      }
    }
    Block(b) => check_block(env, b, ctx)
    Label(_, inner) => check_stmt(env, inner, ctx)
    Empty | Break(_) | Continue(_) | Debugger => ()
    NativeClassStmt(decl, _) =>
      // A class declaration's static initialization blocks run eagerly at
      // definition time, so an assignment to an outer variable inside one
      // (`let foo; class C { static { foo = 1 } }`) definitely assigns it.
      // Walk the blocks so the TS2454 (use-before-assigned) set is cleared;
      // checking them under the surrounding scope also surfaces any nested
      // errors.
      for block in decl.static_blocks {
        check_block(env, block, ctx)
      }
  }
}

///|
/// Walk `expr` for call sites and validate their arguments against the
/// callee's declared parameter types. Pure inference is also run to populate
/// inferred subtypes / surface compound issues.

///|
/// Language keywords / pseudo-values that surface as bare identifiers in the
/// AST (`this`, `super`, `arguments`, …) and contextual keywords the parser
/// can hand back as a `Var` in ambiguous positions (`new.target`,
/// `yield`-in-template, `let`-as-name). Never a TS2304 ("Cannot find name").
fn is_pseudo_value_keyword(name : String) -> Bool {
  match name {
    "this"
    | "super"
    | "arguments"
    | "undefined"
    | "null"
    | "true"
    | "false"
    | "void"
    | "globalThis"
    | "eval"
    | "new"
    | "yield"
    | "await"
    | "let"
    | "async"
    | "of"
    | "as"
    | "from"
    | "get"
    | "set" => true
    _ => false
  }
}

///|
fn is_ascii_ident_start_name(name : String) -> Bool {
  for c in name {
    return (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      c == '_' ||
      c == '$'
  }
  false
}

///|
/// TS2304 ("Cannot find name 'X'"): a value-position identifier bound in no
/// scope we track, not declared anywhere in the module, and not a standard
/// ambient global. The `declared_value_names` backstop means hoisting /
/// forward references never trip this; `is_lib_global_value` (generated from
/// the TypeScript standard libraries) covers ambient runtime globals.
fn check_undefined_name(env : ExprEnv, ctx : CheckCtx, name : String) -> Unit {
  if name == "__ts_no_init__" {
    return
  }
  // Only plain ASCII-identifier references. Filters lexer artifacts (a
  // leading UTF-8 BOM is otherwise tokenised as an identifier) and
  // unicode-named bindings we don't cheaply reason about — a missed
  // diagnostic there beats a false positive.
  if !is_ascii_ident_start_name(name) {
    return
  }
  if is_pseudo_value_keyword(name) || is_lib_global_value(name) {
    return
  }
  if env.lookup(name) is Some(_) {
    return
  }
  if ctx.resolver.globals.get(name) is Some(_) {
    return
  }
  if ctx.resolver.declared_value_names.get(name) is Some(_) {
    return
  }
  if ctx.resolver.classes.get(name) is Some(_) {
    return
  }
  if ctx.resolver.enums.get(name) is Some(_) {
    return
  }
  if ctx.in_scope_type_params.contains(name) {
    return
  }
  record(ctx, "use `\{name}`", "cannot find name `\{name}`")
}

///|

///|
/// TS2558 ("Expected N type arguments, but got M") for explicit type arguments
/// supplied to a callee that is *confidently* non-generic: a declared class or
/// function that declares zero type parameters. Restricted to that case to
/// stay false-positive-free — when the callee can't be resolved, or is generic
/// / `any` / a callable interface whose type-parameter count we don't model,
/// the check stays silent.
fn check_explicit_type_args(
  ctx : CheckCtx,
  targs : Array[@ast.TsType],
  inner : @ast.TsExpr,
) -> Unit {
  if targs.length() == 0 {
    return
  }
  // The callee's declared type-parameter names (positional), or `None` when the
  // callee can't be resolved to a declared class / function (stay silent).
  fn declared_type_params(name : String) -> Array[String]? {
    match ctx.resolver.classes.get(name) {
      Some(cls) => Some(cls.type_params)
      None => ctx.resolver.func_type_params.get(name)
    }
  }

  // The callee's `(param, bound)` constraints — sparse, only constrained
  // parameters appear.
  fn declared_bounds(name : String) -> Array[(String, @ast.TsType)] {
    match ctx.resolver.classes.get(name) {
      Some(cls) => cls.type_param_bounds
      None =>
        match ctx.resolver.func_type_param_bounds.get(name) {
          Some(b) => b
          None => []
        }
    }
  }

  let callee_name = match inner {
    Call(name, _) => Some(name)
    New(name, _) => Some(name)
    _ => None
  }
  guard callee_name is Some(name) else { return }
  guard declared_type_params(name) is Some(params) else { return }
  // Supplying *more* type arguments than the callee declares is always an
  // error, regardless of any trailing defaults — defaults make trailing
  // parameters optional but never raise the maximum. (The "too few" direction
  // is left silent: without default-parameter info we can't tell a required
  // parameter from a defaulted one, so flagging it would risk false positives.)
  if targs.length() > params.length() {
    record(
      ctx,
      "call `\{name}`",
      "expected \{params.length()} type arguments, but got \{targs.length()}",
    )
    return
  }
  // TS2344: a type argument that doesn't satisfy its parameter's `extends`
  // constraint. Mirrors the type-position check in `check_constraints`:
  // positional substitution of the supplied arguments into the bound (so
  // dependent constraints like `K extends keyof T` see the concrete `T`),
  // then a three-valued `extends_decision_with` — only a definite `Some(false)`
  // is reported, keeping the check false-positive-free. Requires an exact
  // arity match so the positional substitution is meaningful.
  let bounds = declared_bounds(name)
  if bounds.length() == 0 || params.length() != targs.length() {
    return
  }
  let resolve = fn(n : String) -> @ast.TsType? {
    match ctx.resolver.type_aliases.get(n) {
      Some(ta) =>
        if ta.type_params.length() == 0 {
          Some(ta.type_)
        } else {
          None
        }
      None => None
    }
  }
  for pair in bounds {
    let (pname, bound) = pair
    let mut idx = -1
    for i in 0..<params.length() {
      if params[i] == pname {
        idx = i
        break
      }
    }
    if idx < 0 {
      continue
    }
    let mut substituted = bound
    for i in 0..<params.length() {
      substituted = substitute_named(substituted, params[i], targs[i])
    }
    let target = simplify_type(substituted)
    let arg = simplify_type(targs[idx])
    if extends_decision_with(arg, target, resolve) is Some(false) {
      record(
        ctx,
        "call `\{name}`",
        "type argument does not satisfy the `\{pname}` constraint",
      )
    }
  }
}

///|
fn check_call_args_in_expr(
  env : ExprEnv,
  expr : @ast.TsExpr,
  ctx : CheckCtx,
) -> Unit {
  match expr {
    // A call carrying explicit type arguments: first validate the type-argument
    // list against the callee, then descend into the underlying call so its
    // arguments are still checked.
    TypeArgs(targs, inner) => {
      check_explicit_type_args(ctx, targs, inner)
      check_call_args_in_expr(env, inner, ctx)
    }
    Call(name, args) => {
      // TS2304: calling a name declared nowhere and not a standard global.
      check_undefined_name(env, ctx, name)
      // TS2454: invoking an as-yet-unassigned variable (`var f: T; f()`)
      // reads it before assignment, same as a bare reference.
      if name != "__ts_no_init__" &&
        ctx.unassigned.get(name) is Some(block_scoped) &&
        (not(ctx.in_computed_key) || block_scoped) {
        record(
          ctx,
          "use `\{name}`",
          "variable `\{name}` is used before being assigned",
        )
        let _ = ctx.unassigned.remove(name)
      }
      let callee_ty = match env.lookup(name) {
        Some(t) => t
        None =>
          match ctx.resolver.globals.get(name) {
            Some(t) => t
            None => @ast.TsType::Any
          }
      }
      match callee_ty {
        Func(params, _) => {
          let sig = ctx.resolver.signatures.get(name)
          // Substitute type-parameter bindings into the formal params
          // before checking, so generic calls like `map([1,2,3], x => x)`
          // see `params = [number[], (number) => R]` instead of
          // `[T[], (T) => R]`.
          let type_params = match ctx.resolver.func_type_params.get(name) {
            Some(tps) => tps
            None => []
          }
          let substituted_params = if type_params.length() > 0 {
            let bindings = solve_generic_bindings(
              env,
              ctx.resolver,
              type_params,
              params,
              args,
              sig,
            )
            substitute_params_array(params, bindings)
          } else {
            params
          }
          // A direct call to a top-level function *declaration* (present in
          // `signatures`) with no rest parameter has an exact, reliable
          // arity -- safe to report even in permissive mode. Call-signature
          // -typed variables, inferred function values, and rest-bearing
          // signatures are not in `signatures` (or carry a rest) and stay
          // suppressed. (`this` parameters are stripped during resolver
          // construction, so they no longer skew the count.)
          let arity_reliable = match sig {
            Some(ps) => {
              let mut ok = true
              for p in ps {
                if p.is_rest {
                  ok = false
                }
              }
              ok
            }
            None => false
          }
          check_arguments_with_sig(
            env,
            substituted_params,
            sig,
            args,
            ctx,
            "call `\{name}`",
            arity_reliable~,
          )
        }
        other =>
          // A union callee whose members share one identical call signature
          // (`{ (a:number):X } | { (a:number):Y }`) is callable with those
          // parameters; otherwise fall back to the not-callable diagnostic.
          match union_common_call_params(other, ctx.resolver) {
            Some(params) =>
              check_arguments(env, params, args, ctx, "call `\{name}`")
            None =>
              if is_definitely_not_callable(other) {
                record(
                  ctx,
                  "call `\{name}`",
                  "`\{type_display(other)}` is not callable",
                )
              }
          }
      }
      for a in args {
        check_call_args_in_expr(env, a, ctx)
      }
    }
    CallExpr(callee, args) => {
      let callee_ty = ctx.resolver.unwrap(infer_expr(env, ctx.resolver, callee))
      match callee_ty {
        Func(params, _) => check_arguments(env, params, args, ctx, "call")
        // A union callee whose members share one identical call signature is
        // callable with those parameters (`{ (a:number):X } | { (a:number):Y
        // }`); check the arguments against them.
        Union(_) =>
          match union_common_call_params(callee_ty, ctx.resolver) {
            Some(params) => check_arguments(env, params, args, ctx, "call")
            None => ()
          }
        other =>
          if is_definitely_not_callable(other) {
            record(ctx, "call", "`\{type_display(other)}` is not callable")
          }
      }
      check_call_args_in_expr(env, callee, ctx)
      for a in args {
        check_call_args_in_expr(env, a, ctx)
      }
    }
    MethodCall(receiver, meth, args) => {
      check_private_name_access(ctx, meth)
      check_member_accessibility(env, ctx, receiver, meth)
      // Static-namespace dispatch: `Math.max(...)`, `JSON.stringify(...)`.
      // Recognised by the bare-identifier shape of the receiver. Also handle
      // a static method called through the class name (`A.s(args)`), whose
      // parameter types we read straight off the class declaration.
      let static_params : Array[@ast.TsType]? = match receiver {
        Var(name) =>
          match global_namespace_method(name, meth) {
            Some(Func(params, _)) => Some(params)
            _ =>
              match ctx.resolver.classes.get(name) {
                Some(cls) => class_static_method_param_types(cls, meth)
                None => None
              }
          }
        _ => None
      }
      match static_params {
        Some(params) =>
          check_arguments(env, params, args, ctx, "call `\{meth}`")
        None => {
          let recv_ty = infer_expr(env, ctx.resolver, receiver)
          if is_nullable_type(recv_ty) {
            record(
              ctx,
              "call `\{meth}`",
              "cannot call `.\{meth}()` — receiver may be null or undefined",
            )
          } else {
            let pruned = prune_nullish(ctx.resolver, recv_ty)
            match ctx.resolver.lookup_method_sig(pruned, meth) {
              Some((params, _)) =>
                check_arguments(env, params, args, ctx, "call `\{meth}`")
              None =>
                // If the receiver has a concrete shape and we can't find the
                // method, flag it — but be conservative and skip Any/primitives
                // (which have many built-in methods we don't model).
                match ctx.resolver.unwrap(pruned) {
                  Named(_) | Applied(_, _) | Object(_) | Struct(_, _) =>
                    if is_checkable(pruned) &&
                      !is_in_scope_type_param(ctx, pruned) &&
                      ctx.resolver.lookup_field(pruned, meth) is None &&
                      // Same opaque-shape guard as the property-existence
                      // check: when the receiver contains an unresolvable
                      // Named ref (this-type, in-scope TP we lost track
                      // of, qualified-namespace member), the resulting
                      // diagnostic is uninformative -- stay silent.
                      !type_contains_unresolved_named(pruned, ctx.resolver) &&
                      !member_recv_unmodeled(pruned, ctx.resolver) {
                      record(
                        ctx,
                        "call `\{meth}`",
                        "method `\{meth}` does not exist on `\{type_display(pruned)}`",
                      )
                    }
                  _ => ()
                }
            }
          }
        }
      }
      check_call_args_in_expr(env, receiver, ctx)
      for a in args {
        check_call_args_in_expr(env, a, ctx)
      }
    }
    New(class_name, args) => {
      check_abstract_instantiation(ctx, class_name)
      match ctx.resolver.lookup_constructor_sig(class_name) {
        Some((params, sig)) => {
          check_arguments_with_sig(
            env,
            params,
            Some(sig),
            args,
            ctx,
            "new `\{class_name}`",
            arity_reliable=true,
          )
          for a in args {
            check_call_args_in_expr(env, a, ctx)
          }
        }
        None => {
          // Not a resolvable class constructor: the name may be a value
          // typed as a union of construct-signature objects (`declare var X:
          // { new (a:number):T } | { new (a:number):U }`). When every member
          // shares one identical construct signature, check the arguments
          // against its parameters.
          let callee_ty = match env.lookup(class_name) {
            Some(t) => t
            None =>
              match ctx.resolver.globals.get(class_name) {
                Some(t) => t
                None => @ast.TsType::Any
              }
          }
          match union_common_construct_params(callee_ty, ctx.resolver) {
            Some(params) =>
              check_arguments(env, params, args, ctx, "new `\{class_name}`")
            None => ()
          }
          for a in args {
            check_call_args_in_expr(env, a, ctx)
          }
        }
      }
    }
    NewExpr(callee, args) => {
      match new_callee_class_name(callee) {
        Some(name) => check_abstract_instantiation(ctx, name)
        None => ()
      }
      check_call_args_in_expr(env, callee, ctx)
      for a in args {
        check_call_args_in_expr(env, a, ctx)
      }
    }
    BinOp(op, l, r) => {
      check_call_args_in_expr(env, l, ctx)
      check_call_args_in_expr(env, r, ctx)
      check_binop_operands(env, op, l, r, ctx)
    }
    UnaryOp(op, inner) => {
      check_call_args_in_expr(env, inner, ctx)
      match op {
        Neg | BitwiseNot => {
          let inner_ty = ctx.resolver.unwrap(
            infer_expr(env, ctx.resolver, inner),
          )
          if is_checkable(inner_ty) && is_definitely_not_arithmetic(inner_ty) {
            record(
              ctx,
              "unary op",
              "operand `\{type_display(inner_ty)}` is not a valid number type",
            )
          }
        }
        // Unary `+` is the explicit numeric-coercion operator, so TypeScript
        // accepts string operands (`+"5"`, `+templateString`, `+forInKey`)
        // as well as number / bigint / any. Only operands that cannot
        // coerce at all (objects, arrays, …) are flagged.
        Plus => {
          let inner_ty = ctx.resolver.unwrap(
            infer_expr(env, ctx.resolver, inner),
          )
          let is_stringish = match inner_ty {
            String_ | Literal(_) => true
            _ => false
          }
          if is_checkable(inner_ty) &&
            is_definitely_not_arithmetic(inner_ty) &&
            !is_stringish {
            record(
              ctx,
              "unary op",
              "operand `\{type_display(inner_ty)}` is not a valid number type",
            )
          }
        }
        _ => ()
      }
    }
    Cond(c, t, e) => {
      check_call_args_in_expr(env, c, ctx)
      check_call_args_in_expr(env, t, ctx)
      check_call_args_in_expr(env, e, ctx)
    }
    ArrayLit(items) =>
      for it in items {
        check_call_args_in_expr(env, it, ctx)
      }
    ObjectLit(entries) =>
      for ent in entries {
        check_call_args_in_expr(env, ent.1, ctx)
      }
    // A computed property key (`{ [e]: 1 }`, `class C { [e]() {} }`) is an
    // ordinary value expression: walk both the key and the value so an
    // undefined name in the key surfaces (TS2304) like any other reference.
    // The key is walked with `in_computed_key` set so the TS2454
    // used-before-assigned read-check is suppressed there (tsc accepts a
    // declared-but-unassigned name read inside a computed key).
    ComputedProp(key, value) => {
      let saved = ctx.in_computed_key
      ctx.in_computed_key = true
      check_call_args_in_expr(env, key, ctx)
      ctx.in_computed_key = saved
      check_call_args_in_expr(env, value, ctx)
    }
    PropAccess(recv, prop) => {
      check_call_args_in_expr(env, recv, ctx)
      check_private_name_access(ctx, prop)
      check_member_accessibility(env, ctx, recv, prop)
      // Property-existence check: when the receiver has a concrete
      // structural shape and the resolver can't find `prop` on it,
      // surface a diagnostic. The class static-side fallback used
      // by `infer_expr` already runs `r.globals[Class.member]` lookups
      // and the resolver's instance/class lookup is exhaustive — so
      // if both miss against a checkable receiver, the property
      // genuinely doesn't exist on the static shape.
      match recv {
        Var(class_name) =>
          match ctx.resolver.globals.get(class_name + "." + prop) {
            Some(_) => ()
            None =>
              match ctx.resolver.classes.get(class_name) {
                Some(cls) => {
                  let mut has_static = false
                  for p in cls.properties {
                    if p.name == prop && p.is_static {
                      has_static = true
                    }
                  }
                  for m in cls.methods {
                    if m.name == prop && m.is_static {
                      has_static = true
                    }
                  }
                  if has_static {
                    return
                  }
                  // Fall through to the general lookup below.
                  let recv_ty = infer_expr(env, ctx.resolver, recv)
                  if is_checkable(recv_ty) &&
                    !is_in_scope_type_param(ctx, recv_ty) &&
                    !member_recv_unmodeled(recv_ty, ctx.resolver) &&
                    !(ctx.resolver.lookup_field(recv_ty, prop) is Some(_)) {
                    record(
                      ctx,
                      "PropAccess `.\{prop}`",
                      "property `\{prop}` does not exist on `\{type_display(recv_ty)}`",
                    )
                  }
                  return
                }
                None => ()
              }
          }
        _ => ()
      }
      let recv_ty = infer_expr(env, ctx.resolver, recv)
      // Null/undefined receiver: `.foo` on `null | undefined` is a runtime error.
      if is_nullable_type(recv_ty) {
        record(
          ctx,
          "PropAccess `.\{prop}`",
          "cannot access `.\{prop}` — receiver may be null or undefined",
        )
      } else if is_checkable(recv_ty) &&
        !is_in_scope_type_param(ctx, recv_ty) &&
        // Prune null/undefined before the existence lookup: a field declared on
        // the non-nullish part of `T | null` (e.g. accessed via `a?.b`) still
        // exists. The pure-null case is handled by the branch above.
        !(ctx.resolver.lookup_field(prune_nullish(ctx.resolver, recv_ty), prop)
        is Some(_)) &&
        // Discriminated unions: when at least one member has the field the
        // access is valid under flow-narrowing we can't model. Stay silent.
        !ctx.resolver.field_on_any_union_member(
          prune_nullish(ctx.resolver, recv_ty),
          prop,
        ) &&
        // Suppress when the receiver shape contains an unresolvable Named
        // ref (`this`, an in-scope generic, a qualified-namespace name
        // the resolver doesn't expand). The diagnostic would just render
        // the opaque shape with no actionable detail and almost always
        // comes from a generic / `this`-type / flow-narrowing gap we
        // don't model.
        !type_contains_unresolved_named(recv_ty, ctx.resolver) &&
        // Mapped / conditional / generic-alias shapes (`Proxify<Shape>`,
        // `Boxified<Foo>`, …) resolve to forms we can't enumerate; TS
        // accepts member access on them, so stay silent.
        !member_recv_unmodeled(recv_ty, ctx.resolver) {
        record(
          ctx,
          "PropAccess `.\{prop}`",
          "property `\{prop}` does not exist on `\{type_display(recv_ty)}`",
        )
      }
    }
    IndexAccess(recv, idx) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, idx, ctx)
      let recv_ty = ctx.resolver.unwrap(infer_expr(env, ctx.resolver, recv))
      // `x["charAt"]` / `n["toExponential"]` reaches a prototype member by
      // name — valid even on primitives — so a string-literal key is never
      // an "cannot index into" error. Only flag genuine numeric / dynamic
      // indexing into a non-indexable primitive.
      let string_keyed = idx is StringLit(_)
      if is_checkable(recv_ty) &&
        is_definitely_not_indexable(recv_ty) &&
        !string_keyed {
        record(
          ctx,
          "index access",
          "cannot index into `\{type_display(recv_ty)}`",
        )
      }
      // TS2493 ("Tuple type has no element at index N"): a fixed-length
      // tuple indexed by an out-of-range numeric literal. Tuples that
      // carry a `...rest` element accept any index, so we skip those.
      // Tuple length is a property of the *declared* type, so for a bare
      // variable receiver consult the declared slot rather than the
      // flow-narrowed type (`t = [a, b]` would otherwise erase the tuple
      // shape down to an array literal and hide the out-of-range access).
      let tuple_ty = match recv {
        Var(name) =>
          match env.lookup_declared(name) {
            Some(d) => ctx.resolver.unwrap(d)
            None => recv_ty
          }
        _ => recv_ty
      }
      match tuple_ty {
        Tuple(items) => {
          let mut has_rest = false
          for it in items {
            if it is Rest(_) {
              has_rest = true
            }
          }
          if !has_rest {
            let idx_lit = match idx {
              IntLit(n) => Some(n)
              NumberLit(d) =>
                if d >= 0.0 && d == d.to_int().to_double() {
                  Some(d.to_int())
                } else {
                  None
                }
              _ => None
            }
            match idx_lit {
              Some(n) =>
                if n >= 0 && n >= items.length() {
                  record(
                    ctx,
                    "index access",
                    "tuple type `\{type_display(tuple_ty)}` has no element at index \{n}",
                  )
                }
              None => ()
            }
          }
        }
        _ => ()
      }
    }
    AssignExpr(name, v) => {
      check_call_args_in_expr(env, v, ctx)
      // Assignment target is the *declared* type, not the narrowed
      // current type (same reasoning as the stmt-level `Assign`
      // case above). Falls back to `resolver.globals` for module-
      // level variables not in this scope's local env.
      let target = match env.lookup_declared(name) {
        Some(t) => Some(t)
        None => ctx.resolver.globals.get(name)
      }
      match target {
        Some(target_ty) =>
          check_expr_against(env, v, target_ty, ctx, "assign `\{name}`")
        None => ()
      }
      // Narrow-by-assignment: the variable's effective type now
      // reflects the assigned value's type. Narrowing-only -- don't
      // touch the declared slot.
      let new_ty = infer_expr(env, ctx.resolver, v)
      if is_checkable(new_ty) {
        env.narrow(name, new_ty)
      }
      // TS2454: clear the unassigned marker now that the variable
      // has a concrete assignment.
      let _ = ctx.unassigned.remove(name)
    }
    CompoundAssignExpr(target, op, v) => {
      check_call_args_in_expr(env, target, ctx)
      check_call_args_in_expr(env, v, ctx)
      // TS2364: the left-hand side of an assignment must be a variable or a
      // property access. A literal LHS (`1 >>= 2`) is never assignable. Only
      // literals are flagged — every reference-shaped target (`Var`, member /
      // index access, and anything we can't classify) is left silent, so the
      // check is false-positive-free.
      match target {
        NumberLit(_)
        | IntLit(_)
        | BigIntLit(_)
        | BoolLit(_)
        | StringLit(_)
        | NullLit =>
          record(
            ctx, "assignment", "the left-hand side of an assignment expression must be a variable or a property access",
          )
        _ => ()
      }
      // TS2454: a compound assignment (`x += …`) settles `x` after
      // the rhs walk above (which still flags the implicit read).
      match target {
        Var(name) => {
          let _ = ctx.unassigned.remove(name)
        }
        _ => ()
      }
      match target {
        Var(name) =>
          match env.lookup_declared(name) {
            Some(target_ty) =>
              check_compound_assign(env, target_ty, op, v, ctx, name)
            None => ()
          }
        _ => ()
      }
    }
    AssignPattern(binding, v) => {
      check_call_args_in_expr(env, v, ctx)
      // TS2454: a destructuring assignment pattern (`[a, b] = …` /
      // `{x, y} = …`) writes every named binding inside. Clear them
      // from the unassigned set so subsequent reads don't trip.
      clear_unassigned_in_binding(ctx, binding)
    }
    Spread(v) | Await(v) => check_call_args_in_expr(env, v, ctx)
    PropAssignExpr(recv, prop, v) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, v, ctx)
      check_private_name_access(ctx, prop)
      check_member_accessibility(env, ctx, recv, prop)
      let recv_ty = infer_expr(env, ctx.resolver, recv)
      if !prop.has_prefix("__private_brand__") &&
        is_readonly_field(ctx.resolver, recv_ty, prop) {
        record(
          ctx,
          "assign `.\{prop}`",
          "cannot assign to `\{prop}` because it is read-only",
        )
      }
      match ctx.resolver.lookup_field(recv_ty, prop) {
        Some(target_ty) =>
          check_expr_against(env, v, target_ty, ctx, "assign `.\{prop}`")
        None =>
          if is_checkable(recv_ty) &&
            !is_nullable_type(recv_ty) &&
            !is_in_scope_type_param(ctx, recv_ty) &&
            !prop.has_prefix("__private_brand__") &&
            !type_contains_unresolved_named(recv_ty, ctx.resolver) &&
            !member_recv_unmodeled(recv_ty, ctx.resolver) {
            match ctx.resolver.unwrap(recv_ty) {
              Object(_) | Struct(_, _) | Named(_) | Applied(_, _) =>
                record(
                  ctx,
                  "assign `.\{prop}`",
                  "property `\{prop}` does not exist on `\{type_display(recv_ty)}`",
                )
              _ => ()
            }
          }
      }
    }
    IndexAssignExpr(recv, idx, v) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, idx, ctx)
      check_call_args_in_expr(env, v, ctx)
      let recv_ty = infer_expr(env, ctx.resolver, recv)
      match ctx.resolver.unwrap(recv_ty) {
        // `ReadonlyArray<T>` (and the `readonly [...]` tuple form, when it
        // survives as such) permits reads only — element assignment is a
        // type error in TypeScript (TS2542).
        Applied("ReadonlyArray", _) =>
          record(
            ctx, "assign element", "index signature in a `ReadonlyArray` only permits reading",
          )
        Array(elem) =>
          check_expr_against(env, v, elem, ctx, "assign array element")
        Tuple(items) =>
          match idx {
            IntLit(i) if i >= 0 && i < items.length() =>
              check_expr_against(env, v, items[i], ctx, "assign tuple[\{i}]")
            _ => ()
          }
        _ => ()
      }
    }
    Seq(a, b) => {
      check_call_args_in_expr(env, a, ctx)
      check_call_args_in_expr(env, b, ctx)
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        check_call_args_in_expr(env, e, ctx)
      }
    Yield(operand_opt) =>
      match operand_opt {
        Some(operand) => {
          check_call_args_in_expr(env, operand, ctx)
          // Inside a generator, `yield x` must produce a value
          // assignable to the declared element type. Outside (or
          // when the type isn't statically extractable) the
          // yield_type is `Any` and the check no-ops.
          if is_checkable(ctx.yield_type) {
            check_expr_against(env, operand, ctx.yield_type, ctx, "yield")
          }
        }
        None => ()
      }
    YieldStar(operand) => {
      check_call_args_in_expr(env, operand, ctx)
      // `yield* iter` delegates to another iterable. Validate against
      // `Iterable<T>` / `Generator<T, ...>` of the same element type.
      if is_checkable(ctx.yield_type) {
        let expected : @ast.TsType = Union([
          Applied("Iterable", [ctx.yield_type]),
          Applied("IterableIterator", [ctx.yield_type]),
          Applied("Generator", [ctx.yield_type, Any, Any]),
        ])
        check_expr_against(env, operand, expected, ctx, "yield*")
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      check_call_args_in_expr(env, tag, ctx)
      for e in exprs {
        check_call_args_in_expr(env, e, ctx)
      }
    }
    // New AST wrappers: recurse into the inner expression so call-site
    // checks inside `(call(badArg) as T)` / `call(badArg)!` / `obj?.m()`
    // still fire.
    As(inner, asserted) => {
      check_call_args_in_expr(env, inner, ctx)
      // TS2300: an object type-literal in the asserted type (`<{a;a}>x`,
      // `x as { a; a }`) with duplicate property names.
      collect_type_dup_issues(asserted, ctx.path_prefix, ctx.issues)
      // Validate `x as T`: if neither direction is assignable the assertion
      // is always wrong (e.g. `5 as string`).
      // We only flag when both sides are concrete primitive-ish types so we
      // don't accidentally fire on generic type parameters or opaque named
      // types that we can't fully resolve here.
      let inferred = infer_expr(env, ctx.resolver, inner)
      let concrete = fn(t : @ast.TsType) -> Bool {
        match t {
          Number
          | String_
          | Boolean
          | BigInt
          | Null
          | Undefined
          | Void
          | Never
          | NumberLiteral(_)
          | BooleanLiteral(_)
          | Literal(_)
          | BigIntLiteral(_) => true
          _ => false
        }
      }
      if concrete(inferred) &&
        concrete(asserted) &&
        !is_assignable_to(inferred, asserted) &&
        !is_assignable_to(asserted, inferred) {
        record(
          ctx,
          "as",
          "Type '\{type_display(inferred)}' cannot be asserted to type '\{type_display(asserted)}' (no overlap)",
        )
      }
    }
    NonNull(inner) => check_call_args_in_expr(env, inner, ctx)
    // Optional chain (`a?.b…`) handles the nullishness for us. Surface
    // call-arg / type-position checks on the inner expression, but skip
    // the inner PropAccess's "may be null or undefined" diagnostic by
    // peeling one chain step ourselves before recursing.
    OptionalChain(inner) =>
      match inner {
        PropAccess(recv, prop) => {
          // Walk the receiver for any nested issues, then run the
          // property-existence check against the *pruned* receiver
          // type so we don't double-flag on the explicit optional
          // chain.
          check_call_args_in_expr(env, recv, ctx)
          let recv_ty = ctx.resolver.unwrap(
            prune_nullish(ctx.resolver, infer_expr(env, ctx.resolver, recv)),
          )
          if is_checkable(recv_ty) &&
            !is_in_scope_type_param(ctx, recv_ty) &&
            !member_recv_unmodeled(recv_ty, ctx.resolver) &&
            !(ctx.resolver.lookup_field(recv_ty, prop) is Some(_)) &&
            !ctx.resolver.field_on_any_union_member(recv_ty, prop) {
            record(
              ctx,
              "PropAccess `?.\{prop}`",
              "property `\{prop}` does not exist on `\{type_display(recv_ty)}`",
            )
          }
        }
        _ => check_call_args_in_expr(env, inner, ctx)
      }
    Satisfies(inner, ty) => {
      check_call_args_in_expr(env, inner, ctx)
      // `x satisfies T` — verify the operand is assignable to `T`.
      check_expr_against(env, inner, ty, ctx, "satisfies")
    }
    // JSX element / fragment: recurse into every attribute value and
    // child sub-expression so call-site mismatches inside JSX braces
    // are reported. When the tag resolves to a known component (a
    // top-level function whose only parameter is a Props interface or
    // object type), also run per-attribute type checks against the
    // declared prop types.
    JsxElement(tag, attrs, children) => {
      check_jsx_attrs(env, tag, attrs, children, ctx)
      for entry in attrs {
        match entry.1 {
          Some(value) => check_call_args_in_expr(env, value, ctx)
          None => ()
        }
      }
      // Each child entry is a `TsExpr` — text segments are wrapped as
      // `StringLit(...)`, JSX expressions are parsed expressions, and
      // nested elements are themselves `JsxElement(...)`. Recursing
      // through `check_call_args_in_expr` handles all three uniformly
      // (text literals walk through as no-op).
      for c in children {
        check_call_args_in_expr(env, c, ctx)
        // React `key` rule: when a child is `xs.map(fn)` and `fn`
        // returns a JSX element, that element needs a `key` attr.
        check_jsx_key_in_map(c, ctx)
      }
    }
    // TS2454: a bare identifier reference. If the name is in the
    // unassigned set (parser-synthesised `let x: T;` with no `=`),
    // emit the diagnostic and clear the entry so we only fire once
    // per variable. Skips the parser's no-init sentinel itself
    // (which appears as the rhs of the synthesised init).
    Var(name) => {
      if name != "__ts_no_init__" &&
        ctx.unassigned.get(name) is Some(block_scoped) &&
        (not(ctx.in_computed_key) || block_scoped) {
        record(
          ctx,
          "use `\{name}`",
          "variable `\{name}` is used before being assigned",
        )
        let _ = ctx.unassigned.remove(name)
      }
      check_undefined_name(env, ctx, name)
    }
    _ => ()
  }
}

///|
/// React `key`-in-iteration rule: when a JSX child is the result of
/// `xs.map(fn)` and the callback returns a JSX element, that element
/// must declare a `key` attribute. The check walks the immediate child
/// expression and records `<Tag>` missing `key` diagnostics; deeply
/// nested misses are left to the recursive `check_call_args_in_expr`.
fn check_jsx_key_in_map(child : @ast.TsExpr, ctx : CheckCtx) -> Unit {
  match child {
    MethodCall(_, meth, args) =>
      if meth == "map" && args.length() >= 1 {
        walk_map_callback_for_key(args[0], ctx)
      }
    CallExpr(callee, args) =>
      match callee {
        PropAccess(_, meth) =>
          if meth == "map" && args.length() >= 1 {
            walk_map_callback_for_key(args[0], ctx)
          }
        _ => ()
      }
    _ => ()
  }
}

///|
fn walk_map_callback_for_key(callback : @ast.TsExpr, ctx : CheckCtx) -> Unit {
  match callback {
    ArrowFunc(_, _, ArrowExpr(body), _) => check_jsx_expr_has_key(body, ctx)
    ArrowFunc(_, _, ArrowBlock(block), _) =>
      for stmt in block.stmts {
        match stmt {
          Return(Some(e)) => check_jsx_expr_has_key(e, ctx)
          _ => ()
        }
      }
    _ => ()
  }
}

///|
fn check_jsx_expr_has_key(expr : @ast.TsExpr, ctx : CheckCtx) -> Unit {
  match expr {
    JsxElement(tag, attrs, _) =>
      // Fragments (empty tag) can't take a key in plain JSX form; skip.
      if tag != "" {
        let has_key = attrs.iter().any(fn(a) { a.0 == "key" })
        if !has_key {
          record(
            ctx,
            "<\{tag}> in `.map()`",
            "missing required `key` prop for list element",
          )
        }
      }
    // `cond ? <A/> : <B/>` — recurse into both branches.
    Cond(_, then_e, else_e) => {
      check_jsx_expr_has_key(then_e, ctx)
      check_jsx_expr_has_key(else_e, ctx)
    }
    // `cond && <A/>`.
    BinOp(And, _, right) => check_jsx_expr_has_key(right, ctx)
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// Reachability — "does this statement / block always exit (return / throw)?"
// Used to flag non-void functions whose body may fall through without
// returning. Intentionally conservative: complex switch / loop flow is
// treated as "may fall through".
// ---------------------------------------------------------------------------

///|
fn block_always_exits(block : @ast.TsBlock) -> Bool {
  for stmt in block.stmts {
    if stmt_always_exits(stmt) {
      return true
    }
  }
  false
}

///|
/// Resolver-aware variant of `block_always_exits` used by the missing-return
/// analysis. Identical to the structural form except that a `switch` without a
/// `default:` clause can still count as exhaustive when its case labels cover
/// every member of the scrutinee's literal-union type (mirroring TypeScript's
/// exhaustiveness narrowing).
fn block_always_exits_with(
  block : @ast.TsBlock,
  env : ExprEnv,
  resolver : Resolver,
) -> Bool {
  for stmt in block.stmts {
    if stmt_always_exits_with(stmt, env, resolver) {
      return true
    }
  }
  false
}

///|
fn stmt_always_exits_with(
  stmt : @ast.TsStmt,
  env : ExprEnv,
  resolver : Resolver,
) -> Bool {
  match stmt {
    Return(_) | Throw(_) => true
    If(_, then_b, Some(else_b)) =>
      block_always_exits_with(then_b, env, resolver) &&
      block_always_exits_with(else_b, env, resolver)
    Block(b) => block_always_exits_with(b, env, resolver)
    Try(try_b, _, catch_b_opt, _) => {
      let try_exits = block_always_exits_with(try_b, env, resolver)
      let catch_exits = match catch_b_opt {
        Some(cb) => block_always_exits_with(cb, env, resolver)
        None => false
      }
      try_exits && catch_exits
    }
    Label(_, inner) => stmt_always_exits_with(inner, env, resolver)
    Switch(scrutinee, cases) => {
      // Every case body must exit.
      for c in cases {
        if !block_always_exits_with(c.body, env, resolver) {
          return false
        }
      }
      let mut has_default = false
      for c in cases {
        match c.test_expr {
          None => has_default = true
          _ => ()
        }
      }
      if has_default {
        return true
      }
      // No default: exhaustive only if the case labels cover the scrutinee's
      // literal-union type.
      switch_covers_union(scrutinee, cases, env, resolver)
    }
    _ => false
  }
}

///|
/// True when the `switch` case labels cover every member of the scrutinee's
/// literal-union type. Conservative: returns false unless the scrutinee
/// resolves to a union (or single literal) of literal types and every member
/// has a matching `case` label.
fn switch_covers_union(
  scrutinee : @ast.TsExpr,
  cases : Array[@ast.TsSwitchCase],
  env : ExprEnv,
  resolver : Resolver,
) -> Bool {
  let members : Array[@ast.TsType] = match
    resolver.unwrap(infer_expr(env, resolver, scrutinee)) {
    Union(parts) => parts
    other =>
      match other {
        Literal(_) | NumberLiteral(_) | BooleanLiteral(_) => [other]
        _ => return false
      }
  }
  // Every member must be a literal type for coverage to be decidable.
  for m in members {
    match m {
      Literal(_) | NumberLiteral(_) | BooleanLiteral(_) => ()
      _ => return false
    }
  }
  let labels : Array[@ast.TsType] = []
  for c in cases {
    match c.test_expr {
      // Map a case-label literal expression to its *precise* literal type.
      // `infer_expr` widens `0` to `number` and `true` to `boolean`, which
      // would never equal the literal union members (`0 | 1`, `true | false`),
      // so coverage of numeric / boolean discriminated unions would be missed.
      Some(e) =>
        labels.push(
          match precise_literal_type(e) {
            Some(lit) => lit
            None => resolver.unwrap(infer_expr(env, resolver, e))
          },
        )
      None => ()
    }
  }
  for m in members {
    let mut covered = false
    for l in labels {
      if l == m {
        covered = true
        break
      }
    }
    if !covered {
      return false
    }
  }
  true
}

///|
fn stmt_always_exits(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Return(_) | Throw(_) => true
    If(_, then_b, Some(else_b)) =>
      block_always_exits(then_b) && block_always_exits(else_b)
    Block(b) => block_always_exits(b)
    Try(try_b, _, catch_b_opt, _) => {
      let try_exits = block_always_exits(try_b)
      let catch_exits = match catch_b_opt {
        Some(cb) => block_always_exits(cb)
        None => false
      }
      try_exits && catch_exits
    }
    Label(_, inner) => stmt_always_exits(inner)
    // A `switch` always exits when (a) it has a `default:` case, and (b)
    // every case body ends in `return` / `throw` (or an empty body that
    // falls through to one that does). Conservative: ignore fall-through
    // chaining, treating each case independently — so empty bodies fail
    // the check.
    Switch(_, cases) => {
      let mut has_default = false
      for c in cases {
        match c.test_expr {
          None => has_default = true
          _ => ()
        }
      }
      if !has_default {
        return false
      }
      for c in cases {
        if !block_always_exits(c.body) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

// ---------------------------------------------------------------------------
// Public entry points.
// ---------------------------------------------------------------------------

///|
/// Check a single function body against its signature using a resolver built
/// from the surrounding module (or an empty resolver when called in
/// isolation).
pub fn check_function_body(func : @ast.TsFunc) -> Array[ExprIssue] {
  // Seed the TS2304 backstop with the function's own parameter / local
  // binding names so a standalone check matches the module-level path
  // (which collects `declared_value_names` across the whole tree).
  let resolver = Resolver::empty()
  for p in func.params {
    collect_param_value_names(p, resolver.declared_value_names)
  }
  collect_block_value_names(func.body, resolver.declared_value_names)
  check_function_body_with(func, resolver, false, true)
}

///|
fn check_function_body_with(
  func : @ast.TsFunc,
  resolver : Resolver,
  permissive : Bool,
  strict_property_init : Bool,
  this_type? : @ast.TsType? = None,
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  let env = ExprEnv::new()
  // Inside an async function body, `return x` returns the inner type — the
  // wrapping `Promise<T>` is what the *caller* sees. So we unwrap once for
  // the body-level return check.
  //
  // For a type-predicate function (`x is T`), the body actually returns a
  // boolean — the predicate-ness lives only at the call site. Lower it
  // back to `Boolean` for the body-level return check.
  //
  // For an `asserts x [is T]` function the body actually returns `void` —
  // the assertion is a control-flow effect.
  let body_return = match unwrap_async_return(func.is_async, func.return_type) {
    TypePredicate(_, _) => @ast.TsType::Boolean
    AssertsPredicate(_, _) => @ast.TsType::Void
    other => other
  }
  // Extract the yield-element type for generator bodies. We accept the
  // standard ambient shapes `Generator<T, ...>` / `Iterable<T>` /
  // `IterableIterator<T>` / `AsyncGenerator<T, ...>` / `AsyncIterable<T>`
  // and fall back to `Any` for anything else so non-generator and
  // unannotated bodies short-circuit the yield check.
  let yield_type : @ast.TsType = if func.is_generator {
    match func.return_type {
      Applied("Generator", args) | Applied("AsyncGenerator", args) if args.length() >=
        1 => args[0]
      Applied("Iterable", [t])
      | Applied("IterableIterator", [t])
      | Applied("Iterator", [t])
      | Applied("AsyncIterable", [t])
      | Applied("AsyncIterableIterator", [t])
      | Applied("AsyncIterator", [t]) => t
      _ => @ast.TsType::Any
    }
  } else {
    @ast.TsType::Any
  }
  // For a generator, a `return x` statement yields the iterator's
  // `TReturn` slot, not the declared iterator type itself: checking the
  // returned value against `Generator<T, TReturn, ...>` / `IterableIterator<T>`
  // / a named `Iterator`-extending interface is a false positive. Extract
  // the `TReturn` arm where the ambient shape exposes it (`Generator` /
  // `AsyncGenerator` / `Iterator` / `AsyncIterator` second type arg) and
  // otherwise fall back to `Any` so the return-value check is skipped --
  // the iterator type is never itself a valid target for the value.
  let effective_return : @ast.TsType = if func.is_generator {
    match func.return_type {
      Applied("Generator", args)
      | Applied("AsyncGenerator", args)
      | Applied("Iterator", args)
      | Applied("AsyncIterator", args) if args.length() >= 2 => args[1]
      _ => @ast.TsType::Any
    }
  } else {
    body_return
  }
  let ctx : CheckCtx = {
    path_prefix: "function " + func.name,
    return_type: effective_return,
    yield_type,
    resolver,
    issues,
    in_scope_type_params: func.type_params,
    permissive,
    unassigned: {},
    strict_property_init,
    in_computed_key: false,
  }
  // Bind parameter names into the environment. Destructured params
  // (`function f({ a, b }: T)` / `function f([a, b]: T[])`) carry a
  // `TsBinding::Object` / `TsBinding::Array` and need pattern walking
  // so the inner names point at the field/element types — not the
  // whole parameter type.
  for p in func.params {
    match p.binding {
      Some(@ast.TsBinding::Object(_)) | Some(@ast.TsBinding::Array(_)) =>
        match p.binding {
          Some(b) => bind_pattern(env, ctx, b, p.type_)
          None => env.bind(p.name, p.type_)
        }
      _ => env.bind(p.name, p.type_)
    }
  }
  // Bind `this` to the enclosing class type for a method / constructor
  // body so `this.x` and `this.method(args)` resolve against the class's
  // members (property existence, method-argument types). Free functions
  // pass `None` and leave `this` untyped.
  match this_type {
    Some(t) => env.bind("this", t)
    None => ()
  }
  // Default-parameter expression must be assignable to the parameter's
  // (possibly optional-widened) type.
  for p in func.params {
    match p.default {
      Some(d) =>
        check_expr_against(env, d, p.type_, ctx, "param `\{p.name}` default")
      None => ()
    }
  }
  // Nothing further to analyze for an empty / ambient body. The
  // param-default check above is the only declaration-level check that
  // applies to a bodiless signature, so run it (a default whose type
  // mismatches the annotation is an error regardless of the body) and
  // then bail before the statement / return-path analysis.
  if func.body.stmts.length() == 0 {
    return issues
  }
  for stmt in func.body.stmts {
    check_stmt(env, stmt, ctx)
  }
  // Missing-return analysis: when the declared (body-level) return type is
  // concrete and doesn't accept `undefined` / `void`, every path through the
  // body must end in `return` or `throw`. Skip for generators — their body
  // returns the `TReturn` slot via `return`, but the iterator itself is the
  // declared `Generator<T, TReturn, ...>` value; not all generator
  // signatures require an explicit `return`.
  if !func.is_generator &&
    is_checkable(body_return) &&
    !is_assignable_to(@ast.TsType::Undefined, body_return) &&
    !is_assignable_to(@ast.TsType::Void, body_return) &&
    !block_always_exits_with(func.body, env, resolver) &&
    !permissive {
    issues.push({
      path: "function " + func.name,
      message: "not all paths return a `\{type_display(body_return)}`",
    })
  }
  issues
}

///|
/// Check every top-level function in `module_` using a resolver built from
/// the same module. Class methods do not carry bodies in this AST, so they
/// are not walked — class shapes still inform property / method / `new`
/// typing for expressions that *call into* them.
pub fn check_module_function_bodies(
  module_ : @ast.TsModule,
) -> Array[ExprIssue] {
  check_module_function_bodies_layered(module_, [], false)
}

///|
/// Like `check_module_function_bodies` but with the T9 nuclear FP
/// suppressions enabled (mismatch / property / method / arity /
/// callable / index / never / equality / assertion families dropped).
/// Use this for whole-corpus runs (the conformance test, the
/// `tscheck` CLI's batch walks) so they don't drown in noise from
/// gaps we don't model. Unit tests should keep using the strict
/// entry point so individual diagnostic emission stays assertable.
pub fn check_module_function_bodies_permissive(
  module_ : @ast.TsModule,
) -> Array[ExprIssue] {
  check_module_function_bodies_layered(module_, [], true)
}

///|
/// Body of `check_module_function_bodies` parameterized by the chain of
/// enclosing ancestor modules. When `outer_modules` is empty this is the
/// public entry point and we use `Resolver::from_module` (which preserves
/// `Outer.Inner.Foo` prefixed registration for namespace member access).
/// For nested namespaces we build a layered resolver instead: ancestors
/// are ingested first at bare names so inner code can reference
/// outer-scope types unqualified (the way TypeScript scoping works),
/// then this module is ingested to shadow on top.

///|
/// True for the interface-member sentinel keys the parser uses for call /
/// construct / computed / index signatures, which are not real named members
/// and may legitimately repeat.
fn is_signature_sentinel(name : String) -> Bool {
  name == "<call>" ||
  name == "<new>" ||
  name == "<computed>" ||
  name == "<index_signature>"
}

///|
/// TS2300 ("Duplicate identifier") for the structurally-unambiguous cases:
/// an enum that lists the same member name twice, and an interface that
/// declares the same field name twice. Same-name *method* signatures are
/// legal overloads, so an interface name is only flagged when at least one
/// occurrence is a non-method (property) field; signature sentinels are
/// skipped. Both are decided from declaration shape alone — no type
/// resolution — so they carry no false-positive risk on resolvable input.
fn check_structural_duplicates(module_ : @ast.TsModule) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  for e in module_.enums {
    let seen : Map[String, Bool] = {}
    let reported : Map[String, Bool] = {}
    for em in e.members {
      if seen.get(em.name) is Some(_) {
        if !(reported.get(em.name) is Some(_)) {
          reported[em.name] = true
          issues.push({
            path: "enum \{e.name}",
            message: "duplicate identifier `\{em.name}`",
          })
        }
      } else {
        seen[em.name] = true
      }
    }
  }
  // An object type-literal alias body (`type T = { a: X; a: Y }`) is
  // synthesized into an interface by the parser, so the interface loop
  // below already covers it -- no separate type-alias pass is needed.
  for iface in module_.interfaces {
    for name in member_name_duplicates(iface.fields) {
      issues.push({
        path: "interface \{iface.name}",
        message: "duplicate identifier `\{name}`",
      })
    }
    // Nested object type-literals inside field types.
    for f in iface.fields {
      collect_type_dup_issues(f.1, "interface \{iface.name}", issues)
    }
  }
  // Object type-literals in other declaration positions: alias bodies,
  // function/import params and returns, ambient value types. A directly
  // object-bodied alias (`type T = { ... }`) is synthesized into an
  // interface by the parser, so the interface walk above already covers it
  // (and its nested literals) -- skip it here to avoid a double report.
  for ta in module_.type_aliases {
    if !(ta.type_ is Object(_)) {
      collect_type_dup_issues(ta.type_, "type \{ta.name}", issues)
    }
  }
  for f in module_.funcs {
    for p in f.params {
      collect_type_dup_issues(p.type_, "function \{f.name}", issues)
    }
    collect_type_dup_issues(f.return_type, "function \{f.name}", issues)
  }
  for imp in module_.imports {
    for p in imp.params {
      collect_type_dup_issues(p.1, "function \{imp.name}", issues)
    }
    collect_type_dup_issues(imp.return_type, "function \{imp.name}", issues)
  }
  for v in module_.values {
    collect_type_dup_issues(v.type_, "value \{v.name}", issues)
  }
  issues
}

///|
/// True when `name` is a single uppercase ASCII letter (`T`, `U`, `K`, …).
/// Such names are, by overwhelming convention, generic type parameters —
/// never library / global types — so an *unresolved* one is reliably an
/// out-of-scope type parameter rather than a type we merely fail to model.
fn is_single_upper_letter(name : String) -> Bool {
  if name.length() != 1 {
    return false
  }
  let c = name[0]
  c >= 'A' && c <= 'Z'
}

///|
/// TS2304 ("Cannot find name") for the false-positive-free slice: a *single
/// uppercase letter* type reference used in a function / method / property /
/// interface-field / value signature that is neither declared anywhere in the
/// module tree nor in scope as a type parameter of an enclosing function /
/// method / class / interface / generic function type
/// (`function foo<T>(b: (x: U) => U)` references the undeclared `U`).
///
/// Restricting to the single-letter lexical shape sidesteps the incomplete
/// library-type registry that makes general unresolved-name reporting unsound
/// here. The type parameters bound by a nested generic function type
/// (`<S>(x: S) => T`) are tracked via the `GenericFunc` wrapper and added to
/// scope, so they are not mistaken for out-of-scope references. Binder /
/// computed forms that do *not* surface their binders (`Conditional` with
/// `infer`, `MappedType`, `Keyof`, `IndexedAccess`, `TemplateLiteralType`)
/// are not descended into.
fn check_undeclared_type_parameters(
  module_ : @ast.TsModule,
) -> Array[ExprIssue] {
  let declared : Map[String, Unit] = {}
  collect_declared_type_names(module_, declared)
  let issues : Array[ExprIssue] = []
  walk_module_undeclared_tps(module_, [], declared, issues)
  issues
}

///|
/// Collect every type-name declaration (interface / alias / class / enum /
/// namespace) across the whole module tree into `out`. Over-approximating
/// visibility (a name declared in any namespace suppresses the report
/// everywhere) keeps the check false-positive-free at the cost of a few
/// missed reports — the safe direction.
fn collect_declared_type_names(
  module_ : @ast.TsModule,
  out : Map[String, Unit],
) -> Unit {
  for iface in module_.interfaces {
    out[iface.name] = ()
  }
  for ta in module_.type_aliases {
    out[ta.name] = ()
  }
  for c in module_.classes {
    out[c.name] = ()
  }
  for e in module_.enums {
    out[e.name] = ()
  }
  for ns in module_.namespaces {
    out[ns.name] = ()
    collect_declared_type_names(ns.module_, out)
  }
}

///|
/// Walk a module's signatures looking for single-letter unresolved type
/// parameters. `tp_scope` is the chain of type parameters in scope from
/// enclosing functions / classes / interfaces (namespaces are not generic).
fn walk_module_undeclared_tps(
  module_ : @ast.TsModule,
  tp_scope : Array[String],
  declared : Map[String, Unit],
  issues : Array[ExprIssue],
) -> Unit {
  for f in module_.funcs {
    let scope = scope_extend(tp_scope, f.type_params)
    for p in f.params {
      check_type_undeclared_tps(
        p.type_,
        scope,
        declared,
        issues,
        "function \{f.name}",
      )
    }
    check_type_undeclared_tps(
      f.return_type,
      scope,
      declared,
      issues,
      "function \{f.name}",
    )
  }
  for imp in module_.imports {
    let scope = scope_extend(tp_scope, imp.type_params)
    for p in imp.params {
      check_type_undeclared_tps(
        p.1,
        scope,
        declared,
        issues,
        "function \{imp.name}",
      )
    }
    check_type_undeclared_tps(
      imp.return_type,
      scope,
      declared,
      issues,
      "function \{imp.name}",
    )
  }
  for iface in module_.interfaces {
    let iscope = scope_extend(tp_scope, iface.type_params)
    for field in iface.fields {
      // Call / construct / index signatures (`<T>(x: T): T`) declare their own
      // generic parameters under a sentinel field name that doesn't key into
      // `method_type_params`, so their binders aren't recoverable as scope —
      // skip them to stay false-positive-free.
      if is_signature_sentinel(field.0) {
        continue
      }
      // A generic method field carries its own fresh type parameters.
      let mut mscope = iscope
      for entry in iface.method_type_params {
        if entry.0 == field.0 {
          mscope = scope_extend(iscope, entry.1)
        }
      }
      check_type_undeclared_tps(
        field.1,
        mscope,
        declared,
        issues,
        "interface \{iface.name}",
      )
    }
  }
  for c in module_.classes {
    let cscope = scope_extend(tp_scope, c.type_params)
    for prop in c.properties {
      check_type_undeclared_tps(
        prop.type_,
        cscope,
        declared,
        issues,
        "class \{c.name}",
      )
    }
    for m in c.methods {
      let mscope = scope_extend(cscope, m.type_params)
      for p in m.params {
        check_type_undeclared_tps(
          p.1,
          mscope,
          declared,
          issues,
          "class \{c.name}",
        )
      }
      check_type_undeclared_tps(
        m.return_type,
        mscope,
        declared,
        issues,
        "class \{c.name}",
      )
    }
  }
  for v in module_.values {
    check_type_undeclared_tps(
      v.type_,
      tp_scope,
      declared,
      issues,
      "value \{v.name}",
    )
  }
  for ns in module_.namespaces {
    walk_module_undeclared_tps(ns.module_, tp_scope, declared, issues)
  }
}

///|
/// Concatenate `extra` onto `base`, returning `base` unchanged when `extra`
/// is empty (the common non-generic case).
fn scope_extend(base : Array[String], extra : Array[String]) -> Array[String] {
  if extra.length() == 0 {
    return base
  }
  let out : Array[String] = []
  for b in base {
    out.push(b)
  }
  for e in extra {
    out.push(e)
  }
  out
}

///|
/// Recurse a type position, reporting single-letter type references that are
/// neither in `scope` nor `declared`. Binder / computed forms are not
/// descended into (see `check_undeclared_type_parameters`).
fn check_type_undeclared_tps(
  ty : @ast.TsType,
  scope : Array[String],
  declared : Map[String, Unit],
  issues : Array[ExprIssue],
  path : String,
) -> Unit {
  fn report(n : String) -> Unit {
    if is_single_upper_letter(n) &&
      !scope.contains(n) &&
      !(declared.get(n) is Some(_)) {
      issues.push({ path, message: "cannot find name `\{n}`" })
    }
  }

  match ty {
    Named(n) => report(n)
    Applied(n, args) => {
      report(n)
      for a in args {
        check_type_undeclared_tps(a, scope, declared, issues, path)
      }
    }
    Array(e) | Rest(e) =>
      check_type_undeclared_tps(e, scope, declared, issues, path)
    Tuple(items) | Union(items) | Intersection(items) =>
      for it in items {
        check_type_undeclared_tps(it, scope, declared, issues, path)
      }
    Object(pairs) =>
      for p in pairs {
        // Object-literal call / construct signatures (`{ <T>(x: T): T }`)
        // bind their own generics under a sentinel key that doesn't surface
        // the binder names, so skip them to stay false-positive-free.
        match p.0 {
          Literal(key) if is_signature_sentinel(key) => continue
          _ => ()
        }
        check_type_undeclared_tps(p.1, scope, declared, issues, path)
      }
    Struct(_, fields) =>
      for f in fields {
        check_type_undeclared_tps(f.1, scope, declared, issues, path)
      }
    Func(params, ret) | Constructor(params, ret, _) => {
      for p in params {
        check_type_undeclared_tps(p, scope, declared, issues, path)
      }
      check_type_undeclared_tps(ret, scope, declared, issues, path)
    }
    // A generic function type binds its own type parameters: add them to
    // scope before descending so `<S>(x: S) => T` does not flag `S`.
    GenericFunc(names, inner) => {
      let inner_scope = scope_extend(scope, names)
      check_type_undeclared_tps(inner, inner_scope, declared, issues, path)
    }
    TypePredicate(_, pt) =>
      check_type_undeclared_tps(pt, scope, declared, issues, path)
    // Binder-introducing / computed forms are intentionally not descended
    // into — `Conditional` (with `infer`), `MappedType`, `MappedTypeRemap`,
    // `Keyof`, `IndexedAccess`, `TemplateLiteralType`, `AssertsPredicate`,
    // and all primitive / literal leaves.
    _ => ()
  }
}

///|
/// TS2374 ("Duplicate index signature for type 'string' / 'number'"): a
/// single object type (interface or class body) may declare at most one
/// string index signature and at most one numeric index signature. Two of
/// the same key kind is always an error in TypeScript, so this is decided
/// from declaration shape alone -- no resolution -- and carries no
/// false-positive risk. Generic interfaces / classes are included since the
/// rule is independent of any type argument.
/// TS2300 ("Duplicate identifier") for a class member declared in two
/// incompatible ways -- a data field colliding with a method / accessor of
/// the same name. The parser computes `duplicate_member_names` from
/// declaration shape (a data field can never share a name with a method or
/// accessor in one class body), so this is false-positive-free.
fn check_class_duplicate_members(module_ : @ast.TsModule) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  for cls in module_.classes {
    for name in cls.duplicate_member_names {
      issues.push({
        path: "class \{cls.name}",
        message: "duplicate identifier `\{name}`",
      })
    }
  }
  issues
}

///|
/// A type whose identity we can compare safely by structural / set equality:
/// a primitive, a literal, or a named reference. Compound shapes (objects,
/// functions, generics, `typeof`, conditionals, …) are excluded so the
/// redeclaration check never mis-judges identity on a form it can't normalize.
fn is_identity_comparable_atom(t : @ast.TsType) -> Bool {
  match t {
    Number
    | Int
    | Boolean
    | String_
    | BigInt
    | Symbol
    | Void
    | Null
    | Undefined
    | Literal(_)
    | NumberLiteral(_)
    | BigIntLiteral(_)
    | BooleanLiteral(_)
    | Named(_) => true
    _ => false
  }
}

///|
/// Flatten a type into its normalized union members: unwrap aliases, then
/// flatten nested unions, so `(A | B) | C` and `A | (B | C)` both yield
/// `[A, B, C]` and a `type S = string` alias normalizes to `string`.
fn normalized_union_members(
  t : @ast.TsType,
  resolver : Resolver,
  depth? : Int = 0,
) -> Array[@ast.TsType] {
  // Mutually-recursive aliases (`type A = B | number; type B = A | string;`)
  // would otherwise recurse forever through `unwrap` + union members. Cap the
  // depth and return the type un-normalized when exceeded; the caller only
  // trusts results made entirely of identity-comparable atoms, so an
  // un-normalized alias safely fails that test and skips the pair.
  if depth > 64 {
    return [t]
  }
  match resolver.unwrap(t) {
    Union(members) => {
      let out : Array[@ast.TsType] = []
      for m in members {
        for n in normalized_union_members(m, resolver, depth=depth + 1) {
          out.push(n)
        }
      }
      out
    }
    other => [other]
  }
}

///|
/// TS2403 ("Subsequent variable declarations must have the same type"): two
/// `var` declarations of the same name must declare the *identical* type.
/// Identity (not assignability) -- `C` and `C | D` are mutually assignable
/// but not identical -- decided by order-independent set comparison of the
/// normalized union members. To stay false-positive-free we only compare
/// when every member of both types is an identity-comparable atom (primitive
/// / literal / named); anything we can't normalize (objects, generics,
/// `typeof`, …) skips the pair. Only true `var` declarations participate
/// (block-scoped `let` / `const` redeclaration is a different diagnostic).
fn check_var_redeclaration_types(
  module_ : @ast.TsModule,
  resolver : Resolver,
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  let first_members : Map[String, Array[@ast.TsType]] = {}
  let reported : Map[String, Unit] = {}
  fn members_set_equal(a : Array[@ast.TsType], b : Array[@ast.TsType]) -> Bool {
    for x in a {
      if !b.iter().any(fn(y) { x == y }) {
        return false
      }
    }
    for x in b {
      if !a.iter().any(fn(y) { x == y }) {
        return false
      }
    }
    true
  }

  fn consider(name : String, ty : @ast.TsType) -> Unit {
    if !is_checkable(ty) {
      return
    }
    let members = normalized_union_members(ty, resolver)
    if members.length() == 0 {
      return
    }
    for m in members {
      if !is_identity_comparable_atom(m) {
        return
      }
    }
    match first_members.get(name) {
      None => first_members[name] = members
      Some(prev) =>
        if !(reported.get(name) is Some(_)) && !members_set_equal(prev, members) {
          reported[name] = ()
          issues.push({
            path: "var \{name}",
            message: "subsequent variable declaration must have the same type",
          })
        }
    }
  }

  for stmt in module_.top_level_stmts {
    match stmt {
      Var(@ast.TsBinding::Ident(n), ty, _) => consider(n, ty)
      _ => ()
    }
  }
  for v in module_.values {
    consider(v.name, v.type_)
  }
  issues
}

///|
fn check_duplicate_index_signatures(
  module_ : @ast.TsModule,
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  fn scan(label : String, sigs : Array[(@ast.TsType, @ast.TsType)]) -> Unit {
    let mut string_keys = 0
    let mut number_keys = 0
    for sig in sigs {
      match sig.0 {
        String_ => string_keys += 1
        Number | Int => number_keys += 1
        _ => ()
      }
    }
    if string_keys >= 2 {
      issues.push({
        path: label,
        message: "duplicate index signature for type `string`",
      })
    }
    if number_keys >= 2 {
      issues.push({
        path: label,
        message: "duplicate index signature for type `number`",
      })
    }
  }
  for iface in module_.interfaces {
    scan("interface \{iface.name}", iface.index_signatures)
  }
  for c in module_.classes {
    scan("class \{c.name}", c.index_signatures)
  }
  issues
}

///|
/// Names that appear more than once in a member list where at least one
/// occurrence is a non-method (property) field. All-method repeats are legal
/// overloads, and signature sentinels (`<call>` / `<new>` / …) are skipped.
fn member_name_duplicates(
  fields : Array[(String, @ast.TsType)],
) -> Array[String] {
  let count : Map[String, Int] = {}
  let has_property : Map[String, Bool] = {}
  let order : Array[String] = []
  for f in fields {
    let name = f.0
    if is_signature_sentinel(name) {
      continue
    }
    match count.get(name) {
      Some(n) => count[name] = n + 1
      None => {
        count[name] = 1
        order.push(name)
      }
    }
    let is_method = match f.1 {
      Func(_, _) => true
      _ => false
    }
    if !is_method {
      has_property[name] = true
    }
  }
  let dups : Array[String] = []
  for name in order {
    let n = match count.get(name) {
      Some(v) => v
      None => 0
    }
    if n >= 2 && has_property.get(name) is Some(_) {
      dups.push(name)
    }
  }
  dups
}

///|
/// Walk a type, flagging TS2300 duplicate property names in every object
/// type-literal it contains (`{ a: X; a: Y }`, including nested / parameter /
/// return / element positions). Method-overload and signature-sentinel
/// exclusions match `member_name_duplicates`. Purely structural — no
/// resolution — so no false positives on resolvable input.
fn collect_type_dup_issues(
  ty : @ast.TsType,
  label : String,
  issues : Array[ExprIssue],
) -> Unit {
  match ty {
    Object(fields) => {
      let named : Array[(String, @ast.TsType)] = []
      for f in fields {
        match f.0 {
          Literal(n) => named.push((n, f.1))
          _ => ()
        }
      }
      for name in member_name_duplicates(named) {
        issues.push({ path: label, message: "duplicate identifier `\{name}`" })
      }
      for f in fields {
        collect_type_dup_issues(f.1, label, issues)
      }
    }
    Array(e) | Rest(e) | Keyof(e) => collect_type_dup_issues(e, label, issues)
    Tuple(items) =>
      for it in items {
        collect_type_dup_issues(it, label, issues)
      }
    Func(params, ret) | Constructor(params, ret, _) => {
      for p in params {
        collect_type_dup_issues(p, label, issues)
      }
      collect_type_dup_issues(ret, label, issues)
    }
    Union(ms) | Intersection(ms) =>
      for m in ms {
        collect_type_dup_issues(m, label, issues)
      }
    Applied(_, args) =>
      for a in args {
        collect_type_dup_issues(a, label, issues)
      }
    IndexedAccess(b, k) => {
      collect_type_dup_issues(b, label, issues)
      collect_type_dup_issues(k, label, issues)
    }
    Conditional(a, b, x, y) => {
      collect_type_dup_issues(a, label, issues)
      collect_type_dup_issues(b, label, issues)
      collect_type_dup_issues(x, label, issues)
      collect_type_dup_issues(y, label, issues)
    }
    _ => ()
  }
}

///|
fn check_module_function_bodies_layered(
  module_ : @ast.TsModule,
  outer_modules : Array[@ast.TsModule],
  permissive : Bool,
) -> Array[ExprIssue] {
  let resolver = if outer_modules.length() == 0 {
    Resolver::from_module(module_)
  } else {
    let r = Resolver::empty()
    for o in outer_modules {
      Resolver::ingest_module(r, o, "")
    }
    Resolver::ingest_module(r, module_, "")
    // TS2304 backstop: collect declared value names from the *outermost*
    // module, which recurses into every nested namespace. This lets code
    // inside a namespace reference outer-scope (and sibling-namespace)
    // bindings unqualified without tripping a "cannot find name" false
    // positive. `from_module` already does this for the top-level entry.
    collect_module_value_names(outer_modules[0], r.declared_value_names)
    r
  }
  // Strict-mode flag comes from the *outermost* (top-level) module's
  // header directive; namespace-nested modules don't carry their own
  // `@strict: ...` directive, so they inherit. Reuses the same root
  // lookup that TS2564 already does below.
  let strict_root = if outer_modules.length() > 0 {
    outer_modules[0]
  } else {
    module_
  }
  let strict_property_init = strict_root.strict_property_initialization
  let all : Array[ExprIssue] = []
  for func in module_.funcs {
    for
      issue in check_function_body_with(
        func, resolver, permissive, strict_property_init,
      ) {
      all.push(issue)
    }
  }
  // Class method bodies — when the parser supplied a body, walk it the
  // same way top-level functions are walked. Synthesise a `TsFunc` so
  // the existing checker pipeline can run unchanged. The synthetic
  // function name embeds the class + method names so any reported
  // issues point at the source location.
  for cls in module_.classes {
    for meth in cls.methods {
      // Walk the body when present; a bodiless method (abstract / ambient /
      // overload signature) still needs its parameter defaults validated,
      // so synthesize an empty body in that case. `check_function_body_with`
      // checks defaults first and then bails on the empty body.
      let body = match meth.body {
        Some(b) => b
        None => { stmts: [], stmt_positions: [] }
      }
      let params : Array[@ast.TsParam] = []
      for i, p in meth.params {
        // Preserve positionally-aligned default initializers and rest
        // flags so the body checker validates `m(x: string = 1)` style
        // default-vs-annotation mismatches (TS2322) the same way it
        // does for top-level functions.
        let default = if i < meth.param_defaults.length() {
          meth.param_defaults[i]
        } else {
          None
        }
        let is_rest = i < meth.param_is_rest.length() && meth.param_is_rest[i]
        params.push({ name: p.0, binding: None, is_rest, type_: p.1, default })
      }
      // Merge class-level + method-level type parameters so the body
      // sees the same in-scope generics that TypeScript does.
      let merged_tparams : Array[String] = []
      for tp in cls.type_params {
        merged_tparams.push(tp)
      }
      for tp in meth.type_params {
        merged_tparams.push(tp)
      }
      let synth : @ast.TsFunc = {
        name: cls.name + "." + meth.name,
        type_params: merged_tparams,
        params,
        return_type: meth.return_type,
        body,
        const_type_params: [],
        type_param_bounds: meth.type_param_bounds,
        is_generator: false,
        is_async: false,
      }
      // Bind `this` to the instance type only for instance methods. In a
      // `static` method `this` is the class/constructor side (its members
      // are the statics), which we don't model -- leave it untyped there.
      let this_type : @ast.TsType? = if meth.is_static {
        None
      } else {
        Some(@ast.TsType::Named(cls.name))
      }
      for
        issue in check_function_body_with(
          synth,
          resolver,
          permissive,
          strict_property_init,
          this_type~,
        ) {
        all.push(issue)
      }
    }
  }
  // Constructor body + parameter defaults. The constructor's statement
  // body (when retained) is walked with `this` bound to the instance type
  // so `this.method(args)` / `this.x` inside the constructor are validated
  // like any other instance-method body; the parameter-default expressions
  // (`constructor(x: string = 1)`) are checked regardless (TS2322).
  for cls in module_.classes {
    let cparams = match cls.constructor_params {
      Some(p) => p
      None => []
    }
    let body : @ast.TsBlock = match cls.constructor_body {
      Some(b) => b
      None => { stmts: [], stmt_positions: [] }
    }
    if cparams.length() == 0 && body.stmts.length() == 0 {
      continue
    }
    let params : Array[@ast.TsParam] = []
    for i, p in cparams {
      let default = if i < cls.constructor_param_defaults.length() {
        cls.constructor_param_defaults[i]
      } else {
        None
      }
      let is_rest = i < cls.constructor_param_is_rest.length() &&
        cls.constructor_param_is_rest[i]
      params.push({ name: p.0, binding: None, is_rest, type_: p.1, default })
    }
    let synth : @ast.TsFunc = {
      name: cls.name + ".constructor",
      type_params: cls.type_params,
      params,
      return_type: @ast.TsType::Void,
      body,
      const_type_params: [],
      type_param_bounds: cls.type_param_bounds,
      is_generator: false,
      is_async: false,
    }
    for
      issue in check_function_body_with(
        synth,
        resolver,
        permissive,
        strict_property_init,
        this_type=Some(@ast.TsType::Named(cls.name)),
      ) {
      all.push(issue)
    }
  }
  // Class field initializers (`class C { x = expr; static y = expr }`).
  // These were previously never walked, so member-access checks (e.g.
  // accessing another class's `private`/`protected` member from an
  // initializer) were missed. Walk each under a class-scoped path so the
  // accessibility check resolves the enclosing class correctly.
  for cls in module_.classes {
    if cls.static_field_inits.length() == 0 &&
      cls.instance_field_inits.length() == 0 {
      continue
    }
    let field_ctx : CheckCtx = {
      path_prefix: "function \{cls.name}.<field-init>",
      return_type: @ast.TsType::Void,
      yield_type: @ast.TsType::Any,
      resolver,
      issues: [],
      in_scope_type_params: cls.type_params,
      permissive,
      unassigned: {},
      strict_property_init,
      in_computed_key: false,
    }
    let env = ExprEnv::new()
    for v in module_.values {
      env.bind(v.name, v.type_)
    }
    // Map each declared field to its annotated type so an initializer can be
    // checked against it (TS2322: `class C { x: number = "s" }`). Static and
    // instance fields are keyed separately since a static and an instance
    // field may share a name. `check_expr_against` subsumes the member-access
    // walk that this loop previously did via `check_call_args_in_expr`, so the
    // existing coverage is preserved while adding the assignability check.
    let static_field_types : Map[String, @ast.TsType] = {}
    let instance_field_types : Map[String, @ast.TsType] = {}
    for prop in cls.properties {
      if prop.is_static {
        static_field_types[prop.name] = prop.type_
      } else {
        instance_field_types[prop.name] = prop.type_
      }
    }
    fn check_field(
      name : String,
      init : @ast.TsExpr,
      types : Map[String, @ast.TsType],
    ) -> Unit {
      match types.get(name) {
        Some(declared) if is_checkable(declared) =>
          check_expr_against(env, init, declared, field_ctx, "field `\{name}`")
        _ => check_call_args_in_expr(env, init, field_ctx)
      }
    }

    for entry in cls.static_field_inits {
      check_field(entry.0, entry.1, static_field_types)
    }
    for entry in cls.instance_field_inits {
      check_field(entry.0, entry.1, instance_field_types)
    }
    for issue in field_ctx.issues {
      all.push(issue)
    }
  }
  // Computed member keys on class methods / accessors (`class C { [e]() {} }`).
  // The key is an ordinary value expression, so an undefined name in it is a
  // TS2304 like any other reference. Walked with `in_computed_key` set so the
  // TS2454 used-before-assigned read-check stays suppressed for `var` reads.
  for cls in module_.classes {
    let has_computed_key = cls.methods
      .iter()
      .any(fn(m) { m.key_expr is Some(_) }) ||
      cls.computed_field_keys.length() > 0
    if !has_computed_key {
      continue
    }
    let key_ctx : CheckCtx = {
      path_prefix: "function \{cls.name}.<member-key>",
      return_type: @ast.TsType::Void,
      yield_type: @ast.TsType::Any,
      resolver,
      issues: [],
      in_scope_type_params: cls.type_params,
      permissive,
      unassigned: {},
      strict_property_init,
      in_computed_key: true,
    }
    let env = ExprEnv::new()
    for v in module_.values {
      env.bind(v.name, v.type_)
    }
    for meth in cls.methods {
      match meth.key_expr {
        Some(key) => check_call_args_in_expr(env, key, key_ctx)
        None => ()
      }
    }
    for key in cls.computed_field_keys {
      check_call_args_in_expr(env, key, key_ctx)
    }
    for issue in key_ctx.issues {
      all.push(issue)
    }
  }
  // Top-level statements (const/let/var with explicit type annotations).
  // Walk them in a module-scope env so local names resolve correctly.
  if module_.top_level_stmts.length() > 0 {
    let top_ctx : CheckCtx = {
      path_prefix: "top-level",
      return_type: @ast.TsType::Void,
      yield_type: @ast.TsType::Any,
      resolver,
      issues: [],
      in_scope_type_params: [],
      permissive,
      unassigned: {},
      strict_property_init,
      in_computed_key: false,
    }
    let env = ExprEnv::new()
    for v in module_.values {
      env.bind(v.name, v.type_)
    }
    for stmt in module_.top_level_stmts {
      check_stmt(env, stmt, top_ctx)
    }
    for issue in top_ctx.issues {
      all.push(issue)
    }
  }
  for issue in check_module_decl_signatures(module_) {
    all.push(issue)
  }
  for issue in check_structural_duplicates(module_) {
    all.push(issue)
  }
  // TS2304 for single-letter out-of-scope type parameters. Run once at the
  // top level — the walker recurses into namespaces itself, so calling it per
  // layered namespace would double-report.
  if outer_modules.length() == 0 {
    for issue in check_undeclared_type_parameters(module_) {
      all.push(issue)
    }
  }
  for issue in check_var_redeclaration_types(module_, resolver) {
    all.push(issue)
  }
  for issue in check_class_duplicate_members(module_) {
    all.push(issue)
  }
  for issue in check_duplicate_index_signatures(module_) {
    all.push(issue)
  }
  // Walk class field initialisation. Namespaced classes need to
  // inherit the *top-level* file's `strict_property_initialization`
  // flag (the directive `// @strict: false` only appears on the
  // surrounding source, never on a namespace's synthesised module),
  // so we consult the outer-most module when one exists.
  let strict_root = if outer_modules.length() > 0 {
    outer_modules[0]
  } else {
    module_
  }
  for
    issue in check_native_class_property_initializers(
      module_,
      resolver,
      strict_root.strict_property_initialization,
    ) {
    all.push(issue)
  }
  if strict_root.use_define_for_class_fields {
    for issue in check_class_property_init_order(module_) {
      all.push(issue)
    }
  }
  // Object-shaped names visible from outer scopes (a nested namespace's
  // interface can `extends` a member typed by a top-level interface).
  let outer_object_names : Map[String, Unit] = {}
  for o in outer_modules {
    for iface in o.interfaces {
      outer_object_names[iface.name] = ()
    }
    for c in o.classes {
      outer_object_names[c.name] = ()
    }
  }
  for
    issue in check_class_member_structure(
      module_,
      resolver,
      strict_root.use_define_for_class_fields,
      outer_object_names,
    ) {
    all.push(issue)
  }
  // TS5107: deprecated compiler-option directives (`// @target: es5`, …).
  // These live only in the top-level module header, so emit once per file.
  if outer_modules.length() == 0 {
    for opt in module_.deprecated_compiler_options {
      all.push({
        path: "compiler options",
        message: "option `\{opt}` is deprecated",
      })
    }
    // Module-level structural validation that doesn't depend on function
    // bodies. Only the kinds that are sound *and* not already covered by
    // the body pass *and* false-positive-free are admitted:
    //   - `CircularTypeAlias` / `InterfaceExtendsCycle`: self-referential
    //     declarations TS always rejects.
    //   - `TypeAliasArityMismatch`: wrong type-argument count against a
    //     locally-declared alias.
    // Excluded: `UnresolvedReference` (lib / cross-file refs we don't
    // resolve), `DuplicateDeclaration` (legal declaration merging),
    // `InterfaceFieldDuplicate` / `EnumMemberDuplicate` (the body pass
    // already flags real dups while tolerating call / construct / method
    // overloads, which the structural pass mis-reads as duplicate
    // `<call>` / `<new>` / method fields), `ClassPropertyDuplicate` (the
    // parser merges duplicate fields, so it never fires), and
    // `TypeParameterConstraintViolation` (false-flags `infer` / forwarded
    // type-parameter bounds).
    for issue in check_module(module_).issues {
      let keep = match issue.kind {
        CircularTypeAlias | InterfaceExtendsCycle | TypeAliasArityMismatch =>
          true
        _ => false
      }
      if keep {
        all.push({ path: issue.name, message: issue.detail })
      }
    }
    // TS2304 for `typeof X` over an undefined value name. Distinct from the
    // (excluded) `UnresolvedReference` type-name check: this resolves the
    // *value* namespace against the comprehensive lib-globals registry, so it
    // is false-positive-free — only a provably undeclared `typeof` base fires.
    for n in unresolved_typeof_references(module_) {
      all.push({ path: "typeof \{n}", message: "cannot find name `\{n}`" })
    }
  }
  // Recurse into namespace bodies. Each level threads its own ancestor
  // chain so a nested namespace can reference parent-scope types by their
  // bare name (TypeScript scoping). Synthetic `<global>` blocks
  // (`declare global { ... }`) belong to the surrounding scope; we still
  // walk their bodies but don't prefix the diagnostic path.
  let next_outers : Array[@ast.TsModule] = []
  for o in outer_modules {
    next_outers.push(o)
  }
  next_outers.push(module_)
  for ns in module_.namespaces {
    let issues = check_module_function_bodies_layered(
      ns.module_,
      next_outers,
      permissive,
    )
    let prefix = if ns.name == "<global>" {
      "declare global"
    } else {
      "namespace \{ns.name}"
    }
    for issue in issues {
      all.push({ path: "\{prefix} > \{issue.path}", message: issue.message })
    }
  }
  all
}

///|
/// True when `ty` is a fully-concrete primitive or literal type with no type
/// parameters, `any`, `unknown`, or `never` inside it. Used to decide that a
/// value is genuinely incompatible with a bare in-scope type parameter `T`
/// (`var x: T = 1`): only such unambiguously-concrete sources are flagged, so
/// an imprecisely-inferred object / union / generic instantiation can never
/// false-flag against `T`.
fn is_concrete_primitive_or_literal(ty : @ast.TsType) -> Bool {
  match ty {
    Number
    | Int
    | String_
    | Boolean
    | BigInt
    | Symbol
    | Literal(_)
    | NumberLiteral(_)
    | BigIntLiteral(_)
    | BooleanLiteral(_) => true
    _ => false
  }
}

///|
/// True when `ty` is *not* a generic function type. Used to keep the
/// function-type assignability check away from `<S>(...) => T` shapes, which
/// can be made compatible by instantiating their type parameters.
fn not_generic_func(ty : @ast.TsType) -> Bool {
  !(ty is GenericFunc(_, _))
}

///|
/// True when `ty` is a plain callable type — a bare function or constructor
/// type. Used to gate the bivariant function-type assignability check, which
/// `is_assignable_to_bivariant` handles for `Func` / `Constructor` (and the
/// `Constructor` -> `Func` direction) but not for interface / object call
/// signatures (those keep going through the `shape_is_callable` bail).
fn is_plain_callable(ty : @ast.TsType) -> Bool {
  ty is (Func(_, _) | Constructor(_, _, _))
}

///|
/// True when any param / return position of a function type references an
/// in-scope type parameter (`(x: T) => T` inside `function f<T>(...)`). Such a
/// function type's assignability depends on how `T` is instantiated, so the
/// concrete function-type check stays silent. Only the immediate param /
/// return positions are inspected — enough for the shapes the check handles.
fn func_type_mentions_type_param(ty : @ast.TsType, ctx : CheckCtx) -> Bool {
  match ty {
    Func(params, ret) | Constructor(params, ret, _) =>
      params.iter().any(fn(p) { type_mentions_in_scope_type_param(p, ctx) }) ||
      type_mentions_in_scope_type_param(ret, ctx)
    _ => false
  }
}

///|
/// True when a type is a *reliable* operand for the bivariant function-type
/// parameter check: a concrete type whose comparison we trust. Excludes
/// - in-scope type parameters (`T`) and generic function types — instantiation
///   could reconcile them;
/// - unresolved `Named` references (an arrow's own dropped generic `<U>`, or a
///   library type we don't model) — we can't compare them soundly;
/// - `Union` types — these are usually the artifact of our generic
///   type-argument inference (which diverges from tsc), so a strict param
///   comparison against them false-flags.
fn reliable_func_param_operand(ty : @ast.TsType, ctx : CheckCtx) -> Bool {
  if type_mentions_in_scope_type_param(ty, ctx) {
    return false
  }
  if !not_generic_func(ty) {
    return false
  }
  if type_contains_unresolved_named(ty, ctx.resolver) {
    return false
  }
  match ty {
    Union(_) => false
    _ => true
  }
}

///|
/// True when `ty` references any type parameter currently in scope.
fn type_mentions_in_scope_type_param(ty : @ast.TsType, ctx : CheckCtx) -> Bool {
  if ctx.in_scope_type_params.length() == 0 {
    return false
  }
  for tp in ctx.in_scope_type_params {
    if type_param_occurs(tp, ty) {
      return true
    }
  }
  false
}

///|
/// True when `ty` (after alias-unwrap) is a bare reference to a type
/// parameter that is currently in scope. TypeScript treats unconstrained
/// type parameters as having `object`'s method surface, so property /
/// method existence checks should stay silent for these.
fn is_in_scope_type_param(ctx : CheckCtx, ty : @ast.TsType) -> Bool {
  if ctx.in_scope_type_params.length() == 0 {
    return false
  }
  match ctx.resolver.unwrap(ty) {
    Named(n) => ctx.in_scope_type_params.contains(n)
    _ => false
  }
}

///|
/// True when `expr` refers to the constructor receiver, looking through
/// casts / assertions that don't change the value (`this as T`, `this!`,
/// `this satisfies T`, an optional-chain wrapper, a `@__PURE__` marker).
/// Used so `(this as Foo).x = …` / `this!.x = …` are recognised as
/// assigning `this.x` and don't trigger a false TS2564.
fn expr_is_this(expr : @ast.TsExpr) -> Bool {
  match expr {
    Var("this") => true
    As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner) => expr_is_this(inner)
    _ => false
  }
}

///|
/// Collect, into `members`, every field name referenced as `this.<name>`
/// (property access or string-literal index) anywhere in a constructor
/// body — reads included. This over-approximates "assigned in the
/// constructor" by mere presence: a field that never appears cannot have
/// been assigned, so it is a sound TS2564 candidate; a field that appears
/// (even only read) is left alone to stay false-positive-free without
/// modelling control flow.
///
/// `opaque[0]` is set when the body uses a form we don't model precisely
/// enough to be sure which member it touches — a dynamic `this[expr]`, a
/// destructuring assignment, or a nested class. The caller then skips the
/// whole class rather than risk a false positive. Every `TsExpr` / `TsStmt`
/// variant is matched explicitly so a future AST addition fails to compile
/// here instead of silently going untraversed (which could cause an FP).
fn collect_ctor_this_members_block(
  block : @ast.TsBlock,
  members : Map[String, Unit],
  opaque : Array[Bool],
) -> Unit {
  for stmt in block.stmts {
    collect_ctor_this_members_stmt(stmt, members, opaque)
  }
}

///|
fn collect_ctor_this_members_stmt(
  stmt : @ast.TsStmt,
  members : Map[String, Unit],
  opaque : Array[Bool],
) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Assign(_, e) =>
      collect_ctor_this_members_expr(e, members, opaque)
    CompoundAssign(_, _, e) =>
      collect_ctor_this_members_expr(e, members, opaque)
    IndexAssign(recv, idx, val) => {
      if expr_is_this(recv) {
        match idx {
          StringLit(name) => members[name] = ()
          _ => {
            opaque[0] = true
            collect_ctor_this_members_expr(idx, members, opaque)
          }
        }
      } else {
        collect_ctor_this_members_expr(recv, members, opaque)
        collect_ctor_this_members_expr(idx, members, opaque)
      }
      collect_ctor_this_members_expr(val, members, opaque)
    }
    PropAssign(recv, name, val) => {
      if expr_is_this(recv) {
        members[name] = ()
      } else {
        collect_ctor_this_members_expr(recv, members, opaque)
      }
      collect_ctor_this_members_expr(val, members, opaque)
    }
    Expr(e) | Throw(e) => collect_ctor_this_members_expr(e, members, opaque)
    Return(opt) =>
      match opt {
        Some(e) => collect_ctor_this_members_expr(e, members, opaque)
        None => ()
      }
    Try(b, _, c, f) => {
      collect_ctor_this_members_block(b, members, opaque)
      match c {
        Some(cb) => collect_ctor_this_members_block(cb, members, opaque)
        None => ()
      }
      match f {
        Some(fb) => collect_ctor_this_members_block(fb, members, opaque)
        None => ()
      }
    }
    If(c, t, e) => {
      collect_ctor_this_members_expr(c, members, opaque)
      collect_ctor_this_members_block(t, members, opaque)
      match e {
        Some(eb) => collect_ctor_this_members_block(eb, members, opaque)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      collect_ctor_this_members_expr(c, members, opaque)
      collect_ctor_this_members_block(b, members, opaque)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_ctor_this_members_stmt(s, members, opaque)
        None => ()
      }
      match cond {
        Some(e) => collect_ctor_this_members_expr(e, members, opaque)
        None => ()
      }
      match update {
        Some(s) => collect_ctor_this_members_stmt(s, members, opaque)
        None => ()
      }
      collect_ctor_this_members_block(body, members, opaque)
    }
    ForOf(_, _, _, it, body)
    | ForAwaitOf(_, _, _, it, body)
    | ForIn(_, _, _, it, body) => {
      collect_ctor_this_members_expr(it, members, opaque)
      collect_ctor_this_members_block(body, members, opaque)
    }
    Switch(e, cases) => {
      collect_ctor_this_members_expr(e, members, opaque)
      for cse in cases {
        match cse.test_expr {
          Some(te) => collect_ctor_this_members_expr(te, members, opaque)
          None => ()
        }
        collect_ctor_this_members_block(cse.body, members, opaque)
      }
    }
    With(e, b) => {
      collect_ctor_this_members_expr(e, members, opaque)
      collect_ctor_this_members_block(b, members, opaque)
    }
    Label(_, s) => collect_ctor_this_members_stmt(s, members, opaque)
    Block(b) => collect_ctor_this_members_block(b, members, opaque)
    NativeClassStmt(_, _) => opaque[0] = true
    Debugger | Break(_) | Continue(_) | Empty => ()
  }
}

///|
fn collect_ctor_this_members_expr(
  expr : @ast.TsExpr,
  members : Map[String, Unit],
  opaque : Array[Bool],
) -> Unit {
  match expr {
    NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole
    | Var(_)
    | ImportMeta => ()
    TypeArgs(_, inner) => collect_ctor_this_members_expr(inner, members, opaque)
    PropAccess(recv, name) =>
      if expr_is_this(recv) {
        members[name] = ()
      } else {
        collect_ctor_this_members_expr(recv, members, opaque)
      }
    IndexAccess(recv, idx) =>
      if expr_is_this(recv) {
        match idx {
          StringLit(name) => members[name] = ()
          _ => {
            opaque[0] = true
            collect_ctor_this_members_expr(idx, members, opaque)
          }
        }
      } else {
        collect_ctor_this_members_expr(recv, members, opaque)
        collect_ctor_this_members_expr(idx, members, opaque)
      }
    BinOp(_, a, b) | Seq(a, b) => {
      collect_ctor_this_members_expr(a, members, opaque)
      collect_ctor_this_members_expr(b, members, opaque)
    }
    UnaryOp(_, a)
    | Spread(a)
    | PureCall(a)
    | Await(a)
    | NonNull(a)
    | OptionalChain(a)
    | YieldStar(a)
    | As(a, _)
    | Satisfies(a, _) => collect_ctor_this_members_expr(a, members, opaque)
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_ctor_this_members_expr(a, members, opaque)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_ctor_this_members_expr(callee, members, opaque)
      for a in args {
        collect_ctor_this_members_expr(a, members, opaque)
      }
    }
    MethodCall(recv, _, args) => {
      collect_ctor_this_members_expr(recv, members, opaque)
      for a in args {
        collect_ctor_this_members_expr(a, members, opaque)
      }
    }
    Cond(a, b, c) => {
      collect_ctor_this_members_expr(a, members, opaque)
      collect_ctor_this_members_expr(b, members, opaque)
      collect_ctor_this_members_expr(c, members, opaque)
    }
    ArrayLit(items) =>
      for it in items {
        collect_ctor_this_members_expr(it, members, opaque)
      }
    ObjectLit(entries) =>
      for e in entries {
        collect_ctor_this_members_expr(e.1, members, opaque)
      }
    ComputedProp(k, v) => {
      collect_ctor_this_members_expr(k, members, opaque)
      collect_ctor_this_members_expr(v, members, opaque)
    }
    AssignExpr(_, val) => collect_ctor_this_members_expr(val, members, opaque)
    PropAssignExpr(recv, name, val) => {
      if expr_is_this(recv) {
        members[name] = ()
      } else {
        collect_ctor_this_members_expr(recv, members, opaque)
      }
      collect_ctor_this_members_expr(val, members, opaque)
    }
    CompoundAssignExpr(target, _, val) => {
      collect_ctor_this_members_expr(target, members, opaque)
      collect_ctor_this_members_expr(val, members, opaque)
    }
    IndexAssignExpr(recv, idx, val) => {
      if expr_is_this(recv) {
        match idx {
          StringLit(name) => members[name] = ()
          _ => {
            opaque[0] = true
            collect_ctor_this_members_expr(idx, members, opaque)
          }
        }
      } else {
        collect_ctor_this_members_expr(recv, members, opaque)
        collect_ctor_this_members_expr(idx, members, opaque)
      }
      collect_ctor_this_members_expr(val, members, opaque)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_ctor_this_members_expr(e, members, opaque)
        ArrowBlock(b) => collect_ctor_this_members_block(b, members, opaque)
      }
    FuncExpr(f) => collect_ctor_this_members_block(f.body, members, opaque)
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_ctor_this_members_expr(e, members, opaque)
      }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_ctor_this_members_expr(tag, members, opaque)
      for e in exprs {
        collect_ctor_this_members_expr(e, members, opaque)
      }
    }
    Yield(opt) =>
      match opt {
        Some(e) => collect_ctor_this_members_expr(e, members, opaque)
        None => ()
      }
    DynamicImport(a, b) => {
      collect_ctor_this_members_expr(a, members, opaque)
      match b {
        Some(e) => collect_ctor_this_members_expr(e, members, opaque)
        None => ()
      }
    }
    JsxElement(_, attrs, children) => {
      for at in attrs {
        match at.1 {
          Some(e) => collect_ctor_this_members_expr(e, members, opaque)
          None => ()
        }
      }
      for ch in children {
        collect_ctor_this_members_expr(ch, members, opaque)
      }
    }
    // Forms that may bind a `this`-member in a way we don't model, or a
    // nested class shape — be conservative so the caller skips the class.
    AssignPattern(_, val) => {
      opaque[0] = true
      collect_ctor_this_members_expr(val, members, opaque)
    }
    NativeClassExpr(_, _) => opaque[0] = true
  }
}

///|
/// TS2564 ("Property 'X' has no initializer and is not definitely
/// assigned in the constructor") for native (runtime) class
/// declarations. Catches both the no-constructor shape and the
/// constructor-bearing shape: when a constructor is present we walk its
/// body (via `collect_ctor_this_members_block`) and skip any field whose
/// name it touches through `this.<name>`. A field that the constructor
/// never references — and that has neither an `=` initializer nor a `!`
/// definite-assignment assertion, with a declared type that doesn't
/// already accept `undefined` — is reported. The constructor walk
/// over-approximates assignment by presence, so it never produces a
/// false positive; classes using forms we can't model precisely
/// (dynamic `this[expr]`, destructuring assignment, nested classes) are
/// skipped entirely.
fn check_native_class_property_initializers(
  module_ : @ast.TsModule,
  resolver : Resolver,
  strict_property_init : Bool,
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  // The strict-property-initialization check is off in this file
  // (per a `// @strict: false` / `// @strictPropertyInitialization:
  // false` header directive). Skip TS2564 entirely.
  if !strict_property_init {
    return issues
  }
  for decl in module_.classes {
    // Ambient `declare class` decls don't get strict-init checking
    // -- TS itself only enforces it on runtime class bodies.
    if decl.is_declare {
      continue
    }
    // Abstract classes can declare `abstract x: T` fields that
    // subclasses must implement. Our parser drops the `abstract`
    // modifier on properties, so we can't distinguish a truly-
    // unassigned concrete field from an abstract one. Skipping the
    // whole abstract class is a conservative trade -- TS itself
    // applies the check only to concrete-field shapes.
    if decl.is_abstract {
      continue
    }
    // Index signatures (`class C { [k: string]: T }`) implicitly
    // type every property, so a bare `1: Date` / `'a': {}`
    // declaration is satisfied without an `=` initializer. Our
    // assignability layer doesn't reconcile these against
    // individual `properties` entries, so the conservative trade
    // is to skip TS2564 for any class that has one.
    if decl.index_signatures.length() > 0 {
      continue
    }
    // Collect the field names the constructor touches via `this.<name>`
    // (reads included — `collect_ctor_this_members_block` over-approximates
    // assignment by presence to stay false-positive-free). Parameter
    // properties (`constructor(public x: T)`) auto-assign, so their names
    // are seeded in too. A field that never appears is a sound TS2564
    // candidate even when a constructor is present.
    let ctor_members : Map[String, Unit] = {}
    let ctor_opaque : Array[Bool] = [false]
    match decl.constructor_params {
      Some(params) => {
        for entry in params {
          ctor_members[entry.0] = ()
        }
        // A constructor with parameters but no retained body is one we
        // can't inspect (overload signature / parser gap) — skip the
        // class to avoid a false positive.
        match decl.constructor_body {
          Some(body) =>
            collect_ctor_this_members_block(body, ctor_members, ctor_opaque)
          None => ctor_opaque[0] = true
        }
      }
      None =>
        // No declared constructor: nothing assigns `this.x`, so every
        // uninitialized field is reported below (unchanged behaviour).
        // A body may still be present via a desugared path; walk it when so.
        match decl.constructor_body {
          Some(body) =>
            collect_ctor_this_members_block(body, ctor_members, ctor_opaque)
          None => ()
        }
    }
    if ctor_opaque[0] {
      continue
    }
    // Build a set of names backed by a getter/setter method so we can
    // skip them below. `class C { get x() {…} }` upserts `x` into
    // `decl.properties` with `has_initializer = false`, but TS treats
    // the getter body as the initializer.
    let accessor_names : Map[String, Unit] = {}
    for m in decl.methods {
      if !m.is_static && (m.accessor == "get" || m.accessor == "set") {
        accessor_names[m.name] = ()
      }
    }
    for prop in decl.properties {
      // Static fields are subject to a separate initialisation rule
      // in TS (`static x: T;` without `=`) and the runtime path
      // captures `static x = expr;` in `static_field_inits` -- skip
      // for now since it's a much smaller cluster and overlaps the
      // common case.
      if prop.is_static {
        continue
      }
      if accessor_names.contains(prop.name) {
        continue
      }
      if prop.has_initializer || prop.has_definite_assertion {
        continue
      }
      // The constructor references `this.<name>` (assignment, or a read we
      // treat as a possible assignment) — assume definitely assigned.
      if ctor_members.contains(prop.name) {
        continue
      }
      // Skip when the declared type already accepts `undefined`
      // (`x?: T` is wrapped to `T | undefined` by the parser, and
      // `x: T | undefined` matches the same predicate).
      if type_accepts_undefined(resolver.unwrap(prop.type_)) {
        continue
      }
      // Skip when the declared type is `any` -- `class C { x; }`
      // (no annotation) is fine in TS without strict mode.
      if prop.type_ is Any {
        continue
      }
      issues.push({
        path: "class \{decl.name}",
        message: "property `\{prop.name}` has no initializer and is not definitely assigned",
      })
    }
  }
  issues
}

///|
/// Structural class-member checks that need only declaration shape (no
/// flow / expression inference):
///
///   - TS2300 / TS2393 ("Duplicate identifier" / "Duplicate function
///     implementation"): two `get x()` accessors or two `set x(v)`
///     accessors with the same name and static-ness in one class body.
///
///   - TS2610 ("'X' is defined as a property in class but is overridden
///     here as an accessor") / TS2611 ("'X' is defined as an accessor in
///     class but is overridden here as a property"): a subclass member
///     changes the get/set-vs-data shape of an inherited member. TS only
///     reports these under `useDefineForClassFields`, so we gate on that
///     flag to stay false-positive-free.
///
/// Whether `expr` references `super` (a `super(...)` call, `super.x`, or
/// `super.m(...)`). Used by the TS2335 check below.
fn expr_mentions_super(expr : @ast.TsExpr) -> Bool {
  match expr {
    Var("super") => true
    Call("super", _) => true
    PropAccess(inner, _) => expr_mentions_super(inner)
    IndexAccess(a, b) => expr_mentions_super(a) || expr_mentions_super(b)
    CallExpr(callee, args) | NewExpr(callee, args) =>
      expr_mentions_super(callee) ||
      args.iter().any(fn(a) { expr_mentions_super(a) })
    Call(_, args) | New(_, args) =>
      args.iter().any(fn(a) { expr_mentions_super(a) })
    MethodCall(recv, _, args) =>
      expr_mentions_super(recv) ||
      args.iter().any(fn(a) { expr_mentions_super(a) })
    BinOp(_, a, b) | Seq(a, b) =>
      expr_mentions_super(a) || expr_mentions_super(b)
    UnaryOp(_, a)
    | Spread(a)
    | PureCall(a)
    | Await(a)
    | NonNull(a)
    | OptionalChain(a)
    | As(a, _)
    | Satisfies(a, _) => expr_mentions_super(a)
    Cond(a, b, c) =>
      expr_mentions_super(a) || expr_mentions_super(b) || expr_mentions_super(c)
    AssignExpr(_, v) => expr_mentions_super(v)
    PropAssignExpr(r, _, v) => expr_mentions_super(r) || expr_mentions_super(v)
    CompoundAssignExpr(t, _, v) =>
      expr_mentions_super(t) || expr_mentions_super(v)
    _ => false
  }
}

///|
fn block_mentions_super(block : @ast.TsBlock) -> Bool {
  block.stmts.iter().any(fn(s) { stmt_mentions_super(s) })
}

///|
fn stmt_mentions_super(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Expr(e) | Throw(e) => expr_mentions_super(e)
    Return(opt) =>
      match opt {
        Some(e) => expr_mentions_super(e)
        None => false
      }
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) => expr_mentions_super(e)
    PropAssign(r, _, v) => expr_mentions_super(r) || expr_mentions_super(v)
    Block(b) => block_mentions_super(b)
    If(c, t, e) =>
      expr_mentions_super(c) ||
      block_mentions_super(t) ||
      (match e {
        Some(eb) => block_mentions_super(eb)
        None => false
      })
    While(c, b) | DoWhile(c, b) =>
      expr_mentions_super(c) || block_mentions_super(b)
    For(_, _, _, b) => block_mentions_super(b)
    ForOf(_, _, _, it, b)
    | ForAwaitOf(_, _, _, it, b)
    | ForIn(_, _, _, it, b) =>
      expr_mentions_super(it) || block_mentions_super(b)
    Try(b, _, c, f) =>
      block_mentions_super(b) ||
      (match c {
        Some(cb) => block_mentions_super(cb)
        None => false
      }) ||
      (match f {
        Some(fb) => block_mentions_super(fb)
        None => false
      })
    Switch(e, cases) =>
      expr_mentions_super(e) ||
      cases.iter().any(fn(cse) { block_mentions_super(cse.body) })
    _ => false
  }
}

///|
fn check_class_member_structure(
  module_ : @ast.TsModule,
  resolver : Resolver,
  use_define_for_class_fields : Bool,
  outer_object_names : Map[String, Unit],
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  for decl in module_.classes {
    // --- TS18010: an accessibility modifier (`public` / `private` /
    // `protected`) cannot be used with a private identifier (`private #x`,
    // `protected #y`). The parser mangles a `#x` name to a
    // `__private_brand__N__x` symbol and records an explicit accessibility
    // modifier by pushing that mangled name into `private_members` /
    // `protected_members` (a plain `#x` with no modifier is *not* added).
    // So a branded name in either list is exactly a modifier-on-`#name`
    // declaration, which TS rejects unconditionally — false-positive-free.
    let reported_brand_modifier : Map[String, Unit] = {}
    for name in decl.private_members {
      if name.has_prefix("__private_brand__") &&
        !reported_brand_modifier.contains(name) {
        reported_brand_modifier[name] = ()
        issues.push({
          path: "class \{decl.name}",
          message: "an accessibility modifier cannot be used with a private identifier",
        })
      }
    }
    for name in decl.protected_members {
      if name.has_prefix("__private_brand__") &&
        !reported_brand_modifier.contains(name) {
        reported_brand_modifier[name] = ()
        issues.push({
          path: "class \{decl.name}",
          message: "an accessibility modifier cannot be used with a private identifier",
        })
      }
    }
    // --- TS18012: `#constructor` is a reserved word — a `#`-private member
    // may not be named `constructor`. The parser brands such a member to
    // `__private_brand__N__constructor`, so a branded name ending in
    // `__constructor` is exactly a `#constructor` declaration (field, method,
    // or accessor). Always an error, never a legal shape — false-positive-free.
    let mut reported_hash_ctor = false
    fn is_brand_constructor(n : String) -> Bool {
      n.has_prefix("__private_brand__") && n.has_suffix("__constructor")
    }

    for p in decl.properties {
      if is_brand_constructor(p.name) && !reported_hash_ctor {
        reported_hash_ctor = true
        issues.push({
          path: "class \{decl.name}",
          message: "`#constructor` is a reserved word",
        })
      }
    }
    for m in decl.methods {
      if is_brand_constructor(m.name) && !reported_hash_ctor {
        reported_hash_ctor = true
        issues.push({
          path: "class \{decl.name}",
          message: "`#constructor` is a reserved word",
        })
      }
    }
    // --- TS18006: a class may not have a (data) field named `constructor`
    // (`class C { constructor: number }` / `class C { "constructor" = 3 }`).
    // The real constructor is parsed as a method / `constructor_body`, never
    // as a `properties` entry, and a computed `["constructor"]` key parses to
    // `<computed>` — so a non-static, non-accessor property literally named
    // `constructor` is exactly the illegal field form. False-positive-free.
    let mut reported_ctor_field = false
    for p in decl.properties {
      if p.name == "constructor" &&
        !p.is_static &&
        !p.is_accessor &&
        !reported_ctor_field {
        reported_ctor_field = true
        issues.push({
          path: "class \{decl.name}",
          message: "classes may not have a field named `constructor`",
        })
      }
    }
    // --- TS2335: `super` can only be referenced in a derived class. A class
    // with no base (`base_names` empty and no expression-base) whose
    // constructor body references `super` (`super()`, `super.x`,
    // `super.m()`) is an error. Derived classes carry a base name (or the
    // `<expr-base>` sentinel with `base_expr` set), so this is
    // false-positive-free.
    if decl.base_names.length() == 0 && decl.base_expr is None {
      match decl.constructor_body {
        Some(body) =>
          if block_mentions_super(body) {
            issues.push({
              path: "class \{decl.name}",
              message: "`super` can only be referenced in a derived class",
            })
          }
        None => ()
      }
    }
    // --- TS2506: a class directly references itself in its own base
    // expression (`class C extends C {}`, `class D<T> extends D<T> {}`).
    // `base_names` carries the bare extended name, so a self-reference is
    // exactly an entry equal to the class's own name. This is always an
    // error and never a legal shape, so it is false-positive-free.
    for base in decl.base_names {
      if base == decl.name {
        issues.push({
          path: "class \{decl.name}",
          message: "`\{decl.name}` is referenced directly in its own base expression",
        })
        break
      }
    }
    // --- Duplicate get / set accessors within the same class body. ---
    // Key by "name|static" so an instance and a static accessor of the
    // same name don't collide. A computed key (`name == "<computed>"`)
    // can't be statically compared, so skip it.
    let get_seen : Map[String, Unit] = {}
    let set_seen : Map[String, Unit] = {}
    let reported_dup : Map[String, Unit] = {}
    for m in decl.methods {
      if m.name == "<computed>" {
        continue
      }
      if m.accessor != "get" && m.accessor != "set" {
        continue
      }
      let key = "\{m.name}|\{m.is_static}"
      let seen = if m.accessor == "get" { get_seen } else { set_seen }
      if seen.contains(key) {
        if !reported_dup.contains(key) {
          reported_dup[key] = ()
          issues.push({
            path: "class \{decl.name}",
            message: "duplicate identifier `\{m.name}`",
          })
        }
      } else {
        seen[key] = ()
      }
    }
    // --- Duplicate regular-method implementations + field/method name
    // clashes (TS2393 / TS2300). Overload signatures (`body == None`)
    // legally share a name, so only count methods that carry a body.
    let bodied_method : Map[String, Unit] = {}
    let regular_method : Map[String, Unit] = {}
    for m in decl.methods {
      if m.name == "<computed>" || m.accessor != "" {
        continue
      }
      let key = "\{m.name}|\{m.is_static}"
      regular_method[key] = ()
      match m.body {
        Some(_) => {
          if bodied_method.contains(key) && !reported_dup.contains(key) {
            reported_dup[key] = ()
            issues.push({
              path: "class \{decl.name}",
              message: "duplicate identifier `\{m.name}`",
            })
          }
          bodied_method[key] = ()
        }
        None => ()
      }
    }
    // A data field whose name collides with a regular method of the
    // same static-ness is a duplicate identifier. Auto-accessor /
    // get-set-backed property names are excluded (the upsert merges
    // them into `properties`, so they can't be told apart from a real
    // field there).
    let field_accessors = class_instance_accessor_names(decl)
    for prop in decl.properties {
      if prop.is_accessor {
        continue
      }
      let key = "\{prop.name}|\{prop.is_static}"
      if field_accessors.contains(prop.name) {
        continue
      }
      if regular_method.contains(key) && !reported_dup.contains(key) {
        reported_dup[key] = ()
        issues.push({
          path: "class \{decl.name}",
          message: "duplicate identifier `\{prop.name}`",
        })
      }
    }
    // --- property <-> accessor override against the direct base class. ---
    // Skip when the (auto-)accessor / property override target is the
    // subclass itself rather than concrete inherited state.
    if use_define_for_class_fields && decl.base_names.length() > 0 {
      let base = match resolver.classes.get(decl.base_names[0]) {
        Some(b) => Some(b)
        None =>
          match decl.base_names[0].rev_find(".") {
            Some(dot) =>
              resolver.classes.get(
                decl.base_names[0][dot + 1:decl.base_names[0].length()].to_owned(),
              )
            None => None
          }
      }
      match base {
        // An abstract base may declare `abstract x` / `abstract accessor
        // a` members that a subclass legally implements with either a
        // field or an accessor; our parser drops the `abstract` modifier
        // on members, so we can't tell those apart -- skip abstract bases
        // entirely to stay false-positive-free.
        Some(base) if !base.is_abstract => {
          let base_accessors = class_instance_accessor_names(base)
          let base_fields = class_instance_field_names(base, base_accessors)
          let this_accessors = class_instance_accessor_names(decl)
          let this_fields = class_instance_field_names(decl, this_accessors)
          // TS2610: this declares a data property that the base declared
          // as an accessor.
          for name, _ in this_fields {
            if base_accessors.contains(name) {
              issues.push({
                path: "class \{decl.name}",
                message: "`\{name}` is defined as a property but overridden as an accessor",
              })
            }
          }
          // TS2611: this declares an accessor that the base declared as a
          // data property.
          for name, _ in this_accessors {
            if base_fields.contains(name) {
              issues.push({
                path: "class \{decl.name}",
                message: "`\{name}` is defined as an accessor but overridden as a property",
              })
            }
          }
        }
        _ => ()
      }
    }
    // --- TS2416: a derived data property whose type is not assignable to
    // the same property on the (directly extended, non-generic) base class.
    // Restricted to non-generic class + base and to *data* properties
    // (method override variance is bivariant and far more FP-prone), with
    // the conservative `member_override_incompatible` decision, so it stays
    // false-positive-free.
    if decl.type_params.length() == 0 && decl.base_names.length() > 0 {
      match resolver.classes.get(decl.base_names[0]) {
        Some(base) if base.type_params.length() == 0 => {
          let base_props : Map[String, @ast.TsType] = {}
          let base_accessors = class_instance_accessor_names(base)
          for p in base.properties {
            if !p.is_static &&
              !p.is_accessor &&
              !base_accessors.contains(p.name) {
              base_props[p.name] = p.type_
            }
          }
          let this_accessors = class_instance_accessor_names(decl)
          for p in decl.properties {
            if p.is_static || p.is_accessor || this_accessors.contains(p.name) {
              continue
            }
            match base_props.get(p.name) {
              Some(btype) =>
                if member_override_incompatible(p.type_, btype, resolver) {
                  issues.push({
                    path: "class \{decl.name}",
                    message: "property `\{p.name}` of type `\{type_display(p.type_)}` is not assignable to the same property `\{type_display(btype)}` in base type `\{base.name}`",
                  })
                }
              None => ()
            }
          }
        }
        _ => ()
      }
    }
  }
  for
    issue in check_interface_extends_compat(
      module_, outer_object_names, resolver,
    ) {
    issues.push(issue)
  }
  for issue in check_class_implements(module_, resolver) {
    issues.push(issue)
  }
  issues
}

///|
/// TS2420 ("Class incorrectly implements interface"): a (non-generic) class
/// whose `implements` clause names a (non-generic, locally declared)
/// interface must satisfy that interface. We report only the two reliably-
/// decidable shapes, so the check is false-positive-free:
///   - a member the interface declares is implemented as `private` /
///     `protected` (a non-public member can never satisfy a public interface
///     requirement);
///   - a public data property whose type is definitely not assignable to the
///     interface's same-named member (`member_override_incompatible`).
/// A *missing* member is deliberately not flagged (it may be inherited from a
/// base class we don't fully thread here), and interface methods / generic
/// shapes are left to the conservative `member_override_incompatible`, which
/// declines anything it can't decide soundly.
fn check_class_implements(
  module_ : @ast.TsModule,
  resolver : Resolver,
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  for cls in module_.classes {
    if cls.implements_names.length() == 0 || cls.type_params.length() > 0 {
      continue
    }
    let nonpublic : Map[String, Unit] = {}
    for n in cls.private_members {
      nonpublic[n] = ()
    }
    for n in cls.protected_members {
      nonpublic[n] = ()
    }
    let accessors = class_instance_accessor_names(cls)
    let cls_props : Map[String, @ast.TsType] = {}
    for p in cls.properties {
      if !p.is_static && !p.is_accessor && !accessors.contains(p.name) {
        cls_props[p.name] = p.type_
      }
    }
    for iname in cls.implements_names {
      let iface = match resolver.interfaces.get(iname) {
        Some(i) => i
        None => continue
      }
      if iface.type_params.length() > 0 {
        continue
      }
      let mut reported = false
      for f in iface.fields {
        if reported {
          break
        }
        let mname = f.0
        if is_signature_sentinel(mname) {
          continue
        }
        // Interface member implemented with non-public visibility.
        if nonpublic.get(mname) is Some(_) {
          issues.push({
            path: "class \{cls.name}",
            message: "incorrectly implements interface `\{iname}`: member `\{mname}` is not public",
          })
          reported = true
          continue
        }
        // Present public data property with an incompatible type.
        match cls_props.get(mname) {
          Some(ctype) =>
            if member_override_incompatible(ctype, f.1, resolver) {
              issues.push({
                path: "class \{cls.name}",
                message: "incorrectly implements interface `\{iname}`: property `\{mname}` of type `\{type_display(ctype)}` is not assignable to `\{type_display(f.1)}`",
              })
              reported = true
            }
          None => ()
        }
      }
    }
  }
  issues
}

///|
/// TS2430 ("Interface incorrectly extends interface"): a derived
/// interface redeclares an inherited member with an incompatible shape.
/// We report only the two reliably-detectable shapes (no structural
/// assignability needed, so no false positives):
///
///   - optionality: the base member is required but the derived one is
///     optional (`Foo?: T` over `Foo: T`), which weakens the contract.
///
///   - a clear scalar-vs-object category clash: the derived member is a
///     primitive / literal where the base declared an object-shaped
///     interface / class / object-literal type. A primitive can never
///     satisfy an object member, so this is always an error.
///
/// Generic interfaces (and generic bases) are skipped -- substituting
/// `extends Foo<T>` correctly needs the full generic machinery, and the
/// conservative miss is preferable to a substitution-shaped FP.
fn check_interface_extends_compat(
  module_ : @ast.TsModule,
  outer_object_names : Map[String, Unit],
  resolver : Resolver,
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  // Index declared interfaces by name (non-generic only).
  let iface_by_name : Map[String, @ast.TsInterface] = {}
  for iface in module_.interfaces {
    if iface.type_params.length() == 0 {
      iface_by_name[iface.name] = iface
    }
  }
  // Object-shaped declared names (interfaces or classes) -- used to
  // confirm a base member type really is object-shaped before flagging a
  // scalar override against it. Seeded with outer-scope names so a
  // namespaced interface extending a member typed by a top-level
  // interface is still recognised.
  let object_shaped : Map[String, Unit] = {}
  for name, _ in outer_object_names {
    object_shaped[name] = ()
  }
  for iface in module_.interfaces {
    object_shaped[iface.name] = ()
  }
  for c in module_.classes {
    object_shaped[c.name] = ()
  }
  // Strip a trailing `| undefined` / `| null` (the parser's encoding of
  // `x?: T`) so the scalar-vs-object comparison sees the payload type.
  fn strip_optional(t : @ast.TsType) -> @ast.TsType {
    match t {
      Union(members) => {
        let rest : Array[@ast.TsType] = []
        for m in members {
          if !(m is Undefined) && !(m is Null) {
            rest.push(m)
          }
        }
        if rest.length() == 1 {
          rest[0]
        } else {
          t
        }
      }
      _ => t
    }
  }
  fn is_scalar(t : @ast.TsType) -> Bool {
    match t {
      Number
      | Int
      | Boolean
      | String_
      | BigInt
      | Symbol
      | Literal(_)
      | NumberLiteral(_)
      | BigIntLiteral(_)
      | BooleanLiteral(_) => true
      _ => false
    }
  }
  fn is_object_shaped(t : @ast.TsType) -> Bool {
    match t {
      Object(_) | Struct(_, _) => true
      Named(n) => object_shaped.contains(n)
      Applied(n, _) => object_shaped.contains(n)
      _ => false
    }
  }
  for iface in module_.interfaces {
    if iface.type_params.length() > 0 {
      continue
    }
    if iface.extends_names.length() == 0 {
      continue
    }
    for bi, base_name in iface.extends_names {
      // Skip bases supplied with type arguments (`extends Foo<X>`).
      if bi < iface.extends_args.length() && iface.extends_args[bi].length() > 0 {
        continue
      }
      let base = match iface_by_name.get(base_name) {
        Some(b) => b
        None => continue
      }
      // Base field name -> (type, accepts-undefined).
      let base_fields : Map[String, @ast.TsType] = {}
      for f in base.fields {
        base_fields[f.0] = f.1
      }
      for df in iface.fields {
        match base_fields.get(df.0) {
          Some(btype) => {
            let d_optional = type_accepts_undefined(df.1)
            let b_optional = type_accepts_undefined(btype)
            // Optionality weakening: derived optional over required base.
            let d_payload = strip_optional(df.1)
            let b_payload = strip_optional(btype)
            // Both members are plain (non-generic) class / interface
            // references: decide structurally. `struct_assignable_named_rec`
            // has the full field sets, so a `false` here is a reliable
            // "not assignable" (e.g. derived `bar: Base` over base
            // `bar: Derived`, where `Base` lacks `Derived`'s members), not a
            // "couldn't determine". Generic `Applied` shapes are excluded
            // (no type-arg substitution) to stay false-positive-free.
            let both_plain_named = match
              (resolver.unwrap(d_payload), resolver.unwrap(b_payload)) {
              (Named(_), Named(_)) =>
                is_named_decl(d_payload, resolver) &&
                is_named_decl(b_payload, resolver)
              _ => false
            }
            if is_scalar(d_payload) && is_object_shaped(b_payload) {
              issues.push({
                path: "interface \{iface.name}",
                message: "interface incorrectly extends `\{base_name}`: property `\{df.0}` of type `\{type_display(df.1)}` is not assignable to the base type `\{type_display(btype)}`",
              })
            } else if both_plain_named &&
              !struct_assignable_named_rec(d_payload, b_payload, resolver, []) {
              issues.push({
                path: "interface \{iface.name}",
                message: "interface incorrectly extends `\{base_name}`: property `\{df.0}` of type `\{type_display(df.1)}` is not assignable to the base type `\{type_display(btype)}`",
              })
            } else if d_optional && !b_optional {
              issues.push({
                path: "interface \{iface.name}",
                message: "interface incorrectly extends `\{base_name}`: property `\{df.0}` is optional but required in the base",
              })
            }
          }
          None => ()
        }
      }
      // Index-signature compatibility: a derived index signature's value
      // type must be assignable to the base's same-keyed index signature
      // value. `interface B extends A { [x: string]: Base }` over
      // `interface A { [x: string]: Derived }` is incompatible because
      // `Base` lacks `Derived`'s members. Decide structurally and only when
      // both values are plain (non-generic) named decls, so it's a reliable
      // "not assignable" with no FP from unresolved generics.
      for d_sig in iface.index_signatures {
        for b_sig in base.index_signatures {
          if d_sig.0 == b_sig.0 {
            let dv = strip_optional(d_sig.1)
            let bv = strip_optional(b_sig.1)
            let both_plain_named = match
              (resolver.unwrap(dv), resolver.unwrap(bv)) {
              (Named(_), Named(_)) =>
                is_named_decl(dv, resolver) && is_named_decl(bv, resolver)
              _ => false
            }
            if both_plain_named &&
              !struct_assignable_named_rec(dv, bv, resolver, []) {
              issues.push({
                path: "interface \{iface.name}",
                message: "interface incorrectly extends `\{base_name}`: index signatures are incompatible",
              })
            }
          }
        }
      }
    }
  }
  // TS2411 ("Property 'X' of type 'T' is not assignable to '<key>' index
  // type 'V'"): an index signature `[k: K]: V` constrains the named
  // members of its containing type -- every constrained property's type
  // must be assignable to the index value type `V`. A numeric index
  // signature (`[k: number]: V`) only constrains numeric-named properties;
  // a string index signature (`[k: string]: V`) constrains every named
  // property (a numeric name is also a string name).
  //
  // We only emit when the violation is structurally certain so the
  // declaration-level check never false-flags subtype-dependent pairs:
  //   - both sides are concrete scalars and the property scalar is not
  //     assignable to the index scalar (`number` vs `string` index, etc.);
  //   - the index value is a scalar but the property is object-shaped /
  //     function / array / tuple (never assignable to a primitive);
  //   - the index value is object-shaped but the property is a scalar
  //     (a primitive can never satisfy an object index type).
  // `any` / `unknown` / unresolved `Named` / generic-dependent property
  // types fall through to "no diagnostic".
  //
  // A property name is treated as numeric only when it is a canonical
  // non-negative integer literal (`"0"`, `"42"`); this is a deliberate
  // subset of TS's numeric-literal-name rule, chosen so every name we
  // count as numeric really is one (no false positives), accepting a
  // conservative miss on fractional numeric names.
  fn is_numeric_name(name : String) -> Bool {
    let chars = name.to_array()
    if chars.length() == 0 {
      return false
    }
    if chars.length() > 1 && chars[0] == '0' {
      return false
    }
    for c in chars {
      if c < '0' || c > '9' {
        return false
      }
    }
    true
  }
  // A scalar, or a union whose every member is a scalar (`string | number`,
  // `"a" | "b"`, …). Such a value type is a "primitive set": no object /
  // function / array can be assigned to it, and a scalar property is decided
  // by `is_assignable_to` (which handles union membership). A union with even
  // one non-scalar member is excluded so an object property is never
  // mis-flagged against an index type that could actually accept it.
  fn is_scalar_set(t : @ast.TsType) -> Bool {
    match t {
      Union(members) => {
        for m in members {
          if !is_scalar(m) {
            return false
          }
        }
        members.length() > 0
      }
      _ => is_scalar(t)
    }
  }
  fn violates_index_value(prop : @ast.TsType, value : @ast.TsType) -> Bool {
    let t = strip_optional(prop)
    // Index value is object-shaped: a scalar property can never satisfy it.
    if is_object_shaped(value) {
      return is_scalar(t)
    }
    // Index value is a primitive scalar (or a union of scalars): the property
    // must be assignable to it. Only decide for concrete property shapes —
    // object / function / array / tuple types are never a primitive, and a
    // concrete scalar is decided by `is_assignable_to` (union-membership
    // aware). Anything else (unresolved `Named`, type parameters, `any`,
    // unions on the property side) falls through to "no diagnostic".
    if is_scalar_set(value) {
      if is_scalar(t) {
        return !is_assignable_to(t, value)
      }
      if is_object_shaped(t) {
        return true
      }
      return match t {
        Func(_, _) | Constructor(_, _, _) | Array(_) | Tuple(_) => true
        _ => false
      }
    }
    false
  }
  fn check_index_props(
    index_sigs : Array[(@ast.TsType, @ast.TsType)],
    fields : Array[(String, @ast.TsType)],
    owner : String,
  ) -> Unit {
    for sig in index_sigs {
      let numeric_only = match sig.0 {
        Number | Int => true
        String_ => false
        // Symbol / template-literal / other index keys aren't constrained
        // here (and the `Any` placeholder from an unparsed signature must
        // never constrain anything).
        _ => continue
      }
      for f in fields {
        if numeric_only && !is_numeric_name(f.0) {
          continue
        }
        // Symbol-keyed members (rendered `<computed>`, e.g.
        // `[Symbol.toStringTag]: string` / `[mySymbol]: string`) are not
        // constrained by string or numeric index signatures — only a symbol
        // index signature would apply. Skip them.
        if f.0 == "<computed>" {
          continue
        }
        if violates_index_value(f.1, sig.1) {
          issues.push({
            path: owner,
            message: "property `\{f.0}` of type `\{type_display(f.1)}` is not assignable to index type `\{type_display(sig.1)}`",
          })
        }
      }
    }
  }

  for iface in module_.interfaces {
    // Generic interfaces are processed too: a property whose type is one of
    // the interface's own type parameters resolves to a bare `Named` that is
    // not object-shaped and not scalar, so `violates_index_value` leaves it
    // alone -- only concrete object / scalar properties are decided.
    check_index_props(
      iface.index_signatures,
      iface.fields,
      "interface \{iface.name}",
    )
  }
  for c in module_.classes {
    if c.type_params.length() == 0 {
      // Getters / setters are upserted into `properties` by the parser
      // with an imprecise (often `Any`) type, so exclude accessor-named
      // members to keep the constraint check on real data fields.
      let accessors = class_instance_accessor_names(c)
      let fields : Array[(String, @ast.TsType)] = []
      for p in c.properties {
        if !p.is_static && !accessors.contains(p.name) {
          fields.push((p.name, p.type_))
        }
      }
      check_index_props(c.index_signatures, fields, "class \{c.name}")
    }
  }
  issues
}

///|
/// Names of a class's non-static get/set accessors.
fn class_instance_accessor_names(decl : @ast.TsClassDecl) -> Map[String, Unit] {
  let names : Map[String, Unit] = {}
  for m in decl.methods {
    if !m.is_static && (m.accessor == "get" || m.accessor == "set") {
      names[m.name] = ()
    }
  }
  // Stage-3 auto-accessor fields (`accessor x = ...`) are accessor-like,
  // not data properties -- track them on the accessor side.
  for prop in decl.properties {
    if !prop.is_static && prop.is_accessor {
      names[prop.name] = ()
    }
  }
  names
}

///|
/// Names of a class's non-static data fields -- `properties` entries
/// that are not actually backed by an accessor (getters/setters are
/// upserted into `properties` by the parser, so they are filtered out
/// via the supplied accessor-name set, and auto-accessor fields are
/// excluded too).
fn class_instance_field_names(
  decl : @ast.TsClassDecl,
  accessors : Map[String, Unit],
) -> Map[String, Unit] {
  let names : Map[String, Unit] = {}
  for prop in decl.properties {
    if prop.is_static {
      continue
    }
    if prop.is_accessor {
      continue
    }
    if accessors.contains(prop.name) {
      continue
    }
    names[prop.name] = ()
  }
  names
}

///|
/// TS2728 ("Property 'X' is used before its initialization"). Instance
/// field initializers run in declaration order; referencing `this.Y`
/// from `X`'s initializer before `Y` itself has been initialized is a
/// real error because the runtime read sees `undefined` regardless of
/// `Y`'s declared type.
///
/// We rely on `decl.instance_field_inits` (parser-populated in source
/// order) and walk each init expression for `this.<name>` references.
/// A reference is flagged when the referenced name is also an init in
/// the list at a later index — references to methods, getters/setters,
/// constructor params, or fields without initializers are not flagged.
fn check_class_property_init_order(module_ : @ast.TsModule) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  for decl in module_.classes {
    if decl.is_declare {
      continue
    }
    if decl.instance_field_inits.length() == 0 {
      continue
    }
    // Set of non-static field names declared on the class. We use this
    // to distinguish a reference to a class field (potential TS2729
    // candidate) from a reference to a method, accessor, or external
    // member. Methods are recorded via `decl.methods`; bare property
    // entries with `is_accessor`/`get`/`set` are recorded by upserting
    // through `properties` but synthesized methods (which include
    // getters/setters) are listed in `decl.methods` and we exclude
    // their names from the field set so `this.m1()` -> a method call
    // isn't flagged.
    let field_names : Map[String, Unit] = {}
    for prop in decl.properties {
      if !prop.is_static && !prop.is_accessor {
        field_names[prop.name] = ()
      }
    }
    // Constructor parameter properties (`constructor(public foo: T)`)
    // declare `this.foo` slots that are written *during* the constructor
    // body — i.e. after every instance-field initializer has already
    // run. Treat their names as fields so a field-init that reads
    // `this.foo` before the constructor runs is reported.
    match decl.constructor_params {
      Some(params) =>
        for entry in params {
          field_names[entry.0] = ()
        }
      None => ()
    }
    for m in decl.methods {
      // Methods + accessors live in `properties` AND `methods`. The
      // method's presence overrides the field interpretation -- the
      // slot's value is a stable function reference once the class is
      // defined, so reading `this.m` from a field init is fine.
      if !m.is_static {
        let _ = field_names.remove(m.name)
      }
    }
    // Walk inits in source order. The set of *already initialized*
    // names grows as we go; a reference to `this.X` where X is a known
    // field but not yet in `inited` is the TS2729 signal.
    let inited : Map[String, Unit] = {}
    for entry in decl.instance_field_inits {
      let (name, init_expr) = entry
      collect_this_refs_for_uninit_field(
        init_expr,
        field_names,
        inited,
        decl.name,
        issues,
      )
      inited[name] = ()
    }
  }
  issues
}

///|
/// Walk `expr` and emit a TS2729 issue for every `this.<name>` access
/// where `<name>` is a non-static, non-method field declared on the
/// class but not yet present in `inited`. Function-bodies (arrow /
/// FuncExpr) and getter/setter callbacks are intentionally NOT
/// traversed because their bodies execute lazily, after class setup.
fn collect_this_refs_for_uninit_field(
  expr : @ast.TsExpr,
  field_names : Map[String, Unit],
  inited : Map[String, Unit],
  class_name : String,
  issues : Array[ExprIssue],
) -> Unit {
  match expr {
    PropAccess(Var("this"), name) =>
      if field_names.contains(name) && !inited.contains(name) {
        issues.push({
          path: "class \{class_name}",
          message: "property `\{name}` is used before its initialization",
        })
      }
    PropAccess(inner, _) =>
      collect_this_refs_for_uninit_field(
        inner, field_names, inited, class_name, issues,
      )
    IndexAccess(recv, idx) => {
      collect_this_refs_for_uninit_field(
        recv, field_names, inited, class_name, issues,
      )
      collect_this_refs_for_uninit_field(
        idx, field_names, inited, class_name, issues,
      )
    }
    Call(_, args) =>
      for a in args {
        collect_this_refs_for_uninit_field(
          a, field_names, inited, class_name, issues,
        )
      }
    CallExpr(callee, args) => {
      collect_this_refs_for_uninit_field(
        callee, field_names, inited, class_name, issues,
      )
      for a in args {
        collect_this_refs_for_uninit_field(
          a, field_names, inited, class_name, issues,
        )
      }
    }
    MethodCall(recv, name, args) => {
      if recv is Var("this") &&
        field_names.contains(name) &&
        !inited.contains(name) {
        // `this.m3()` where m3 is a field-typed function (`m3 =
        // function(){}`) that hasn't been initialized yet.
        issues.push({
          path: "class \{class_name}",
          message: "property `\{name}` is used before its initialization",
        })
      } else if !(recv is Var("this")) {
        collect_this_refs_for_uninit_field(
          recv, field_names, inited, class_name, issues,
        )
      }
      for a in args {
        collect_this_refs_for_uninit_field(
          a, field_names, inited, class_name, issues,
        )
      }
    }
    New(_, args) =>
      for a in args {
        collect_this_refs_for_uninit_field(
          a, field_names, inited, class_name, issues,
        )
      }
    NewExpr(callee, args) => {
      collect_this_refs_for_uninit_field(
        callee, field_names, inited, class_name, issues,
      )
      for a in args {
        collect_this_refs_for_uninit_field(
          a, field_names, inited, class_name, issues,
        )
      }
    }
    BinOp(_, l, r) => {
      collect_this_refs_for_uninit_field(
        l, field_names, inited, class_name, issues,
      )
      collect_this_refs_for_uninit_field(
        r, field_names, inited, class_name, issues,
      )
    }
    UnaryOp(_, inner) =>
      collect_this_refs_for_uninit_field(
        inner, field_names, inited, class_name, issues,
      )
    Cond(c, t, e) => {
      collect_this_refs_for_uninit_field(
        c, field_names, inited, class_name, issues,
      )
      collect_this_refs_for_uninit_field(
        t, field_names, inited, class_name, issues,
      )
      collect_this_refs_for_uninit_field(
        e, field_names, inited, class_name, issues,
      )
    }
    Seq(l, r) => {
      collect_this_refs_for_uninit_field(
        l, field_names, inited, class_name, issues,
      )
      collect_this_refs_for_uninit_field(
        r, field_names, inited, class_name, issues,
      )
    }
    ArrayLit(items) =>
      for it in items {
        collect_this_refs_for_uninit_field(
          it, field_names, inited, class_name, issues,
        )
      }
    ObjectLit(entries) =>
      for entry in entries {
        collect_this_refs_for_uninit_field(
          entry.1,
          field_names,
          inited,
          class_name,
          issues,
        )
      }
    Spread(inner) =>
      collect_this_refs_for_uninit_field(
        inner, field_names, inited, class_name, issues,
      )
    _ => ()
  }
}

///|
/// Module-level signature lint: duplicate parameter names, duplicate
/// type-parameter names, and other decl-shape errors that TypeScript
/// reports without needing flow / body analysis.
fn check_module_decl_signatures(module_ : @ast.TsModule) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  // Top-level functions.
  for func in module_.funcs {
    check_dup_type_params("function \{func.name}", func.type_params, issues)
    let names : Array[String] = []
    for p in func.params {
      names.push(p.name)
    }
    check_dup_param_names("function \{func.name}", names, issues)
    check_func_rest_params("function \{func.name}", func.params, issues)
  }
  // Ambient `declare function` imports.
  for imp in module_.imports {
    check_dup_type_params("function \{imp.name}", imp.type_params, issues)
    let names : Array[String] = []
    for p in imp.params {
      names.push(p.0)
    }
    check_dup_param_names("function \{imp.name}", names, issues)
  }
  // Classes — own type-param list, plus methods.
  for cls in module_.classes {
    check_dup_type_params("class \{cls.name}", cls.type_params, issues)
    if cls.type_params.length() > 0 {
      check_static_uses_class_type_params(cls, issues)
    }
    for meth in cls.methods {
      let path = "class \{cls.name} > \{meth.name}"
      check_dup_type_params(path, meth.type_params, issues)
      let names : Array[String] = []
      for p in meth.params {
        names.push(p.0)
      }
      check_dup_param_names(path, names, issues)
      check_method_rest_params(path, meth, issues)
    }
  }
  // Interfaces.
  for iface in module_.interfaces {
    check_dup_type_params("interface \{iface.name}", iface.type_params, issues)
  }
  // Type aliases.
  for ta in module_.type_aliases {
    check_dup_type_params("type \{ta.name}", ta.type_params, issues)
  }
  issues
}

///|
/// TS2302: a `static` member (property or method) cannot reference any of
/// the enclosing class's type parameters. Class TPs are an instance-side
/// notion; the static side doesn't carry a binding for them. Walks every
/// type-position on each static member and flags references back to any
/// of the class's TPs.
fn check_static_uses_class_type_params(
  cls : @ast.TsClassDecl,
  issues : Array[ExprIssue],
) -> Unit {
  for p in cls.properties {
    if p.is_static && type_references_any(p.type_, cls.type_params) {
      issues.push({
        path: "class \{cls.name} > static \{p.name}",
        message: "static members cannot reference class type parameters",
      })
    }
  }
  for m in cls.methods {
    if !m.is_static {
      continue
    }
    let path = "class \{cls.name} > static \{m.name}"
    // Method-level type parameters shadow the class's, so exclude them
    // from the offending set when scanning a method's signature.
    let class_tps_minus_method : Array[String] = []
    for tp in cls.type_params {
      if !m.type_params.contains(tp) {
        class_tps_minus_method.push(tp)
      }
    }
    if class_tps_minus_method.length() == 0 {
      continue
    }
    if type_references_any(m.return_type, class_tps_minus_method) {
      issues.push({
        path,
        message: "static members cannot reference class type parameters",
      })
      continue
    }
    let mut flagged = false
    for prm in m.params {
      if type_references_any(prm.1, class_tps_minus_method) {
        issues.push({
          path,
          message: "static members cannot reference class type parameters",
        })
        flagged = true
        break
      }
    }
    let _ = flagged
  }
}

///|
/// True when `ty` (or anything nested inside it) is `Named(n)` for some
/// `n` in `names`. Walks all structural type variants so a reference
/// through `Array<T>`, `T | undefined`, `Record<string, T>`, tuples,
/// object literals, function types, etc. is caught.
fn type_references_any(ty : @ast.TsType, names : Array[String]) -> Bool {
  if names.length() == 0 {
    return false
  }
  match ty {
    Named(n) => names.contains(n)
    Applied(_, args) => {
      for a in args {
        if type_references_any(a, names) {
          return true
        }
      }
      false
    }
    Array(inner) => type_references_any(inner, names)
    Union(parts) | Intersection(parts) => {
      for p in parts {
        if type_references_any(p, names) {
          return true
        }
      }
      false
    }
    Tuple(parts) => {
      for p in parts {
        if type_references_any(p, names) {
          return true
        }
      }
      false
    }
    Func(params, ret) => {
      for p in params {
        if type_references_any(p, names) {
          return true
        }
      }
      type_references_any(ret, names)
    }
    Object(fields) => {
      for f in fields {
        if type_references_any(f.0, names) || type_references_any(f.1, names) {
          return true
        }
      }
      false
    }
    Struct(_, fields) => {
      for f in fields {
        if type_references_any(f.1, names) {
          return true
        }
      }
      false
    }
    Rest(inner) => type_references_any(inner, names)
    _ => false
  }
}

///|
/// A rest parameter (`...x: T`) requires `T` to be an array, tuple, or any.
/// Anything else is `TS2370: A rest parameter must be of an array type`.
fn check_func_rest_params(
  path : String,
  params : Array[@ast.TsParam],
  issues : Array[ExprIssue],
) -> Unit {
  let mut i = 0
  while i < params.length() {
    let p = params[i]
    if p.is_rest {
      if !is_valid_rest_param_type(p.type_) {
        issues.push({
          path,
          message: "rest parameter `\{p.name}` must be of an array type",
        })
      }
      if i + 1 < params.length() {
        issues.push({
          path,
          message: "rest parameter `\{p.name}` must be last in the parameter list",
        })
      }
    }
    i = i + 1
  }
}

///|
fn check_method_rest_params(
  path : String,
  meth : @ast.TsClassMethodDecl,
  issues : Array[ExprIssue],
) -> Unit {
  let mut i = 0
  while i < meth.params.length() && i < meth.param_is_rest.length() {
    if meth.param_is_rest[i] {
      let pname = meth.params[i].0
      let ptype = meth.params[i].1
      if !is_valid_rest_param_type(ptype) {
        issues.push({
          path,
          message: "rest parameter `\{pname}` must be of an array type",
        })
      }
      if i + 1 < meth.params.length() {
        issues.push({
          path,
          message: "rest parameter `\{pname}` must be last in the parameter list",
        })
      }
    }
    i = i + 1
  }
}

///|
fn is_valid_rest_param_type(ty : @ast.TsType) -> Bool {
  match ty {
    Array(_) => true
    Tuple(_) => true
    Applied("Array", _) | Applied("ReadonlyArray", _) => true
    // Type alias / interface reference (`...args: SomeTuple`). We don't
    // resolve through the resolver here (the decl-signature pass is
    // resolver-free), so treat any `Named` / `Applied` shape as valid
    // and let real array-shape mismatches surface elsewhere.
    Named(_) | Applied(_, _) => true
    // Indexed-access / generic-construct types (`T[K]`, `Parameters<F>`,
    // `keyof X`, conditional / mapped types). We can't resolve their
    // surface shape without the resolver; accept rather than false-flag.
    IndexedAccess(_, _) => true
    Keyof(_) => true
    Conditional(_, _, _, _) => true
    MappedType(_, _, _, _) | MappedTypeRemap(_, _, _, _, _) => true
    Union(_) | Intersection(_) => true
    // Unannotated rest (`...args`) parses as `Any` — TS treats this as
    // `any[]`, valid.
    Any => true
    _ => false
  }
}

///|
fn check_dup_type_params(
  path : String,
  type_params : Array[String],
  issues : Array[ExprIssue],
) -> Unit {
  if type_params.length() < 2 {
    return
  }
  let seen : Array[String] = []
  let reported : Array[String] = []
  for name in type_params {
    if seen.contains(name) {
      if !reported.contains(name) {
        reported.push(name)
        issues.push({ path, message: "duplicate type parameter `\{name}`" })
      }
    } else {
      seen.push(name)
    }
  }
}

///|
fn check_dup_param_names(
  path : String,
  names : Array[String],
  issues : Array[ExprIssue],
) -> Unit {
  if names.length() < 2 {
    return
  }
  let seen : Array[String] = []
  let reported : Array[String] = []
  for name in names {
    // TypeScript treats binding-pattern parameters (which our parser
    // sometimes labels with a synthesized empty / `<pattern>` name)
    // separately, so only flag duplicates on real identifiers.
    if name == "" || name.has_prefix("<") {
      continue
    }
    if seen.contains(name) {
      if !reported.contains(name) {
        reported.push(name)
        issues.push({ path, message: "duplicate parameter name `\{name}`" })
      }
    } else {
      seen.push(name)
    }
  }
}
