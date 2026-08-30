// The four ways JavaScript writes one property, and the one way the
// export surface used to index.
//
// `index_prop_assigns` recorded `NAME.prop = value` and nothing else, so
// three of the four spellings never put their VALUE on the export
// surface — and `mtsc entry.ts --bundle`, with NO optimization flag,
// deleted the methods of a class that only reaches a consumer that way.
// The witness was hono: `#req ??= new HonoRequest(…)` inside `Context`'s
// getter, and a consumer's `c.req.param("id")` throwing
// `TypeError: c.req.param is not a function`.
//
// ---- How this case observes, and the two drafts that proved nothing.
//
// Each holder is EXPORTED, and its payload's method is called only from
// `driver.mjs` — outside the bundle, after it is compiled. So nothing in
// this bundle names those methods, the static access collector cannot pin
// them, and the EXPORT SURFACE is the only thing that can keep them.
//
// Draft 1 handed the payload to an `--external` module instead. It
// FAILED, correctly: an external call routes through off-bundle
// reachability, a different analysis, which attributes the escaping value
// to the HOLDER rather than to the class held inside it. It reproduced
// the bug while never exercising the export surface at all.
//
// Draft 2 used the driver, and PASSED with the fix reverted — no
// detection power whatever. The cause was the control class below.
// `prop_assigns` is keyed by receiver NAME, and `this` is therefore the
// union of every class in the bundle (`surface_escape_class` says so in
// its own comment). With every holder sharing one payload class, the
// control's plain `this.slot = new Payload(…)` — the one spelling that
// always worked — reached that class and kept its method for all six
// holders.
//
// So each holder has its OWN payload class with its OWN method name.
// A spelling that is not indexed now reaches nothing, and only that
// holder's method dies.
//
// The reference leg — Node running this same TypeScript — is what makes
// the comparison mean something: the deletion happened in every mtsc leg,
// so two mtsc outputs agreeing says nothing.

// ---- H1: a COMPOUND property assignment. -----------------------------
// `??=` / `||=` / `&&=` are a `CompoundAssignExpr` through a
// `PropAccess`, which the indexer had no arm for at all. This is how
// real code spells a lazily-created member, so it is the spelling that
// mattered most and the one that was missing.
class PayloadCoalesce {
  tag: string;
  constructor(tag: string) {
    this.tag = tag;
  }
  readCoalesce(k: string): string {
    return this.tag + ":" + k;
  }
}

class LazyCoalesce {
  slot: PayloadCoalesce | undefined;
  constructor() {
    this.slot = undefined;
  }
  get inner(): PayloadCoalesce {
    this.slot ??= new PayloadCoalesce("coalesce");
    return this.slot!;
  }
}

class PayloadOr {
  tag: string;
  constructor(tag: string) {
    this.tag = tag;
  }
  readOr(k: string): string {
    return this.tag + ":" + k;
  }
}

class LazyOr {
  slot: PayloadOr | undefined;
  constructor() {
    this.slot = undefined;
  }
  get inner(): PayloadOr {
    this.slot ||= new PayloadOr("or");
    return this.slot!;
  }
}

// ---- H2: a computed write with a literal key. ------------------------
// `NAME["prop"] = value` is `NAME.prop = value` written differently, and
// was indexed as neither.
class PayloadLiteralKey {
  tag: string;
  constructor(tag: string) {
    this.tag = tag;
  }
  readLiteralKey(k: string): string {
    return this.tag + ":" + k;
  }
}

class LiteralKeyWrite {
  slot: PayloadLiteralKey | undefined;
  constructor() {
    this.slot = undefined;
    this["slot"] = new PayloadLiteralKey("literal-key");
  }
  get inner(): PayloadLiteralKey {
    return this.slot!;
  }
}

// ---- H3: a property READ off an internal object. ---------------------
// `surface_lookup_member` resolved `bag.slot` against the object
// literal's own entry — `undefined` — escaped that, and stopped. A hit
// in the literal is a NECESSARY source of `bag.slot`, not a sufficient
// one; the recorded write is the rest of it. `return bag` was always
// fine, which is what made this look like it worked.
//
// `counter` is here as well, and not decoratively: fixing the read above
// meant walking the recorded writes, and a write can READ the key it
// writes. `counter = counter + 1` is that, and it made the walk fail to
// terminate — `case36-annotated-boundary` has the same increment and hung
// the whole corpus. The memo that stops it is keyed on `(receiver, key)`.
class PayloadReadThrough {
  tag: string;
  constructor(tag: string) {
    this.tag = tag;
  }
  readThrough(k: string): string {
    return this.tag + ":" + k;
  }
}

const bag: { slot: PayloadReadThrough | undefined; counter: number } = {
  slot: undefined,
  counter: 0,
};

// ---- H4 lives in case61. ---------------------------------------------
// The `#private` field's value escape was the fourth hole, and it cannot
// be covered here: the unindexed write spellings above leave `this.slot`
// unresolvable, which widens to `this`, and widening escapes every
// this-write — the private one included. The two holes mask each other,
// so H4 has its own fixture where nothing else reads a field off `this`.

// ---- The control. ----------------------------------------------------
// The spelling that always worked, on its own payload class so it cannot
// keep anybody else's method. A regression here would say the fix broke
// the route it was extending rather than adding one.
class PayloadPlain {
  tag: string;
  constructor(tag: string) {
    this.tag = tag;
  }
  readPlain(k: string): string {
    return this.tag + ":" + k;
  }
}

class PlainAssign {
  slot: PayloadPlain;
  constructor() {
    this.slot = new PayloadPlain("plain");
  }
  get inner(): PayloadPlain {
    return this.slot;
  }
}

export const coalesce: LazyCoalesce = new LazyCoalesce();
export const or: LazyOr = new LazyOr();
export const literalKey: LiteralKeyWrite = new LiteralKeyWrite();
export const plain: PlainAssign = new PlainAssign();

export function fillBag(): PayloadReadThrough {
  bag.counter = bag.counter + 1;
  bag.slot = new PayloadReadThrough("read-through");
  return bag.slot!;
}

export function bagCount(): number {
  return bag.counter;
}
