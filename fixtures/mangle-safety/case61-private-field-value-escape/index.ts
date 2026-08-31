// A `#private` field's VALUE has to escape, even though its NAME must
// not be reserved.
//
// `surface_escape_class` had the value escape INSIDE the
// `is_internal_marker_prop` filter:
//
//     if (!is_internal_marker_prop(entry.0)) {
//       w.reserved[entry.0] = true
//       surface_escape_expr(w, entry.1, depth + 1)   // <- wrong side
//     }
//
// The filter answers "may this NAME be reserved" — no, because no
// consumer can spell `__private_brand__0__slot`. It says nothing about
// the value, which is an ordinary object that leaves with the instance.
// So `mtsc entry.ts --bundle`, with no optimization flag, deleted
// `Payload`'s method, and the identical class with a PUBLIC field was
// fine. The top-level `prop_assigns` loop sixty lines above the bug had
// the escape on the correct side, which is what makes this the ninth
// instance of one rule written in two places and applied in one.
//
// ---- Why this is its own case and not part of case60.
//
// case60 covers the three unindexed WRITE spellings, and inside that
// bundle this hole is MASKED. Those spellings leave `this.slot` reads
// unresolvable, which widens to `this` — and widening enqueues `this`,
// whose `prop_assigns` loop escapes every this-write including the
// private one. The two holes interact, so a fixture that reverts both
// cannot attribute either. Here nothing else reads a field off `this`,
// so the only route to `Payload` is the private field's own write.
//
// The payload is handed out through a callback the CONSUMER supplies,
// deliberately: a getter that returns the field widens to `this` and
// would mask this hole exactly the way case60 does.

class Payload {
  tag: string;

  constructor(tag: string) {
    this.tag = tag;
  }

  // Called only from `driver.mjs`, outside the bundle. Nothing in here
  // names it, so only the export surface can keep it.
  readPrivate(k: string): string {
    return this.tag + ":" + k;
  }
}

export class PrivateHolder {
  #slot: Payload | undefined;

  constructor() {
    this.#slot = undefined;
  }

  load(): void {
    this.#slot = new Payload("private");
  }

  use(f: (p: Payload) => string): string {
    return f(this.#slot!);
  }
}

const holder = new PrivateHolder();
holder.load();

export const priv: PrivateHolder = holder;
