// @strict: true
// @target: esnext

// Narrowing by an assignment used as a condition (`while ((m = re.exec(s)))`),
// boolean truthiness to `true` / `false`, and the normalized union of an
// array of object literals with different keys.

function okExecLoop(re: RegExp, s: string) {
  let m: RegExpExecArray | null;
  while ((m = re.exec(s))) { m.index; m.input; m[0].length; }
}
function okAssignCond(x: string | null) { let z: string | null; if ((z = x)) { z.length; } }
function okAssignCmp(x: string | null) { let z: string | null; if ((z = x) !== null) { z.length; } }
function badAssignNegated(x: string | null) { let z: string | null; if (!(z = x)) { z.length; } }
function okBoolTruthy(b: boolean) { if (b) { const t: true = b; } else { const f: false = b; } }
function badNeverMember(b: boolean) { if (b) { if (!b) { b.toString(); } } }
function okNumberOrBool(x: number | boolean) { if (!x) { x.toString(); } }
function okNormalized() { let a1 = [{ a: 0 }, { a: 1, b: "x" }][0]; a1 = { a: 1 }; const b: string | undefined = a1.b; }
function badNormalizedWrongType() { let a1 = [{ a: 0 }, { a: 1, b: "x" }][0]; a1 = { a: 0, b: 0 }; }
function badNormalizedMissing() { let a1 = [{ a: 0 }, { a: 1, b: "x" }][0]; a1 = { b: "y" }; }
function okNormalizedLoop() { const cfgs = [{ name: "a", port: 1 }, { name: "b" }]; for (const c of cfgs) { c.name.toUpperCase(); } }
