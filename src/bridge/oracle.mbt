// Hybrid type-resolution oracle.
//
// The bridge keeps its own TypeScript type machinery for the common case,
// but cannot reliably reduce the long tail of conditional / mapped /
// `keyof T[K]` aliases. The Node.js helper at `scripts/oracle/resolve-types.mjs`
// runs the official TypeScript compiler over the same .d.ts entries and
// emits a JSON cache of fully-resolved types; this file deserialises that
// cache into a `Map[String, TsType]` so callers can splice the oracle's
// answers into the working `TsModule` before lowering.
//
// Wire format mirrors the script: `{ resolutions: [{ key, ok, type? }, ...] }`
// with `type` shaped as documented at the top of the helper script.

///|
/// Read an oracle cache JSON file and return a `name -> TsType` map of the
/// successful resolutions. Failed entries (missing alias, parse error,
/// unknown shape on the JS side) are dropped silently — the caller falls
/// back to the in-house lowering for those names.
pub async fn read_oracle_cache(path : String) -> Map[String, @ast.TsType] {
  let text = @fs.read_file(path).text() catch { _ => return {} }
  let json = @json.parse(text) catch { _ => return {} }
  let resolutions = match json {
    Object(fields) =>
      match fields.get("resolutions") {
        Some(Array(items)) => items
        _ => return {}
      }
    _ => return {}
  }
  let result : Map[String, @ast.TsType] = {}
  for entry in resolutions {
    match entry {
      Object(fields) => {
        let key = match fields.get("key") {
          Some(String(s)) => s
          _ => continue
        }
        let ok = match fields.get("ok") {
          Some(True) => true
          _ => false
        }
        if !ok {
          continue
        }
        let type_node = match fields.get("type") {
          Some(node) => node
          None => continue
        }
        match deserialize_oracle_type(type_node) {
          Some(t) => result[key] = t
          None => ()
        }
      }
      _ => ()
    }
  }
  result
}

///|
/// Convert one JSON node from the oracle cache into a bridge-friendly
/// `TsType`. Returns `None` for shapes the helper marked `unknown_shape`,
/// or for malformed payloads — callers should treat that as "oracle
/// declined" and keep the in-house lowering.
fn deserialize_oracle_type(node : Json) -> @ast.TsType? {
  match node {
    Object(fields) => {
      let kind = match fields.get("kind") {
        Some(String(s)) => s
        _ => return None
      }
      match kind {
        "any" => Some(@ast.TsType::Any)
        "void" => Some(@ast.TsType::Void)
        "null" => Some(@ast.TsType::Null)
        "undefined" => Some(@ast.TsType::Undefined)
        "never" => Some(@ast.TsType::Never)
        "primitive" =>
          match fields.get("name") {
            Some(String("string")) => Some(@ast.TsType::String_)
            Some(String("number")) => Some(@ast.TsType::Number)
            Some(String("boolean")) => Some(@ast.TsType::Boolean)
            Some(String("bigint")) => Some(@ast.TsType::BigInt)
            Some(String("symbol")) => Some(@ast.TsType::Symbol)
            _ => None
          }
        "literal" => {
          let value = match fields.get("value") {
            Some(String(s)) => s
            _ => return None
          }
          match fields.get("literal_kind") {
            Some(String("string")) => Some(@ast.TsType::Literal(value))
            Some(String("number")) => Some(@ast.TsType::NumberLiteral(value))
            Some(String("bigint")) => Some(@ast.TsType::BigIntLiteral(value))
            Some(String("bool")) =>
              Some(@ast.TsType::BooleanLiteral(value == "true"))
            _ => None
          }
        }
        "named" =>
          match fields.get("name") {
            Some(String(name)) => Some(@ast.TsType::Named(name))
            _ => None
          }
        "applied" => {
          let name = match fields.get("name") {
            Some(String(s)) => s
            _ => return None
          }
          let args = match fields.get("args") {
            Some(Array(arr)) => arr
            _ => return None
          }
          let lowered : Array[@ast.TsType] = []
          for arg in args {
            match deserialize_oracle_type(arg) {
              Some(t) => lowered.push(t)
              None => return None
            }
          }
          Some(@ast.TsType::Applied(name, lowered))
        }
        "array" =>
          match fields.get("element") {
            Some(elem) =>
              match deserialize_oracle_type(elem) {
                Some(t) => Some(@ast.TsType::Array(t))
                None => None
              }
            None => None
          }
        "tuple" => {
          let items = match fields.get("items") {
            Some(Array(arr)) => arr
            _ => return None
          }
          let lowered : Array[@ast.TsType] = []
          for it in items {
            match deserialize_oracle_type(it) {
              Some(t) => lowered.push(t)
              None => return None
            }
          }
          Some(@ast.TsType::Tuple(lowered))
        }
        "union" | "intersection" => {
          let parts_json = match fields.get("parts") {
            Some(Array(arr)) => arr
            _ => return None
          }
          let parts : Array[@ast.TsType] = []
          for p in parts_json {
            match deserialize_oracle_type(p) {
              Some(t) => parts.push(t)
              None => return None
            }
          }
          if kind == "union" {
            Some(@ast.TsType::Union(parts))
          } else {
            Some(@ast.TsType::Intersection(parts))
          }
        }
        "func" => {
          let params_json = match fields.get("params") {
            Some(Array(arr)) => arr
            _ => return None
          }
          let return_node = match fields.get("return") {
            Some(n) => n
            None => return None
          }
          let params : Array[@ast.TsType] = []
          for p in params_json {
            match deserialize_oracle_type(p) {
              Some(t) => params.push(t)
              None => return None
            }
          }
          let return_type = match deserialize_oracle_type(return_node) {
            Some(t) => t
            None => return None
          }
          Some(@ast.TsType::Func(params, return_type))
        }
        "object" => {
          let entries_json = match fields.get("entries") {
            Some(Array(arr)) => arr
            _ => return None
          }
          let entries : Array[(@ast.TsType, @ast.TsType)] = []
          for e in entries_json {
            match e {
              Object(entry_fields) => {
                let key = match entry_fields.get("key") {
                  Some(k) =>
                    match deserialize_oracle_type(k) {
                      Some(t) => t
                      None => return None
                    }
                  None => return None
                }
                let value = match entry_fields.get("value") {
                  Some(v) =>
                    match deserialize_oracle_type(v) {
                      Some(t) => t
                      None => return None
                    }
                  None => return None
                }
                entries.push((key, value))
              }
              _ => return None
            }
          }
          Some(@ast.TsType::Object(entries))
        }
        // `unknown_shape` means the JS oracle could not represent the type
        // in the wire schema (mapped types, infer fragments, template
        // literal types with type substitutions, etc.). Treat as a decline.
        _ => None
      }
    }
    _ => None
  }
}

///|
/// Splice an oracle cache into a parsed `TsModule` by:
///   (1) upserting the resolved types as type-alias declarations, and
///   (2) substituting every `Named(name)` reference inside funcs /
///       interfaces / classes / values / other type aliases with the
///       resolved body.
///
/// Step (2) is what actually moves the needle for the bridge: the
/// downstream emit pipeline drops `type_aliases` from the lowered module
/// before checker validation, so an alias-only update wouldn't show up
/// anywhere. The substitution rewrites every consumer in place.
pub fn apply_oracle_resolutions(
  module_ : @ast.TsModule,
  resolutions : Map[String, @ast.TsType],
) -> Unit {
  for entry in resolutions {
    let (name, type_) = entry
    let mut found = false
    for i, existing in module_.type_aliases {
      if existing.name == name {
        module_.type_aliases[i] = {
          name,
          type_params: existing.type_params,
          type_param_bounds: existing.type_param_bounds,
          type_,
        }
        found = true
        break
      }
    }
    if !found {
      module_.type_aliases.push({
        name,
        type_params: [],
        type_param_bounds: [],
        type_,
      })
    }
  }
  // Substitute every `Named(name)` reference (and matching `Applied`
  // heads) in the module so downstream lowering sees the resolved shape
  // even when the alias is later stripped.
  for i, ta in module_.type_aliases {
    module_.type_aliases[i] = {
      ..ta,
      type_: substitute_named_types(ta.type_, resolutions),
    }
  }
  for i, iface in module_.interfaces {
    let new_fields : Array[(String, @ast.TsType)] = []
    for f in iface.fields {
      new_fields.push((f.0, substitute_named_types(f.1, resolutions)))
    }
    module_.interfaces[i] = { ..iface, fields: new_fields }
  }
  for i, func in module_.funcs {
    let new_params : Array[@ast.TsParam] = []
    for p in func.params {
      new_params.push({
        ..p,
        type_: substitute_named_types(p.type_, resolutions),
      })
    }
    module_.funcs[i] = {
      ..func,
      params: new_params,
      return_type: substitute_named_types(func.return_type, resolutions),
    }
  }
  for i, value in module_.values {
    module_.values[i] = {
      ..value,
      type_: substitute_named_types(value.type_, resolutions),
    }
  }
  for i, class_ in module_.classes {
    let new_props : Array[@ast.TsClassPropertyDecl] = []
    for p in class_.properties {
      new_props.push({
        ..p,
        type_: substitute_named_types(p.type_, resolutions),
      })
    }
    let new_methods : Array[@ast.TsClassMethodDecl] = []
    for m in class_.methods {
      let new_params : Array[(String, @ast.TsType)] = []
      for mp in m.params {
        new_params.push((mp.0, substitute_named_types(mp.1, resolutions)))
      }
      new_methods.push({
        ..m,
        params: new_params,
        return_type: substitute_named_types(m.return_type, resolutions),
      })
    }
    module_.classes[i] = {
      ..class_,
      properties: new_props,
      methods: new_methods,
    }
  }
}

///|
/// Recursively rewrite every `Named(n)` (or `Applied(n, _)`) reference in
/// `t` with the type bound to `n` in `table`. Args of an `Applied` head
/// that hits the table are dropped on purpose — the oracle has already
/// resolved the alias against its declared type parameters, so re-passing
/// args would re-introduce ambiguity. Recurses through all compound
/// `TsType` shapes so deeply-nested references are rewritten too.
fn substitute_named_types(
  t : @ast.TsType,
  table : Map[String, @ast.TsType],
) -> @ast.TsType {
  match t {
    @ast.TsType::Named(name) =>
      match table.get(name) {
        Some(r) => r
        None => t
      }
    @ast.TsType::Applied(name, args) => {
      let new_args : Array[@ast.TsType] = []
      for a in args {
        new_args.push(substitute_named_types(a, table))
      }
      match table.get(name) {
        Some(r) => r
        None => @ast.TsType::Applied(name, new_args)
      }
    }
    @ast.TsType::Array(inner) =>
      @ast.TsType::Array(substitute_named_types(inner, table))
    @ast.TsType::Tuple(items) => {
      let new_items : Array[@ast.TsType] = []
      for it in items {
        new_items.push(substitute_named_types(it, table))
      }
      @ast.TsType::Tuple(new_items)
    }
    @ast.TsType::Union(parts) => {
      let new_parts : Array[@ast.TsType] = []
      for p in parts {
        new_parts.push(substitute_named_types(p, table))
      }
      @ast.TsType::Union(new_parts)
    }
    @ast.TsType::Intersection(parts) => {
      let new_parts : Array[@ast.TsType] = []
      for p in parts {
        new_parts.push(substitute_named_types(p, table))
      }
      @ast.TsType::Intersection(new_parts)
    }
    @ast.TsType::Func(params, return_type) => {
      let new_params : Array[@ast.TsType] = []
      for p in params {
        new_params.push(substitute_named_types(p, table))
      }
      @ast.TsType::Func(new_params, substitute_named_types(return_type, table))
    }
    @ast.TsType::Object(entries) => {
      let new_entries : Array[(@ast.TsType, @ast.TsType)] = []
      for e in entries {
        new_entries.push(
          (
            substitute_named_types(e.0, table),
            substitute_named_types(e.1, table),
          ),
        )
      }
      @ast.TsType::Object(new_entries)
    }
    @ast.TsType::Conditional(s, target, x, y) =>
      @ast.TsType::Conditional(
        substitute_named_types(s, table),
        substitute_named_types(target, table),
        substitute_named_types(x, table),
        substitute_named_types(y, table),
      )
    @ast.TsType::IndexedAccess(target, key) =>
      @ast.TsType::IndexedAccess(
        substitute_named_types(target, table),
        substitute_named_types(key, table),
      )
    @ast.TsType::TemplateLiteralType(parts, args) => {
      let new_args : Array[@ast.TsType] = []
      for a in args {
        new_args.push(substitute_named_types(a, table))
      }
      @ast.TsType::TemplateLiteralType(parts, new_args)
    }
    _ => t
  }
}
