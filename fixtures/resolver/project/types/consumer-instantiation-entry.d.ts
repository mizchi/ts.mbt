// Consumer-style fixture: a concrete `Schema` interface drives all the
// downstream type-level computations. Mirrors what a real project does
// after picking a concrete `Env`/`Shape`/`Schema`. Demonstrates that
// `keyof T` and `${prefix}${keyof T}` partial-evaluate end-to-end when
// the operand is concrete in the user's own module.

export interface Schema {
  id: number;
  name: string;
  age: number;
}

// `keyof Schema` over a concrete struct expands to a literal-key union.
export type SchemaKeys = keyof Schema;

// Template literal over the alias-indirected `keyof` source — chains
// `${prefix}${keyof Schema}` through the simplifier.
export type SchemaPrefixed = `prefix_${SchemaKeys}`;

// Mapped type whose source is `keyof Schema`. After mapped-type partial
// evaluation the body collapses to a concrete object with literal keys;
// the bridge surfaces that as a synthetic interface, so consumers see
// a real `pub(all) struct SchemaFlags { id : Bool, ... }`.
export type SchemaFlags = { [K in keyof Schema]: boolean };

export declare function getKey(): SchemaKeys;
export declare function tag(value: SchemaPrefixed): void;
export declare function flag(): SchemaFlags;
