// Schemas, refinements, and the issue surface. zod's error objects are
// read by key (`code`, `path`, `message`, `expected`), which is exactly
// what a property mangler must not touch.
import { z } from "./target.mjs";
const User = z.object({
  name: z.string().min(2).max(20),
  age: z.number().int().nonnegative(),
  email: z.string().email(),
  tags: z.array(z.enum(["a", "b", "c"])),
  role: z.union([z.literal("admin"), z.literal("user")]),
  nick: z.string().optional().default("anon"),
});
const good = { name: "ada", age: 36, email: "a@b.co", tags: ["a", "c"], role: "admin" };
const bad = { name: "x", age: -1, email: "nope", tags: ["z"], role: "root" };
const out = [];
out.push(User.parse(good));
out.push(User.safeParse(good).success, User.safeParse(bad).success);
const r = User.safeParse(bad);
out.push(r.success ? null : r.error.issues.map((i) => ({ code: i.code, path: i.path })));
const Tagged = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("a"), n: z.number() }),
  z.object({ kind: z.literal("b"), s: z.string() }),
]);
out.push(Tagged.parse({ kind: "a", n: 1 }), Tagged.safeParse({ kind: "c" }).success);
out.push(z.string().transform((s) => s.length).parse("abcd"));
out.push(z.number().refine((n) => n % 2 === 0, "even").safeParse(3).success);
try { User.parse(bad); } catch (e) { out.push("threw:" + e.constructor.name); }
console.log(JSON.stringify(out, null, 1));
