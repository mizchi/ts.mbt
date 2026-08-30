// `#private` names, renamed.
//
// The property mangler skipped every `#name`, and the skip gave two
// reasons of which only the second was real: there is "nothing to hide"
// (true, and beside the point — this is about BYTES: hono's
// `#notFoundHandler` is 16 characters and `#a` is two), and renaming
// would "drop the `#`, turning a private field back into an ordinary
// visible property" (true of a bare mint, so the mint keeps the prefix).
//
// A `#private` name is the one property class that needs NO proof. It is
// class-scoped by language rule: no consumer, no reflection, no
// serialization and no computed access can name it. That is also why the
// candidate check runs BEFORE the reserved set — the reserved set
// answers "can something outside see this name", and for a `#` name the
// answer is no whatever the escape analysis concluded. Six of the ten
// measured targets reserve the wildcard, so leaving privates behind that
// check would keep them un-mangled exactly where the pass is otherwise
// inert.
//
// What this case has to establish:
//
//   1. The rename is applied to the declaration AND every reference.
//   2. TWO classes declaring the same private name stay independent —
//      they are different members, so both may become `#a`.
//   3. A private is still INVISIBLE: `Object.keys`, `JSON.stringify`,
//      object spread and `for…in` must see nothing, before and after.
//   4. A public property of the same spelling is a different member and
//      must not be confused with the private one.
//
// The classes are deliberately NOT exported: `report` carries the
// RESULTS, so the whole class may legitimately be inlined or deleted and
// the observation is still what decides.
//
// This is a SAFETY case, not an optimization pin. Mutating the rename
// back off leaves it passing, and correctly so — declining to rename a
// private breaks nothing. What it does detect is the hazard the old skip
// named: with the `#` dropped from the mint it fails, because the
// private becomes an ordinary visible property and `Object.keys`,
// `JSON.stringify`, the spread and the `for…in` all start seeing it.
// The byte saving is pinned by the number in `docs/mangle-safety.md`
// (hono -1,876) and by the census line in `--explain-mangle`.
//
// NOT covered: `#x in obj`, the ergonomic brand check. mtsc's checker
// rejects it — `cannot find name __private_brand__0__path` — because the
// `in` operand is lowered to the brand name and the checker has no entry
// for it. That is a checker gap, separate from this rename, and it is
// filed on its own; putting it here would only make this case
// blocked-compile.

class Router {
  #notFoundHandler: (() => string) | null = null;
  #routes: string[] = [];
  #path = "/";
  // A PUBLIC `path` alongside the private `#path`: different members.
  path = "public";

  setNotFound(h: () => string): void {
    this.#notFoundHandler = h;
  }
  add(r: string): void {
    this.#routes.push(r);
    this.#path = r;
  }
  describe(): string {
    return (
      this.#path +
      ":" +
      String(this.#routes.length) +
      ":" +
      (this.#notFoundHandler ? this.#notFoundHandler() : "none")
    );
  }
}

// The same private name in a different class. Independent members.
class Other {
  #path = "!";
  get p(): string {
    return this.#path;
  }
}

const r = new Router();
r.add("/a");
r.setNotFound(() => "nf");
const o = new Other();

const spread = { ...r };
const forIn: string[] = [];
for (const k in r) {
  forIn.push(k);
}

export const report = {
  describe: r.describe(),
  otherPath: o.p,
  publicPath: r.path,
  // A private must not appear in any of these, in any leg.
  keys: Object.keys(r).join(","),
  json: JSON.stringify(r),
  spreadKeys: Object.keys(spread).join(","),
  forIn: forIn.join(","),
};
