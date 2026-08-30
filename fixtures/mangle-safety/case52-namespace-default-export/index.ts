// A default-exported namespace object, where the namespace's local name
// collides with another module's top-level declaration.
//
// The linker mints a collision-free name for the synthesized
// `const Type = { … }` and records it in `namespace_local_renames`,
// which is a DIFFERENT table from `rename_per_module`.
// `resolve_export`'s fallback read only the latter — which has no entry
// for a namespace local — so it handed back the SOURCE spelling, and
// the consumer's `Type.Number()` was left bound to `helpers.ts`'s
// unrelated arrow. `Type.Number is not a function`, under plain
// `mtsc --bundle` with no optimization flag: this case declares no
// `mtscArgs` for that reason.
//
// It is a wrong BINDING rather than a missing one, so `--verify` cannot
// see it: every name in the emitted bundle resolves. It just resolves
// to the wrong thing.
//
// A library's own package entry cannot reach this — nothing imports a
// barrel's own default export — which is why it took measuring an
// application entry to surface it.

import Type, { Shapes, Type as Helper, helperLabel } from "./barrel";

// Through the DEFAULT import: the spelling that was broken.
export const viaDefault = Type.Number(7) + "|" + Type.Object("k") + "|" +
  Type.label;

// Through the NAMED re-export of the same namespace object: a separate
// resolution path with the same missing lookup.
export const viaNamed = Shapes.Number(8) + "|" + Shapes.Object("j");

// And the colliding declaration is still reachable under its own name,
// which is what makes this a rename rather than a shadowing. If the
// linker had resolved the collision the other way, this would be the
// observation that broke.
export const viaCollision = Helper("x") + "|" + helperLabel;
