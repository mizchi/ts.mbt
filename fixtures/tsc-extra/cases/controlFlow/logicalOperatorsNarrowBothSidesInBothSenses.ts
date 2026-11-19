// @strict: true
// @target: esnext

// `&&` and `||` narrow in both senses. Under a `!`, `!(x === null || y ===
// null)` narrows both operands to non-null where it is true. The else side
// of `!a?.x && !a?.y` is `a?.x || a?.y`, where `a` is defined on either path.
// And `x === false` on a union holding `boolean` leaves `true`.

type Lock = { scroll?: boolean; zoom?: boolean; overscroll?: number };

export function okNegatedOrNarrowsBoth(x: string | null, y: string | null) { if (!(x === null || y === null)) { return x.length + y.length; } return 0; }
export function badNegatedOrElseSide(x: string | null, y: string | null) { if (!(x === null || y === null)) { return 0; } return x.length; }
export function okAndOfNegatedChainsEarlyReturn(lock?: Lock) { if (!lock?.scroll && !lock?.zoom) return 0; return lock.overscroll; }
export function badOrOfNegatedChainsEarlyReturn(lock?: Lock) { if (!lock?.scroll || !lock?.zoom) return lock.overscroll; return 0; }
export function okFalseThenTrueLeavesNumber(o: boolean | number | undefined): number { if (o === false) return 0; if (o === true || o == null) return 1; return Math.max(o, 0); }
export function badFalseLeavesTrue(o: boolean | number): number { if (o === false) return 0; return o; }
