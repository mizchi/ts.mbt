// Standard TypeScript utility-type definitions encoded as `AliasBinding`s the
// resolver-aware checker can consume directly. Built on the distributive
// conditional + infer pattern matcher.
//
// Excluded for now (require AST features we do not model):
//   Partial / Required / Readonly  — mapped types
//   Pick / Omit                    — keyof + mapped
//   ConstructorParameters / InstanceType — class signature distinction
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
    body: Conditional(Named("T"), Union([Null, Undefined]), Never, Named("T")),
  }

  // type ReturnType<F> = F extends (...args: any[]) => infer R ? R : any
  table["ReturnType"] = {
    type_params: ["F"],
    body: Conditional(
      Named("F"),
      Func([Array(Any)], Applied("__tsmbt_infer", [Named("R")])),
      Named("R"),
      Any,
    ),
  }

  // type Parameters<F> = F extends (...args: infer P) => any ? P : never
  table["Parameters"] = {
    type_params: ["F"],
    body: Conditional(
      Named("F"),
      Func([Array(Applied("__tsmbt_infer", [Named("P")]))], Any),
      Named("P"),
      Never,
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

  // type ThisType<T> = T — TS uses it as an inference-context marker on
  // an object literal's contextual type so methods see `T` as `this`.
  // Without a contextual-inference engine the alias is the identity at
  // the type level, which matches what every other consumer sees too.
  table["ThisType"] = { type_params: ["T"], body: Named("T") }

  // type NoInfer<T> = T — added in TS 5.4 as an inference-blocking marker.
  // We don't model contextual inference, so structurally `NoInfer<T>` is
  // the identity. Recording it as an alias keeps `is_assignable_to`
  // transparent and lets bridge passes unwrap it directly.
  table["NoInfer"] = { type_params: ["T"], body: Named("T") }

  // type ThisParameterType<F> = F extends (this: infer U, ...args: any[]) => any
  //   ? U : unknown
  // MoonBit doesn't model `this` parameters explicitly; we recognize the
  // shape so the alias still resolves, but real-world `this` capture
  // requires a follow-up at the parser level.
  table["ThisParameterType"] = {
    type_params: ["F"],
    body: Conditional(Named("F"), Func([Array(Any)], Any), Any, Any),
  }

  // type OmitThisParameter<F> = F extends (this: any, ...args: infer A) => infer R
  //   ? (...args: A) => R : F
  // Without an explicit `this`-parameter model the structural pattern
  // collapses to the function shape unchanged, which is what callers
  // observe at runtime anyway.
  table["OmitThisParameter"] = {
    type_params: ["F"],
    body: Conditional(
      Named("F"),
      Func(
        [Array(Applied("__tsmbt_infer", [Named("A")]))],
        Applied("__tsmbt_infer", [Named("R")]),
      ),
      Func([Array(Applied("__tsmbt_infer", [Named("A")]))], Named("R")),
      Named("F"),
    ),
  }

  // type ConstructorParameters<C> = C extends new (...args: infer P) => any
  //   ? P : never
  table["ConstructorParameters"] = {
    type_params: ["C"],
    body: Conditional(
      Named("C"),
      Constructor([Array(Applied("__tsmbt_infer", [Named("P")]))], Any, false),
      Named("P"),
      Never,
    ),
  }

  // type InstanceType<C> = C extends new (...args: any[]) => infer R ? R : any
  table["InstanceType"] = {
    type_params: ["C"],
    body: Conditional(
      Named("C"),
      Constructor([Array(Any)], Applied("__tsmbt_infer", [Named("R")]), false),
      Named("R"),
      Any,
    ),
  }
  table
}
