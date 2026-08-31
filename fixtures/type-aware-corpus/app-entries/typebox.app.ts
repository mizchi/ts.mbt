// typebox, used the way its readme's first example uses it, plus the
// `Script` / validation surface so the schema is consumed and not only
// built.
//
// Every export is a scalar.

import Type from "./src/index.ts";

const T = Type.Object({
  x: Type.Number(),
  y: Type.Number(),
  z: Type.Number(),
});

type T = Type.Static<typeof T>;

const point: T = { x: 1, y: 2, z: 3 };

const Nested = Type.Object({
  id: Type.String(),
  point: T,
  tags: Type.Array(Type.String()),
  kind: Type.Union([Type.Literal("a"), Type.Literal("b")]),
});

export const schema: string = JSON.stringify(T);
export const nestedKeys: string = Object.keys(
  (Nested as { properties?: Record<string, unknown> }).properties ?? {},
).join(",");
export const kind: string = String((T as { type?: string }).type);
export const required: string =
  ((T as { required?: string[] }).required ?? []).join("");
export const sum: number = point.x + point.y + point.z;
