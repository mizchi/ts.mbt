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

export declare function getKey(): SchemaKeys;
export declare function tag(value: SchemaPrefixed): void;
