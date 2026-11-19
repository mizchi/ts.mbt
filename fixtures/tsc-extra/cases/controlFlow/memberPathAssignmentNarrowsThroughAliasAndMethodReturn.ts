// @strict: true
// @target: esnext

// Assigning a never-nullish value to a property path removes the nullish
// members of the field's declared type, as it does for a binding. That
// holds when the declaration is an alias (`Nullable<number>` is
// `number | null | undefined | void`, and `void` goes too), and when the
// value is a call to an unannotated method whose body returns a
// non-nullish value. A method whose body may return `undefined`, an empty
// body (`void`), an explicit `: any` return and a field never assigned all
// leave the declared type. In a generic class the path narrows to `T`.

type Nullable<T> = T | null | undefined | void;
function mapClass(c: number) { return c + 1; }
class N {
    static create(v: number) { const i = new N(v); return i; }
    static maybe(v: number) { if (v > 0) { return new N(v); } return undefined; }
    constructor(public v: number) {}
}

export class OkPath {
    private _next: Nullable<number> = null;
    private _nextChar() { const k = 1; return mapClass(k); }
    run() { this._next = this._nextChar(); return mapClass(this._next); }
}
export class OkBinding {
    private _nextChar() { const k = 1; return mapClass(k); }
    run() { let o: Nullable<number> = null; o = this._nextChar(); return mapClass(o); }
}
export class OkLiteralOnAlias {
    private _next: Nullable<number> = null;
    run() { this._next = 3; return mapClass(this._next); }
}
export class OkStaticPath {
    private _n: Nullable<N> = null;
    run() { this._n = N.create(0); return this._n.v; }
}
export class BadStaticPathMaybe {
    private _n: Nullable<N> = null;
    run() { this._n = N.maybe(0); return this._n.v; }
}
export class BadPathMaybe {
    private _next: Nullable<number> = null;
    private _maybe() { if (Math.random() > 0.5) { return 1; } return undefined; }
    run() { this._next = this._maybe(); return mapClass(this._next); }
}
export class BadAnyReturn {
    private _next: Nullable<number> = null;
    private _anyRet(): any { return 1; }
    run() { this._next = this._anyRet(); return mapClass(this._next); }
}
export class BadEmptyBody {
    private _next: Nullable<number> = null;
    private _empty() { }
    run() { this._next = this._empty(); return mapClass(this._next); }
}
export class BadUnassigned {
    private _next: Nullable<number> = null;
    run() { return mapClass(this._next); }
}
export class OkGeneric<T> {
    private _v: Nullable<T> = null;
    private _get(x: T) { return x; }
    run(x: T) { this._v = this._get(x); const y: T = this._v; return y; }
}
