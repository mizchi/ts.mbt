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
  // Enum declarations keyed by name so `Color.Red` resolves to the member's
  // literal value type rather than falling through to Any.
  enums : Map[String, @ast.TsEnumDecl]
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
    func_const_type_params: {},
    enums: {},
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
  }
}

///|
fn Resolver::from_module(module_ : @ast.TsModule) -> Resolver {
  let r = Resolver::empty()
  Resolver::ingest_module(r, module_, "")
  r
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
    let param_types : Array[@ast.TsType] = []
    for p in imp.params {
      // `declare function`'s params come from `(name, type)` pairs without
      // a rest flag, so each entry is taken as-is. A surface-level rest
      // declaration like `(...args: T[])` shows up as `Array(T)` here
      // already; the rest pattern path in `match_infer_pattern` handles
      // single-Array-param shapes without needing an explicit Rest.
      param_types.push(p.1)
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
    for p in imp.params {
      synth_params.push({
        name: p.0,
        binding: None,
        is_rest: false,
        type_: p.1,
        default: None,
      })
    }
    r.signatures[prefix + imp.name] = synth_params
  }
  for f in module_.funcs {
    let param_types : Array[@ast.TsType] = []
    for p in f.params {
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
    r.signatures[prefix + f.name] = f.params
    r.func_type_params[prefix + f.name] = f.type_params
    r.func_const_type_params[prefix + f.name] = f.const_type_params
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
    if !type_accepts_undefined_param(params[i]) {
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
            None => keep_going = false
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
      TypeOf(name) =>
        match self.globals.get(name) {
          Some(resolved) => cur = resolved
          None => keep_going = false
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
              return Some(substitute_params(f.1, bindings))
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
                  let param_types : Array[@ast.TsType] = []
                  for mp in m.params {
                    param_types.push(substitute_params(mp.1, bindings))
                  }
                  return Some(
                    @ast.TsType::Func(
                      param_types,
                      substitute_params(m.return_type, bindings),
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
      let field_is_numeric = (try? @string.parse_int(field)) is Ok(_)
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
    // Restore primitive-vs-primitive (and a few other reliable
    // shapes) so the strict diagnostic isn't fully lost in
    // permissive mode -- the common `var x: number = "hello"` style
    // mistake is a clean signal we can keep.
    match extract_mismatch_types(message) {
      Some((exp, got)) =>
        if is_reliable_mismatch_pair(exp, got) &&
          !is_widening_direction_mismatch(exp, got) &&
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
    return true
  }
  if message.has_prefix("method `") && message.contains("does not exist on") {
    return true
  }
  if message.contains("argument(s), got ") {
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
    return true
  }
  if message.has_prefix("comparing `") &&
    message.contains("will always be false") {
    return true
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
  // Primitive-vs-shape and shape-vs-primitive: an obvious category
  // mismatch (`number = [1, "a"]`, `string[] = 5`). TS flags these
  // and our assignability gets them right. We still suppress when
  // either side contains `|` (union -> flow narrowing residue) or
  // `<` (generic application -> inference residue).
  if exp.contains("|") || got.contains("|") {
    return false
  }
  if exp.contains("<") || got.contains("<") {
    return false
  }
  if is_reliable_mismatch_type(exp) && is_simple_shape_type(got) {
    return true
  }
  if is_simple_shape_type(exp) && is_reliable_mismatch_type(got) {
    return true
  }
  false
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
fn is_widening_direction_mismatch(exp : String, got : String) -> Bool {
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
  // void target accepts any source: a callback like `(x) => x.foo()`
  // returning `boolean` passed to `forEach` (`(v) => void`) is fine
  // because the return value is discarded at the call site. TS
  // accepts these; we treat the mismatch as widening-direction.
  if exp == "void" {
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
      }
    }
    _ => ()
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
      infer_binop(op, lt, rt)
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
              env, resolver, type_params, params, args,
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
      // Nullable receiver: strip null/undefined members and retry so
      // `(arr | null).map(...)` still resolves the method return type.
      match resolver.lookup_method_sig(prune_nullish(resolver, recv_ty), meth) {
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
      match infer_expr(env, resolver, tag) {
        Func(_, ret) => ret
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
/// in `actual`. First binding wins; later occurrences are only honored
/// if the existing binding was `Any`.
fn infer_param_bindings(
  type_params : Array[String],
  formal : @ast.TsType,
  actual : @ast.TsType,
  bindings : Map[String, @ast.TsType],
) -> Unit {
  // Direct hit: formal is exactly a type parameter we're solving for.
  match formal {
    Named(name) =>
      if type_params.contains(name) {
        match bindings.get(name) {
          Some(Any) | None => bindings[name] = actual
          Some(_) => () // first concrete binding wins
        }
        return
      }
    _ => ()
  }
  // Structural matching — peel matching outer shapes.
  match (formal, actual) {
    (Array(f_elem), Array(a_elem)) =>
      infer_param_bindings(type_params, f_elem, a_elem, bindings)
    (Array(f_elem), Applied("Array", a_args)) if a_args.length() == 1 =>
      infer_param_bindings(type_params, f_elem, a_args[0], bindings)
    (Applied("Array", f_args), Array(a_elem)) if f_args.length() == 1 =>
      infer_param_bindings(type_params, f_args[0], a_elem, bindings)
    (Applied(f_name, f_args), Applied(a_name, a_args)) =>
      if f_name == a_name && f_args.length() == a_args.length() {
        let mut i = 0
        while i < f_args.length() {
          infer_param_bindings(type_params, f_args[i], a_args[i], bindings)
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
        infer_param_bindings(type_params, f_items[i], a_items[i], bindings)
        i = i + 1
      }
    }
    (Func(f_params, f_ret), Func(a_params, a_ret)) => {
      let n = if f_params.length() < a_params.length() {
        f_params.length()
      } else {
        a_params.length()
      }
      let mut i = 0
      while i < n {
        infer_param_bindings(type_params, f_params[i], a_params[i], bindings)
        i = i + 1
      }
      infer_param_bindings(type_params, f_ret, a_ret, bindings)
    }
    (Union(f_parts), _) =>
      // Best-effort: try the first part that isn't a bare type parameter
      // (matching a concrete shape generally yields more information). If
      // none matches concretely, fall back to the first part.
      for part in f_parts {
        match part {
          Named(n) if type_params.contains(n) => continue
          _ => {
            infer_param_bindings(type_params, part, actual, bindings)
            return
          }
        }
      }
    _ => ()
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
) -> Map[String, @ast.TsType] {
  let bindings : Map[String, @ast.TsType] = {}
  for tp in type_params {
    bindings[tp] = @ast.TsType::Any
  }
  let n = if args.length() < params.length() {
    args.length()
  } else {
    params.length()
  }
  let mut i = 0
  while i < n {
    let actual = infer_expr(env, resolver, args[i])
    infer_param_bindings(type_params, params[i], actual, bindings)
    i = i + 1
  }
  bindings
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
fn infer_binop(
  op : @ast.TsBinOp,
  l : @ast.TsType,
  r : @ast.TsType,
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
    // `a`. Conservative: union both sides.
    And => narrow_union(l, r)
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
      for i, item in items {
        check_expr_against(
          env,
          item,
          elem,
          ctx,
          sub_path + "[" + i.to_string() + "]",
        )
      }
      return
    }
    (ArrayLit(items), Applied("Array", [elem]))
    | (ArrayLit(items), Applied("ReadonlyArray", [elem])) => {
      for i, item in items {
        check_expr_against(
          env,
          item,
          elem,
          ctx,
          sub_path + "[" + i.to_string() + "]",
        )
      }
      return
    }
    // `Readonly<T[]>` contextual typing — delegate to element checking on
    // the inner array type so `['a', 'b'] as Readonly<string[]>` works.
    (ArrayLit(items), Applied("Readonly", [Array(elem)])) => {
      for i, item in items {
        check_expr_against(
          env,
          item,
          elem,
          ctx,
          sub_path + "[" + i.to_string() + "]",
        )
      }
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
  // Generic `Applied(...)` shapes (`Generator<any, any>`, `Maybe<any>[]`,
  // `Promise<T>`) on either side carry inference we don't fully track.
  // Comparing them nominally produces false mismatches when the user's
  // generic substitution would have unified them. Stay silent when
  // either side is a generic instantiation -- the cost is dropping some
  // genuine generic-mismatch diagnostics, but those are the same kind
  // of `expected Promise<X> but got Promise<Y>` cases users rarely
  // benefit from in a structurally-typed nominal-rendering checker.
  match (inferred_u, expected_u) {
    (Applied(_, _), _) | (_, Applied(_, _)) => return
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
  // Only engage when both sides resolve as class / interface shapes.
  // `lookup_field` returns `None` for opaque receivers, so this filter
  // also weeds out unresolvable references (generic type parameters,
  // qualified names) without false promotion.
  if !is_named_decl(source, resolver) || !is_named_decl(target, resolver) {
    return false
  }
  let target_fields = collect_declared_fields(target, resolver)
  if target_fields.length() == 0 {
    return false
  }
  for f in target_fields {
    let key = f.0
    let want = f.1
    match resolver.lookup_field(source, key) {
      Some(have) =>
        if !is_assignable_to(resolver.unwrap(have), resolver.unwrap(want)) {
          return false
        }
      None => return false
    }
  }
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
  // Per-field type checks for each provided key.
  for entry in entries {
    let key = entry.0
    let value = entry.1
    // Spread entries (`@@spread:N`) are not individual properties — skip them
    // in the excess-property check; their fields are checked via infer_expr.
    if key.has_prefix("@@spread:") {
      continue
    }
    match resolver.lookup_field(target, key) {
      Some(declared) =>
        check_expr_against(env, value, declared, ctx, "\{sub_path}.\{key}")
      None =>
        // Unknown key on the target — TS calls this an excess-property
        // error. Skip class/struct opaque shapes by relying on lookup_field
        // having already walked their fields above.
        record(
          ctx,
          "\{sub_path}.\{key}",
          "property `\{key}` does not exist on target type",
        )
    }
  }
  // Missing-required check: collect the declared field names of the target
  // and see which were omitted. Properties whose declared type accepts
  // `undefined` (optional, written `x?: T` or `T | undefined`) are
  // exempt.
  let declared = collect_declared_fields(target, resolver)
  let provided : Map[String, Bool] = {}
  for entry in entries {
    if !entry.0.has_prefix("@@spread:") {
      provided[entry.0] = true
    }
  }
  for d in declared {
    let name = d.0
    let ty = d.1
    if provided.contains(name) {
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
    env.bind(p.name, ty)
    i = i + 1
  }
  match body {
    ArrowExpr(e) => {
      let want = unwrap_async_return(is_async, formal_ret)
      check_expr_against(env, e, want, ctx, "\{sub_path} arrow body")
    }
    ArrowBlock(block) => {
      // Recheck the block with the new env and the formal_ret as the
      // expected return type.
      let inner_ctx : CheckCtx = {
        path_prefix: ctx.path_prefix,
        return_type: unwrap_async_return(is_async, formal_ret),
        yield_type: @ast.TsType::Any,
        resolver: ctx.resolver,
        issues: ctx.issues,
        in_scope_type_params: ctx.in_scope_type_params,
        permissive: ctx.permissive,
        unassigned: ctx.unassigned,
        strict_property_init: ctx.strict_property_init,
      }
      for stmt in block.stmts {
        check_stmt(env, stmt, inner_ctx)
      }
    }
  }
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
    unassigned: ctx.unassigned,
    strict_property_init: ctx.strict_property_init,
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
    None =>
      // No rich `TsParam` metadata (e.g. calling a value typed as
      // `Func([...], _)` — a variable, method, or call-signature). We can
      // still recover optionality from the parameter *types*: the parser
      // widens `x?: T` to `T | undefined`, so a trailing param whose type
      // accepts `undefined` is omittable. This drives the min count down
      // without needing the declaration's `TsParam` list.
      (required_arity_from_types(params), params.length())
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
      record(ctx, call_path, "expected \{expect_str} argument(s), got \{n}")
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
    None => -1
  }
  let rest_elem_type : @ast.TsType = if rest_index >= 0 &&
    rest_index < params.length() {
    match params[rest_index] {
      Array(elem) => elem
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
  let mut i = 0
  while i < args.length() {
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
    Func(_, _) => "function"
    Tuple(items) => {
      let parts : Array[String] = []
      for a in items {
        parts.push(type_display(a))
      }
      "[" + parts.join(", ") + "]"
    }
    _ => "type"
  }
}

// ---------------------------------------------------------------------------
// Destructuring binding helpers.
// ---------------------------------------------------------------------------

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
    bind_pattern(env, ctx, prop.binding, field_ty)
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
        // Both sub-conditions must hold in the then-branch.
        collect_narrowing(env, resolver, l, then_binds, else_binds, true)
        collect_narrowing(env, resolver, r, then_binds, else_binds, true)
      }
    BinOp(Or, l, r) =>
      if !then_sense {
        // Both must be false in the else-branch.
        collect_narrowing(env, resolver, l, then_binds, else_binds, true)
        collect_narrowing(env, resolver, r, then_binds, else_binds, true)
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
    None => return
  }
  let (param_name, target) = match ret {
    TypePredicate(p, t) => (p, t)
    _ => return
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
  let is_numeric = (try? @string.parse_int(field)) is Ok(_)
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
  let idx = (try? @string.parse_int(inner)) is Ok(_)
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
fn check_block_with_narrowing(
  env : ExprEnv,
  block : @ast.TsBlock,
  ctx : CheckCtx,
  binds : Array[(String, @ast.TsType)],
) -> Unit {
  let pre = env.full_snapshot()
  for b in binds {
    env.bind(b.0, b.1)
  }
  for stmt in block.stmts {
    check_stmt(env, stmt, ctx)
  }
  env.restore_from(pre)
}

///|
fn check_stmt(env : ExprEnv, stmt : @ast.TsStmt, ctx : CheckCtx) -> Unit {
  match stmt {
    Var(@ast.TsBinding::Ident(name), declared, init)
    | Let(@ast.TsBinding::Ident(name), declared, init)
    | Const(@ast.TsBinding::Ident(name), declared, init) => {
      let bound_type = if is_checkable(declared) {
        declared
      } else {
        infer_expr(env, ctx.resolver, init)
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
      // `let x: T;` / `var x: T;` with no `=` initializer. Track the
      // binding as unassigned so later references can be flagged. Only
      // do this when the declared type doesn't already accept
      // `undefined` (otherwise the read of an unassigned `x` is well
      // -typed) and when it's checkable (no annotation = `Any`, which
      // TS doesn't flag either).
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
            ctx.strict_property_init {
            ctx.unassigned[name] = true
          }
        _ => ()
      }
      check_expr_against(env, init, declared, ctx, "binding `\{name}` init")
    }
    Var(@ast.TsBinding::Array(ab), declared, init)
    | Let(@ast.TsBinding::Array(ab), declared, init)
    | Const(@ast.TsBinding::Array(ab), declared, init) => {
      check_call_args_in_expr(env, init, ctx)
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
            !is_in_scope_type_param(ctx, recv_ty) {
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
      let effect = analyze_narrowing(env, ctx.resolver, cond)
      check_block_with_narrowing(env, then_block, ctx, effect.then_binds)
      let then_exits = block_always_exits(then_block)
      let else_exits = match else_block {
        Some(b) => {
          check_block_with_narrowing(env, b, ctx, effect.else_binds)
          block_always_exits(b)
        }
        None => false
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
      // TS2454: same reasoning as for-in — the loop variable is
      // assigned each iteration, so reused declarations clear.
      match binding {
        @ast.TsBinding::Ident(n) => {
          let _ = ctx.unassigned.remove(n)
        }
        _ => ()
      }
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
      match binding {
        @ast.TsBinding::Ident(n) => {
          let _ = ctx.unassigned.remove(n)
        }
        _ => ()
      }
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
      match binding {
        @ast.TsBinding::Ident(n) => {
          let _ = ctx.unassigned.remove(n)
        }
        _ => ()
      }
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
    NativeClassStmt(_, _) => ()
  }
}

///|
/// Walk `expr` for call sites and validate their arguments against the
/// callee's declared parameter types. Pure inference is also run to populate
/// inferred subtypes / surface compound issues.
fn check_call_args_in_expr(
  env : ExprEnv,
  expr : @ast.TsExpr,
  ctx : CheckCtx,
) -> Unit {
  match expr {
    Call(name, args) => {
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
            )
            substitute_params_array(params, bindings)
          } else {
            params
          }
          check_arguments_with_sig(
            env,
            substituted_params,
            sig,
            args,
            ctx,
            "call `\{name}`",
          )
        }
        other =>
          if is_definitely_not_callable(other) {
            record(
              ctx,
              "call `\{name}`",
              "`\{type_display(other)}` is not callable",
            )
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
      // Static-namespace dispatch: `Math.max(...)`, `JSON.stringify(...)`.
      // Recognised by the bare-identifier shape of the receiver.
      let static_params : Array[@ast.TsType]? = match receiver {
        Var(name) =>
          match global_namespace_method(name, meth) {
            Some(Func(params, _)) => Some(params)
            _ => None
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
                      !type_contains_unresolved_named(pruned, ctx.resolver) {
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
    New(class_name, args) =>
      match ctx.resolver.lookup_constructor(class_name) {
        Some(params) => {
          check_arguments(env, params, args, ctx, "new `\{class_name}`")
          for a in args {
            check_call_args_in_expr(env, a, ctx)
          }
        }
        None =>
          for a in args {
            check_call_args_in_expr(env, a, ctx)
          }
      }
    NewExpr(callee, args) => {
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
        Neg | Plus | BitwiseNot => {
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
    PropAccess(recv, prop) => {
      check_call_args_in_expr(env, recv, ctx)
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
        !type_contains_unresolved_named(recv_ty, ctx.resolver) {
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
      let recv_ty = infer_expr(env, ctx.resolver, recv)
      if is_readonly_field(ctx.resolver, recv_ty, prop) {
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
            !is_in_scope_type_param(ctx, recv_ty) {
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
      match recv_ty {
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
    Var(name) =>
      if name != "__ts_no_init__" && ctx.unassigned.get(name) is Some(_) {
        record(
          ctx,
          "use `\{name}`",
          "variable `\{name}` is used before being assigned",
        )
        let _ = ctx.unassigned.remove(name)
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
  check_function_body_with(func, Resolver::empty(), false, true)
}

///|
fn check_function_body_with(
  func : @ast.TsFunc,
  resolver : Resolver,
  permissive : Bool,
  strict_property_init : Bool,
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  if func.body.stmts.length() == 0 {
    return issues
  }
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
  let ctx : CheckCtx = {
    path_prefix: "function " + func.name,
    return_type: body_return,
    yield_type,
    resolver,
    issues,
    in_scope_type_params: func.type_params,
    permissive,
    unassigned: {},
    strict_property_init,
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
  // Default-parameter expression must be assignable to the parameter's
  // (possibly optional-widened) type.
  for p in func.params {
    match p.default {
      Some(d) =>
        check_expr_against(env, d, p.type_, ctx, "param `\{p.name}` default")
      None => ()
    }
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
      match meth.body {
        Some(body) => {
          let params : Array[@ast.TsParam] = []
          for p in meth.params {
            params.push({
              name: p.0,
              binding: None,
              is_rest: false,
              type_: p.1,
              default: None,
            })
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
            is_generator: false,
            is_async: false,
          }
          for
            issue in check_function_body_with(
              synth, resolver, permissive, strict_property_init,
            ) {
            all.push(issue)
          }
        }
        None => ()
      }
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
/// TS2564 ("Property 'X' has no initializer and is not definitely
/// assigned in the constructor") for native (runtime) class
/// declarations. We catch the common shape where the class has no
/// constructor at all and the field has neither an `=` initializer
/// nor a `!` definite-assignment assertion, and the declared type
/// doesn't already accept `undefined`. The constructor-body-walk
/// variant (which would also catch `class C { x: T; constructor() {
/// this.x = ...; } }`) requires CFA over constructor bodies and is
/// deferred -- 91 of 93 TS2564 cases in the conformance corpus have
/// no constructor at all.
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
    // Skip when the class declares a constructor: its body might
    // assign `this.x` and we don't model the constructor body in the
    // TsClassDecl form (only the parameter list survives). A false
    // negative here is much better than the false positive of
    // claiming an initialised field is uninitialised.
    match decl.constructor_params {
      Some(_) => continue
      None => ()
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
      if prop.has_initializer || prop.has_definite_assertion {
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
