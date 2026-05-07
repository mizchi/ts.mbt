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

export declare function getId(): IdOnly;
export declare function getIdName(): IdAndName;
export declare function getWithoutAge(): WithoutAge;
export declare function getPartial(): SchemaPartial;
export declare function getReadonly(): SchemaReadonly;
