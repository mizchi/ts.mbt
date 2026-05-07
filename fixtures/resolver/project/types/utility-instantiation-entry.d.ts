// Consumer-style fixture: standard TypeScript utility types applied to
// a concrete in-module interface. Each alias should land as a
// `pub(all) struct` with the projected / wrapped fields rather than
// `declare pub type X`.

export interface Schema {
  id: number;
  name: string;
  age: number;
}

export type IdOnly = Pick<Schema, "id">;
export type IdAndName = Pick<Schema, "id" | "name">;
export type WithoutAge = Omit<Schema, "age">;
export type SchemaPartial = Partial<Schema>;
export type SchemaReadonly = Readonly<Schema>;

// Chained utility instantiation: `SchemaPartial` is itself an alias of
// `Partial<Schema>`. The bridge walks the alias chain to discover the
// underlying interface so `Required<SchemaPartial>` recovers the
// original required fields end-to-end.
export type SchemaRequired = Required<SchemaPartial>;

// `Pick` over an already-projected alias. `IdAndName = Pick<Schema, "id"
// | "name">`; picking `"id"` again should leave a struct with just `id`.
export type IdRePick = Pick<IdAndName, "id">;

export declare function getId(): IdOnly;
export declare function getIdName(): IdAndName;
export declare function getWithoutAge(): WithoutAge;
export declare function getPartial(): SchemaPartial;
export declare function getReadonly(): SchemaReadonly;
export declare function getRequired(): SchemaRequired;
export declare function getRePick(): IdRePick;
