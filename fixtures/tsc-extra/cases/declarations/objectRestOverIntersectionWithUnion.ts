// @strict: true
// @target: esnext

// An object rest over an intersection holding one union part distributes
// over that union, as a rest over a bare union does: `{ tab, ...rest }` of
// `{ tab: string } & (A | B)` is `A | B` without `tab`, which an `in` test
// then narrows (excalidraw's `TTDDialog`). A member none of the parts has is
// still an error.

type A = { onSubmit(x: number): void; label?: string };
type B = { __fallback: true };

export function okRestOfIntersectionUnion({ tab, ...rest }: { tab: string } & (A | B)) {
  if (!("__fallback" in rest)) { rest.onSubmit(1); return rest.label; }
  return tab;
}
export function okRestOfIntersection({ tab, ...rest }: { tab: string } & A) { rest.onSubmit(1); return tab; }
export function badRestMissing({ tab, ...rest }: { tab: string } & A) { rest.nope; return tab; }
export function badRestKeepsUnion({ tab, ...rest }: { tab: string } & (A | B)) { rest.onSubmit(1); return tab; }
