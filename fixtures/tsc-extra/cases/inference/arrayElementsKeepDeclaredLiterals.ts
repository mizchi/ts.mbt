// @strict: true
// @target: esnext

// An array's element type widens a FRESH literal only: one written in place,
// an enum member, a generic call's result, or what an inline callback
// returns. A literal type that came from a declaration is kept, `const` or
// not, so `[getSep(1)]` and `xs.map((x) => getSep(x))` stay
// `('-' | '/' | null)[]` and a later `if (sep)` keeps the literals.

declare function getSep(i: number): '-' | '/' | null;
declare const o: { kind: 'a' | 'b' };
enum E { A, B }
declare function id<T>(x: T): T;
function take(s: '-' | '/'): string { return s; }
declare const xs: number[];
export function okMapped() {
    const seps = xs.map((x) => getSep(x));
    const sep = seps[0];
    if (sep) take(sep);
}
export function okLiteral() {
    const seps = [getSep(1)];
    const sep = seps[0];
    if (sep) take(sep);
}
export function okFreshWidens() {
    const a = ["-"]; a.push("z");
    const b = [E.A]; b.push(E.B);
    const c = xs.map(() => "-"); c.push("z");
    const d = [id("x")]; d.push("y");
    const e = xs.map(() => { const k = "a"; return k; }); e.push("z");
}
export function badPropertyKept() {
    const f = [o.kind]; f.push("c");
}
export function badAnnotatedCallbackKept() {
    const g = xs.map((x): "a" => "a"); g.push("z");
}
export function badSpreadKept() {
    const h = [...[getSep(1)]]; h.push("+");
}
