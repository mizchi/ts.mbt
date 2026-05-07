// Concrete-source partial-evaluation cases for the bridge.
// These exercise checker-level keyof / mapped / template-literal
// evaluation; the bridge widens unresolvable shapes back to String /
// Object so consumers never see a dangling `Keyof(...)` / `MappedType(...)`
// at the surface.

export interface Foo {
  a: number;
  b: string;
  c: boolean;
}

// Exercises template-literal cartesian expansion at the alias surface
// without going through an alias indirection. Should land as a 4-member
// string enum (`info-small`, `info-large`, `warn-small`, `warn-large`).
export type DirectBanner = `${"info" | "warn"}-${"small" | "large"}`;

// `keyof Foo` at a parameter position widens to `String` (literal-union
// emission at parameter positions is intentionally conservative).
export declare function pickFooKey(key: keyof Foo): void;

// Direct mapped over a literal union (no binder reference). Eagerly
// materialized by the parser to a concrete object of fixed keys.
export type FooFlags = { [K in "a" | "b" | "c"]: boolean };

// Capitalize intrinsic in a template literal — partial-evaluates to a
// single literal at the alias position.
export type Greeting = `Hello, ${Capitalize<"world">}!`;
