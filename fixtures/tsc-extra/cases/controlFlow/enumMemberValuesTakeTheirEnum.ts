// @strict: true
// @target: esnext

// A mutable place initialized or assigned with an enum member holds the
// ENUM, not the member's value: an unannotated class field, a `let`, and a
// binding declared `Nullable<E>` that each branch assigns a member to. A
// member read through `reduce` keeps its enum as well.

type Nullable<T> = T | null | undefined | void;
export enum DS { D1900 = "1900", D1904 = "1904" }
export enum N { A, B }
export enum Direction { UP, DOWN }
declare function take(d: Direction): void;

export class OkFields {
    private _d = DS.D1900;
    private _n = N.A;
    take(d?: DS) { return d; }
    takeN(n: N) { return n; }
    useBoth() { this.take(this._d); this.takeN(this._n); this._d = DS.D1904; this._n = N.B; }
}
export function okLetReassigned(it?: number) { let s = DS.D1900; if (it === 0) { s = DS.D1904; } return s; }
export function okAssignedOnce() { let d: Nullable<Direction> = null; d = Direction.UP; take(d); }
export function okAssignedInBranches(a: number) { let d: Nullable<Direction> = null; if (a < 0) { d = Direction.UP; } else { d = Direction.DOWN; } take(d); }
export interface IRange { startRow: number; endRow: number; rangeType?: N }
export function okReduceKeepsTheEnum(...ranges: IRange[]): IRange {
    return ranges.reduce((acc, current) => ({ startRow: Math.min(acc.startRow, current.startRow), endRow: Math.max(acc.endRow, current.endRow), rangeType: N.A }), ranges[0]);
}
export function badMaybeAssigned(a: number) { let d: Nullable<Direction> = null; if (a < 0) { d = Direction.UP; } take(d); }
