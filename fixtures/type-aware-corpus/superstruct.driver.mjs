// Structs, refinements, and the failure surface — `path`, `branch` and
// `refinement` are read by name off the error objects.
import { object, string, number, array, optional, union, literal, assert, is, validate, refine, min, size, StructError } from "./target.mjs";
const User = object({
  name: size(string(), 2, 20),
  age: min(number(), 0),
  tags: array(union([literal("a"), literal("b")])),
  nick: optional(string()),
});
const good = { name: "ada", age: 36, tags: ["a"] };
const bad = { name: "x", age: -1, tags: ["z"] };
const out = [];
out.push(is(good, User), is(bad, User));
const [errG, valG] = validate(good, User);
out.push([errG === undefined, valG]);
const [errB] = validate(bad, User, { coerce: false });
out.push(errB ? errB.failures().map((f) => ({ path: f.path, type: f.type, refinement: f.refinement ?? null })) : null);
try { assert(bad, User); } catch (e) { out.push([e instanceof StructError, e.name, e.path]); }
const Even = refine(number(), "Even", (v) => v % 2 === 0);
out.push(is(4, Even), is(5, Even));
console.log(JSON.stringify(out, null, 1));
