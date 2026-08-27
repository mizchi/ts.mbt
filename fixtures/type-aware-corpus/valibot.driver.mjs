// Schemas, pipes, unions, picklists, optionals, and the whole issue
// surface — kind, path, message — because that surface is built from
// object literals whose keys the property mangler would love to rename.
import * as v from "./target.mjs";
const User = v.object({
  name: v.pipe(v.string(), v.minLength(2), v.maxLength(20)),
  age: v.pipe(v.number(), v.integer(), v.minValue(0)),
  email: v.pipe(v.string(), v.email()),
  tags: v.array(v.picklist(["a", "b", "c"])),
  role: v.union([v.literal("admin"), v.literal("user")]),
  nickname: v.optional(v.string(), "anon"),
});
const good = { name: "ada", age: 36, email: "a@b.co", tags: ["a", "c"], role: "admin" };
const bad = { name: "x", age: -1, email: "nope", tags: ["z"], role: "root" };
const r = v.safeParse(User, bad);
console.log(JSON.stringify({
  parsed: v.parse(User, good),
  ok: v.safeParse(User, good).success,
  badOk: r.success,
  issues: (r.issues ?? []).map((i) => ({ kind: i.kind, type: i.type, path: (i.path ?? []).map((p) => p.key) })),
  flat: r.issues ? Object.keys(v.flatten(r.issues).nested ?? {}) : null,
  thrown: (() => { try { v.parse(User, bad); return null; } catch (e) { return e.name; } })(),
}, null, 1));
