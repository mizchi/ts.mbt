// Type constraint tracking for type inference and error detection.

///|
/// A type constraint that must be satisfied.
pub(all) enum TypeConstraint {
  /// left must be assignable to right
  Assignable(@ast.TsType, @ast.TsType, SourceLoc)
  /// expression must have specific type
  MustBe(@ast.TsExpr, @ast.TsType, SourceLoc)
  /// two types must be equal
  Equal(@ast.TsType, @ast.TsType, SourceLoc)
}

///|
/// Object type with tracked properties.
pub(all) struct ObjectType {
  properties : Map[String, @ast.TsType]
  index_type : @ast.TsType? // For index signatures like [key: string]: T
  mut is_class : Bool
  mut name : String? // Class/interface name if applicable
}

///|
/// Create new object type.
pub fn ObjectType::new() -> ObjectType {
  { properties: {}, index_type: None, is_class: false, name: None }
}

///|
/// Create object type from AST object literal type.
pub fn ObjectType::from_props(
  props : Array[(@ast.TsType, @ast.TsType)],
) -> ObjectType {
  let obj = ObjectType::new()
  for prop in props {
    match prop.0 {
      @ast.TsType::Literal(key) => obj.properties[key] = prop.1
      _ => ()
    }
  }
  obj
}

///|
/// Get property type.
pub fn ObjectType::get_prop(self : ObjectType, name : String) -> @ast.TsType? {
  self.properties.get(name)
}

///|
/// Set property type.
pub fn ObjectType::set_prop(
  self : ObjectType,
  name : String,
  type_ : @ast.TsType,
) -> Unit {
  self.properties[name] = type_
}

///|
/// Type registry for tracking object types and type aliases.
pub(all) struct TypeRegistry {
  // Named object types (classes, interfaces)
  object_types : Map[String, ObjectType]
  // Type aliases
  type_aliases : Map[String, @ast.TsType]
  // Type parameters in current scope
  type_params : Array[String]
}

///|
pub fn TypeRegistry::new() -> TypeRegistry {
  { object_types: {}, type_aliases: {}, type_params: [] }
}

///|
/// Register object type by name.
pub fn TypeRegistry::register_object(
  self : TypeRegistry,
  name : String,
  obj : ObjectType,
) -> Unit {
  self.object_types[name] = obj
}

///|
/// Get object type by name.
pub fn TypeRegistry::get_object(
  self : TypeRegistry,
  name : String,
) -> ObjectType? {
  self.object_types.get(name)
}

///|
/// Type error from constraint violation.
pub(all) struct TypeError {
  message : String
  loc : SourceLoc
  expected : @ast.TsType
  actual : @ast.TsType
}

///|
pub fn TypeError::to_string(self : TypeError) -> String {
  "TypeError at line \{self.loc.line}: \{self.message} (expected \{self.expected.to_string()}, got \{self.actual.to_string()})"
}

///|
/// Constraint solver for type checking.
pub(all) struct ConstraintSolver {
  constraints : Array[TypeConstraint]
  errors : Array[TypeError]
  registry : TypeRegistry
}

///|
pub fn ConstraintSolver::new(registry : TypeRegistry) -> ConstraintSolver {
  { constraints: [], errors: [], registry }
}

///|
/// Add a constraint.
pub fn ConstraintSolver::add_constraint(
  self : ConstraintSolver,
  constraint : TypeConstraint,
) -> Unit {
  self.constraints.push(constraint)
}

///|
/// Check if type a is assignable to type b.
pub fn is_assignable(a : @ast.TsType, b : @ast.TsType) -> Bool {
  // Same type
  if a == b {
    return true
  }
  // Any is assignable to/from anything
  match (a, b) {
    (@ast.TsType::Any, _) => true
    (_, @ast.TsType::Any) => true
    // Never is assignable to anything, but nothing is assignable to never
    (@ast.TsType::Never, _) => true
    (_, @ast.TsType::Never) => false
    // Null is assignable to object types
    (@ast.TsType::Null, @ast.TsType::Object(_)) => true
    // Undefined is assignable to void
    (@ast.TsType::Undefined, @ast.TsType::Void) => true
    // Number/Int compatibility
    (@ast.TsType::Int, @ast.TsType::Number) => true
    (@ast.TsType::Number, @ast.TsType::Int) => false // Number may have decimals
    // Array compatibility
    (@ast.TsType::Array(elem_a), @ast.TsType::Array(elem_b)) =>
      is_assignable(elem_a, elem_b)
    (@ast.TsType::Applied(name_a, _), @ast.TsType::Applied(name_b, _)) =>
      name_a == name_b
    (@ast.TsType::Applied(name_a, _), @ast.TsType::Named(name_b)) =>
      name_a == name_b
    (@ast.TsType::Named(name_a), @ast.TsType::Applied(name_b, _)) =>
      name_a == name_b
    // Union type: a is assignable if assignable to any member
    (_, @ast.TsType::Union(types)) =>
      types.iter().any(fn(t) { is_assignable(a, t) })
    // Union type on left: all members must be assignable
    (@ast.TsType::Union(types), _) =>
      types.iter().all(fn(t) { is_assignable(t, b) })
    // Intersection type: must be assignable to all members
    (_, @ast.TsType::Intersection(types)) =>
      types.iter().all(fn(t) { is_assignable(a, t) })
    // Function type compatibility
    (@ast.TsType::Func(params_a, ret_a), @ast.TsType::Func(params_b, ret_b)) => {
      // Contravariant parameters, covariant return
      if params_a.length() != params_b.length() {
        return false
      }
      for i = 0; i < params_a.length(); i = i + 1 {
        if !is_assignable(params_b[i], params_a[i]) {
          return false
        }
      }
      is_assignable(ret_a, ret_b)
    }
    // Tuple compatibility
    (@ast.TsType::Tuple(elems_a), @ast.TsType::Tuple(elems_b)) => {
      if elems_a.length() != elems_b.length() {
        return false
      }
      for i = 0; i < elems_a.length(); i = i + 1 {
        if !is_assignable(elems_a[i], elems_b[i]) {
          return false
        }
      }
      true
    }
    // Object types - structural compatibility
    (@ast.TsType::Object(props_a), @ast.TsType::Object(props_b)) =>
      // All properties in b must exist in a with compatible types
      props_b
      .iter()
      .all(fn(prop_b) {
        props_a
        .iter()
        .any(fn(prop_a) {
          match (prop_a.0, prop_b.0) {
            (@ast.TsType::Literal(name_a), @ast.TsType::Literal(name_b)) =>
              name_a == name_b && is_assignable(prop_a.1, prop_b.1)
            _ => false
          }
        })
      })
    _ => false
  }
}

///|
/// Solve all constraints and collect errors.
pub fn ConstraintSolver::solve(self : ConstraintSolver) -> Unit {
  for constraint in self.constraints {
    match constraint {
      Assignable(from, to, loc) =>
        if !is_assignable(from, to) {
          self.errors.push({
            message: "Type is not assignable",
            loc,
            expected: to,
            actual: from,
          })
        }
      MustBe(_, expected, _loc) =>
        // For now, just check against inferred type
        ignore(expected)
      Equal(a, b, loc) =>
        if a != b && !is_assignable(a, b) && !is_assignable(b, a) {
          self.errors.push({
            message: "Types are not equal",
            loc,
            expected: a,
            actual: b,
          })
        }
    }
  }
}

///|
/// Get narrowed type after a type guard.
pub fn narrow_type(base_type : @ast.TsType, guard_type : String) -> @ast.TsType {
  match guard_type {
    "string" => @ast.TsType::String_
    "number" => @ast.TsType::Number
    "boolean" => @ast.TsType::Boolean
    "function" => @ast.TsType::Any // Could be more specific
    "object" =>
      match base_type {
        @ast.TsType::Union(types) =>
          @ast.TsType::Union(
            types.filter(fn(t) {
              match t {
                @ast.TsType::Object(_) => true
                @ast.TsType::Array(_) => true
                @ast.TsType::Null => true
                _ => false
              }
            }),
          )
        _ => base_type
      }
    "undefined" => @ast.TsType::Undefined
    _ => base_type
  }
}

///|
/// Get the negated narrowed type (for else branch).
pub fn narrow_type_negated(
  base_type : @ast.TsType,
  guard_type : String,
) -> @ast.TsType {
  match base_type {
    @ast.TsType::Union(types) =>
      @ast.TsType::Union(
        types.filter(fn(t) {
          let t_kind = type_to_typeof_string(t)
          t_kind != guard_type
        }),
      )
    _ =>
      // For non-union, if the guard matches, result is never
      if type_to_typeof_string(base_type) == guard_type {
        @ast.TsType::Never
      } else {
        base_type
      }
  }
}

///|
/// Get typeof string for a type.
fn type_to_typeof_string(t : @ast.TsType) -> String {
  match t {
    @ast.TsType::String_ | @ast.TsType::Literal(_) => "string"
    @ast.TsType::Number | @ast.TsType::Int => "number"
    @ast.TsType::Boolean => "boolean"
    @ast.TsType::Undefined | @ast.TsType::Void => "undefined"
    @ast.TsType::Func(_, _) => "function"
    @ast.TsType::Null => "object"
    @ast.TsType::Object(_)
    | @ast.TsType::Array(_)
    | @ast.TsType::Tuple(_)
    | @ast.TsType::Applied(_, _) => "object"
    @ast.TsType::Symbol => "symbol"
    @ast.TsType::BigInt => "bigint"
    _ => "object"
  }
}
