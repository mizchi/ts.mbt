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
  }
}

///|
/// TypeScript interface declaration merging. Two `interface Foo {...}`
/// blocks with the same name combine into one whose member list is the
/// union of both bodies. Later-declared members for the same key
/// override earlier ones (TS itself rejects conflicting overrides at
/// declaration time, but the checker doesn't enforce that — last writer
/// wins for the lookup).
fn merge_interfaces(a : @ast.TsInterface, b : @ast.TsInterface) -> @ast.TsInterface {
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
    r.globals[prefix + imp.name] = @ast.TsType::Func(
      param_types,
      imp.return_type,
    )
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
    r.globals[prefix + f.name] = @ast.TsType::Func(param_types, ret)
    r.signatures[prefix + f.name] = f.params
    r.func_type_params[prefix + f.name] = f.type_params
    r.func_const_type_params[prefix + f.name] = f.const_type_params
  }
  for ns in module_.namespaces {
    let ns_prefix = prefix + ns.name + "."
    Resolver::ingest_module(r, ns.module_, ns_prefix)
    // Namespace + class static-side merging: when a `namespace X` is
    // declared alongside `class X`, the namespace's exports are
    // exposed as static members on the class. Wire each top-level
    // function / value / class into the class lookup by also
    // registering them under the `<Class>.<member>` key so PropAccess
    // resolution that goes through the class shape can find them.
    let cls_key = prefix + ns.name
    let _ = r.classes.get(cls_key) // existence check; presence is enough
    // (`r.globals[ns_prefix + name]` is already set above by the
    // recursive ingest; the qualified key is what lookup_class_field
    // would walk through.)
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
            Some(alias) => {
              seen[n] = true
              cur = alias.type_
            }
            None => keep_going = false
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
    _ => None
  }
}

///|
fn Resolver::lookup_field(
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
      for entry in entries {
        match entry.0 {
          Literal(name) if name == field => return Some(entry.1)
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
      match (try? @strconv.parse_int(field)) {
        Ok(idx) if idx >= 0 && idx < items.length() => Some(items[idx])
        _ =>
          match field {
            "length" => Some(@ast.TsType::Number)
            _ => None
          }
      }
    String_ | Literal(_) => string_prototype_member(field)
    _ => None
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
fn global_namespace_method(namespace : String, method : String) -> @ast.TsType? {
  let s = @ast.TsType::String_
  let n = @ast.TsType::Number
  let b = @ast.TsType::Boolean
  let any = @ast.TsType::Any
  let str_arr = @ast.TsType::Array(s)
  match (namespace, method) {
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
  namespace : String,
  method : String,
  args : Array[@ast.TsExpr],
) -> @ast.TsType? {
  match (namespace, method, args) {
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
  method : String,
) -> (Array[@ast.TsType], @ast.TsType)? {
  match self.lookup_field(recv, method) {
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
}

///|
fn ExprEnv::new() -> ExprEnv {
  { vars: {} }
}

///|
fn ExprEnv::bind(self : ExprEnv, name : String, ty : @ast.TsType) -> Unit {
  self.vars[name] = ty
}

///|
fn ExprEnv::lookup(self : ExprEnv, name : String) -> @ast.TsType? {
  self.vars.get(name)
}

///|
/// Capture a snapshot of `(name, type)` pairs currently in the env so we can
/// fully restore — including overwritten bindings — when a block exits. Used
/// for both lexical scope and narrowing.
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
}

///|
fn record(ctx : CheckCtx, sub_path : String, message : String) -> Unit {
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
      let lt = infer_expr(env, resolver, l)
      let rt = infer_expr(env, resolver, r)
      infer_binop(op, lt, rt)
    }
    UnaryOp(op, inner) => {
      let _ = infer_expr(env, resolver, inner)
      infer_unary(op)
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
          Spread(_) => @ast.TsType::Any
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
      let _ = infer_expr(env, resolver, callee)
      for a in args {
        let _ = infer_expr(env, resolver, a)
      }
      @ast.TsType::Any
    }
    MethodCall(receiver, method, args) => {
      // Static namespace dispatch: `Object.keys(...)`, `Math.max(...)`,
      // `Promise.resolve(...)` etc. — recognise the receiver by its bare
      // identifier rather than its inferred type so we don't depend on
      // ambient globals being declared.
      match receiver {
        Var(name) =>
          match global_namespace_method(name, method) {
            Some(sig) =>
              // Apply per-method generic-style inference for the chosen
              // static method, falling back to the conventional `Func`
              // shape when no special path applies.
              match
                global_static_method_special(env, resolver, name, method, args) {
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
      match (elem_opt, method, args) {
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
      match (promise_inner_opt, method, args) {
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
      match resolver.lookup_method_sig(recv_ty, method) {
        Some((_params, ret)) => {
          for a in args {
            let _ = infer_expr(env, resolver, a)
          }
          ret
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
    Yield(_) | YieldStar(_) => @ast.TsType::Any
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
        None => @ast.TsType::Any
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
        let val_ty = infer_expr(env, resolver, entry.1)
        fields.push((@ast.TsType::Literal(entry.0), val_ty))
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
      // fall back to inferring from the body expression for the
      // `(x) => expr` shorthand.
      let ret = if is_checkable(declared_ret) {
        declared_ret
      } else {
        match body {
          ArrowExpr(e) => infer_expr(env, resolver, e)
          ArrowBlock(_) => @ast.TsType::Any
        }
      }
      @ast.TsType::Func(param_types, wrap_async_return(is_async, ret))
    }
    FuncExpr(f) => {
      let param_types : Array[@ast.TsType] = []
      for p in f.params {
        param_types.push(p.type_)
      }
      @ast.TsType::Func(
        param_types,
        wrap_async_return(f.is_async, f.return_type),
      )
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
      let inner_ty = infer_expr(env, resolver, inner)
      narrow_union(inner_ty, @ast.TsType::Undefined)
    }
    // JSX element / fragment. The value itself is opaque at the type
    // level (we don't model React's `ReactNode` / `JSX.Element`), so
    // return `Any`. The embedded `{expr}` sub-expressions are walked
    // by `check_call_args_in_expr` for diagnostic recursion.
    JsxElement(_, _, _) => @ast.TsType::Any
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
  match callee {
    // `paramName is T` is a boolean at the value level — calls to a type
    // predicate function return `Boolean`. The predicate effect is applied
    // via the narrowing path in `if (isFoo(v))`.
    Func(_, TypePredicate(_, _)) => @ast.TsType::Boolean
    // `asserts paramName [is T]` returns `void` at the value level — the
    // narrowing effect applies to all statements after the call site.
    Func(_, AssertsPredicate(_, _)) => @ast.TsType::Void
    Func(_, ret) => ret
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
  match recv {
    Array(elem) => elem
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
        _ => @ast.TsType::Any
      }
    // Interface receivers — `obj[key]` runs through `lookup_field` so
    // string-literal indices match named fields and (failing that) the
    // index signature. Non-literal indices on an interface fall through
    // to the catch-all `Any` since we can't narrow the lookup.
    Named(_) | Applied(_, _) =>
      match idx_expr {
        StringLit(key) =>
          match resolver.lookup_field(recv, key) {
            Some(t) => t
            None => @ast.TsType::Any
          }
        IntLit(i) =>
          match resolver.lookup_field(recv, i.to_string()) {
            Some(t) => t
            None => @ast.TsType::Any
          }
        _ => @ast.TsType::Any
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
        (Number, Number) | (Number, Int) | (Int, Number) | (Int, Int) =>
          @ast.TsType::Number
        (NumberLiteral(_), _) | (_, NumberLiteral(_)) => @ast.TsType::Number
        (Any, _) | (_, Any) => @ast.TsType::Any
        _ => @ast.TsType::Number
      }
    Sub | Mul | Div | Mod | Pow | Shl | Shr | UShr | BitAnd | BitOr | BitXor =>
      @ast.TsType::Number
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
    // `a || b` — when `a` is truthy the result is `a`; otherwise `b`.
    Or => narrow_union(l, r)
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
    // Contextual typing for array literals: `[a, b]` against a tuple type
    // `[T1, T2]` checks each element against the corresponding slot. Without
    // this hop the array literal would infer as `Array<elem>` and fail
    // assignability against `Tuple(...)`.
    (ArrayLit(items), Tuple(slots)) => {
      check_array_lit_against_tuple(env, items, slots, ctx, sub_path)
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
  let inferred = infer_expr(env, ctx.resolver, expr)
  if !is_checkable(inferred) {
    return
  }
  if !is_assignable_to(inferred, expected) {
    let detail = "expected `\{type_display(expected)}` but got `\{type_display(inferred)}`"
    record(ctx, sub_path, detail)
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
  // Per-field type checks for each provided key.
  for entry in entries {
    let key = entry.0
    let value = entry.1
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
    provided[entry.0] = true
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
        None => ()
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
        None => ()
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
    None => (params.length(), params.length())
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
      Tuple(_) => @ast.TsType::Any
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
              @ast.TsType::Any
            }
          Array(t) => t
          _ => @ast.TsType::Any
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
      None => @ast.TsType::Any
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
        ("Set", 1) | ("Iterable", 1) | ("IterableIterator", 1) => args[0]
        ("Generator", n) if n >= 1 => args[0]
        ("Map", 2) => @ast.TsType::Tuple([args[0], args[1]])
        ("ReadonlyArray", 1) | ("ReadonlySet", 1) => args[0]
        _ => @ast.TsType::Any
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
fn is_null_or_undefined(t : @ast.TsType) -> Bool {
  match t {
    Null | Undefined => true
    _ => false
  }
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
  let variants = union_components(recv)
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
              let then_ty = narrow_keep(cur, fn(v) {
                match v {
                  Named(n) => n == class_name
                  _ => false
                }
              })
              let then_resolved = match then_ty {
                Never => class_ty
                _ => then_ty
              }
              pair_pos.push((key, then_resolved))
              let else_ty = narrow_remove(cur, fn(v) {
                match v {
                  Named(n) => n == class_name
                  _ => false
                }
              })
              pair_neg.push((key, else_ty))
            }
            _ => ()
          }
        }
        // `"key" in obj` — narrow `obj`'s union to members that own `key`.
        In =>
          match (left, right) {
            (StringLit(key), Var(name)) => {
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
      // Positive: narrow to T. If `keep` produces Never (e.g. cur is Any),
      // fall back to target.
      let then_ty = narrow_keep(cur, fn(v) { is_assignable_to(v, target) })
      let then_resolved = match then_ty {
        Never => target
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
/// Resolve the current type of a `name.prop` access — first via any
/// narrowing binding under the synthetic `name.prop` env key, then via
/// the receiver's structural shape.
fn prop_access_current_type(
  env : ExprEnv,
  resolver : Resolver,
  name : String,
  prop : String,
) -> @ast.TsType {
  match env.lookup(name + "." + prop) {
    Some(t) => t
    None => {
      let recv_ty = env_lookup_full(env, resolver, name)
      match resolver.lookup_field(recv_ty, prop) {
        Some(t) => t
        None => @ast.TsType::Any
      }
    }
  }
}

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
        let prefix = key[:open_idx].to_string()
        let inner = key[open_idx + 1:key.length() - 1].to_string()
        let prefix_ty = narrowing_current_type(env, resolver, prefix)
        let elem = index_into_type(resolver, prefix_ty, inner)
        return elem
      }
      None => ()
    }
  }
  match key.rev_find(".") {
    Some(idx) => {
      let prefix = key[:idx].to_string()
      let leaf = key[idx + 1:].to_string()
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
  let is_numeric = (try? @strconv.parse_int(field)) is Ok(_)
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
    let key = inner[1:inner.length() - 1].to_string()
    return match resolver.lookup_field(shape, key) {
      Some(t) => t
      None => @ast.TsType::Any
    }
  }
  // Numeric index — read tuple slot or array element.
  let idx = (try? @strconv.parse_int(inner)) is Ok(_)
  if idx {
    match shape {
      Array(elem) => return elem
      Applied("Array", [elem]) | Applied("ReadonlyArray", [elem]) => return elem
      Tuple(items) =>
        match (try? @strconv.parse_int(inner)) {
          Ok(i) if i >= 0 && i < items.length() => return items[i]
          _ => return @ast.TsType::Any
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
      check_expr_against(env, init, declared, ctx, "binding `\{name}` init")
    }
    Var(@ast.TsBinding::Array(ab), declared, init)
    | Let(@ast.TsBinding::Array(ab), declared, init)
    | Const(@ast.TsBinding::Array(ab), declared, init) => {
      check_call_args_in_expr(env, init, ctx)
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
      match env.lookup(name) {
        Some(target_ty) =>
          check_expr_against(env, e, target_ty, ctx, "assign `\{name}`")
        None => ()
      }
    }
    CompoundAssign(name, op, e) => {
      check_call_args_in_expr(env, e, ctx)
      // For arithmetic compound ops, the right-hand operand must be numeric
      // if the variable is numeric. We delegate to `infer_binop` to derive
      // the equivalent simple assignment's required type.
      match env.lookup(name) {
        Some(target_ty) =>
          check_compound_assign(env, target_ty, op, e, ctx, name)
        None => ()
      }
    }
    PropAssign(recv, prop, value) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, value, ctx)
      let recv_ty = infer_expr(env, ctx.resolver, recv)
      match ctx.resolver.lookup_field(recv_ty, prop) {
        Some(target_ty) =>
          check_expr_against(env, value, target_ty, ctx, "assign `.\{prop}`")
        None => ()
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
    ForOf(_, binding, declared, iter, body) => {
      check_call_args_in_expr(env, iter, ctx)
      let elem_ty = if is_checkable(declared) {
        declared
      } else {
        let iter_ty = infer_expr(env, ctx.resolver, iter)
        for_of_element_type(ctx.resolver, iter_ty)
      }
      let pre = env.full_snapshot()
      bind_pattern(env, ctx, binding, elem_ty)
      check_block(env, body, ctx)
      env.restore_from(pre)
    }
    ForAwaitOf(_, binding, declared, iter, body) => {
      check_call_args_in_expr(env, iter, ctx)
      let elem_ty = if is_checkable(declared) {
        declared
      } else {
        let iter_ty = infer_expr(env, ctx.resolver, iter)
        // `for await (const x of asyncIter)` — unwrap `Promise<T>` and treat
        // the inner type as the iterable.
        let unwrapped = unwrap_async_return(true, iter_ty)
        for_of_element_type(ctx.resolver, unwrapped)
      }
      let pre = env.full_snapshot()
      bind_pattern(env, ctx, binding, elem_ty)
      check_block(env, body, ctx)
      env.restore_from(pre)
    }
    ForIn(_, binding, declared, iter, body) => {
      // `for (key in obj)` — `key` is always `string` in TS; honor an
      // explicit annotation if the source pinned a narrower form.
      check_call_args_in_expr(env, iter, ctx)
      let key_ty = if is_checkable(declared) {
        declared
      } else {
        @ast.TsType::String_
      }
      let pre = env.full_snapshot()
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
      for case_ in cases {
        match case_.test_expr {
          Some(e) => check_call_args_in_expr(env, e, ctx)
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
              env, ctx.resolver, obj_name, prop, cases,
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
        _ => ()
      }
      for a in args {
        check_call_args_in_expr(env, a, ctx)
      }
    }
    CallExpr(callee, args) => {
      let callee_ty = infer_expr(env, ctx.resolver, callee)
      match callee_ty {
        Func(params, _) => check_arguments(env, params, args, ctx, "call")
        _ => ()
      }
      check_call_args_in_expr(env, callee, ctx)
      for a in args {
        check_call_args_in_expr(env, a, ctx)
      }
    }
    MethodCall(receiver, method, args) => {
      // Static-namespace dispatch: `Math.max(...)`, `JSON.stringify(...)`.
      // Recognised by the bare-identifier shape of the receiver.
      let static_params : Array[@ast.TsType]? = match receiver {
        Var(name) =>
          match global_namespace_method(name, method) {
            Some(Func(params, _)) => Some(params)
            _ => None
          }
        _ => None
      }
      match static_params {
        Some(params) =>
          check_arguments(env, params, args, ctx, "call `\{method}`")
        None => {
          let recv_ty = infer_expr(env, ctx.resolver, receiver)
          match ctx.resolver.lookup_method_sig(recv_ty, method) {
            Some((params, _)) =>
              check_arguments(env, params, args, ctx, "call `\{method}`")
            None => ()
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
    BinOp(_, l, r) => {
      check_call_args_in_expr(env, l, ctx)
      check_call_args_in_expr(env, r, ctx)
    }
    UnaryOp(_, inner) => check_call_args_in_expr(env, inner, ctx)
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
    PropAccess(recv, _) => check_call_args_in_expr(env, recv, ctx)
    IndexAccess(recv, idx) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, idx, ctx)
    }
    AssignExpr(name, v) => {
      check_call_args_in_expr(env, v, ctx)
      match env.lookup(name) {
        Some(target_ty) =>
          check_expr_against(env, v, target_ty, ctx, "assign `\{name}`")
        None => ()
      }
    }
    CompoundAssignExpr(target, op, v) => {
      check_call_args_in_expr(env, target, ctx)
      check_call_args_in_expr(env, v, ctx)
      match target {
        Var(name) =>
          match env.lookup(name) {
            Some(target_ty) =>
              check_compound_assign(env, target_ty, op, v, ctx, name)
            None => ()
          }
        _ => ()
      }
    }
    AssignPattern(_, v) | Spread(v) | Await(v) =>
      check_call_args_in_expr(env, v, ctx)
    PropAssignExpr(recv, prop, v) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, v, ctx)
      let recv_ty = infer_expr(env, ctx.resolver, recv)
      match ctx.resolver.lookup_field(recv_ty, prop) {
        Some(target_ty) =>
          check_expr_against(env, v, target_ty, ctx, "assign `.\{prop}`")
        None => ()
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
    As(inner, _) | NonNull(inner) | OptionalChain(inner) =>
      check_call_args_in_expr(env, inner, ctx)
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
    MethodCall(_, method, args) =>
      if method == "map" && args.length() >= 1 {
        walk_map_callback_for_key(args[0], ctx)
      }
    CallExpr(callee, args) =>
      match callee {
        PropAccess(_, method) =>
          if method == "map" && args.length() >= 1 {
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
  check_function_body_with(func, Resolver::empty())
}

///|
fn check_function_body_with(
  func : @ast.TsFunc,
  resolver : Resolver,
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  if func.body.stmts.length() == 0 {
    return issues
  }
  let env = ExprEnv::new()
  for p in func.params {
    env.bind(p.name, p.type_)
  }
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
      Applied("Generator", args)
      | Applied("AsyncGenerator", args) if args.length() >= 1 => args[0]
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
    !block_always_exits(func.body) {
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
  let resolver = Resolver::from_module(module_)
  let all : Array[ExprIssue] = []
  for func in module_.funcs {
    for issue in check_function_body_with(func, resolver) {
      all.push(issue)
    }
  }
  // Class method bodies — when the parser supplied a body, walk it the
  // same way top-level functions are walked. Synthesise a `TsFunc` so
  // the existing checker pipeline can run unchanged. The synthetic
  // function name embeds the class + method names so any reported
  // issues point at the source location.
  for cls in module_.classes {
    for method in cls.methods {
      match method.body {
        Some(body) => {
          let params : Array[@ast.TsParam] = []
          for p in method.params {
            params.push({
              name: p.0,
              binding: None,
              is_rest: false,
              type_: p.1,
              default: None,
            })
          }
          let synth : @ast.TsFunc = {
            name: cls.name + "." + method.name,
            type_params: method.type_params,
            params,
            return_type: method.return_type,
            body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }
          for issue in check_function_body_with(synth, resolver) {
            all.push(issue)
          }
        }
        None => ()
      }
    }
  }
  all
}
