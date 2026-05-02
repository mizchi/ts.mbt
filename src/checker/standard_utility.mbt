// Standard TypeScript utility-type definitions encoded as `AliasBinding`s the
// resolver-aware checker can consume directly. Built on the distributive
// conditional + infer pattern matcher.
//
// Excluded for now (require AST features we do not model):
//   Partial / Required / Readonly  — mapped types
//   Pick / Omit                    — keyof + mapped
//   ReturnType / Parameters        — rest-parameter signature pattern matching
//   ConstructorParameters / InstanceType — same rest-param issue
//
// Use:
//   let resolve = fn(name) { standard_utility_types().get(name) }
//   is_assignable_to_with_generics(s, t, resolve)

///|
pub fn standard_utility_types() -> Map[String, AliasBinding] {
  let table : Map[String, AliasBinding] = {}

  // type Exclude<T, U> = T extends U ? never : T
  table["Exclude"] = {
    type_params: ["T", "U"],
    body: Conditional(Named("T"), Named("U"), Never, Named("T")),
  }

  // type Extract<T, U> = T extends U ? T : never
  table["Extract"] = {
    type_params: ["T", "U"],
    body: Conditional(Named("T"), Named("U"), Named("T"), Never),
  }

  // type NonNullable<T> = T extends null | undefined ? never : T
  table["NonNullable"] = {
    type_params: ["T"],
    body: Conditional(
      Named("T"),
      Union([Null, Undefined]),
      Never,
      Named("T"),
    ),
  }

  // type Awaited<T> = T extends Promise<infer U> ? Awaited<U> : T
  // We unwrap a single Promise level here; the recursive Awaited<U> form is
  // simulated by leaving the inner alias unsubstituted (cycle detection in
  // expand_generic collapses deeper nesting to Any, so the outer level still
  // unwraps correctly for the most common case of Promise<X> → X).
  table["Awaited"] = {
    type_params: ["T"],
    body: Conditional(
      Named("T"),
      Applied("Promise", [Applied("__tsmbt_infer", [Named("U")])]),
      Named("U"),
      Named("T"),
    ),
  }
  table
}
