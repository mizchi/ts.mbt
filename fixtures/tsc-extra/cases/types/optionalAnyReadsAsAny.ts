// @strict: true
// @target: esnext

// An optional `any` is `any`: `undefined` adds nothing to it, so a member
// read is not "possibly undefined" and finds every name. An optional
// `number` or `unknown` keeps its `undefined`, so the same read is an error.

interface S { zoom?: any; n?: number }
declare const s: S;

function okOptionalAnyProperty() { const v = s.zoom.value; }
function okOptionalAnyParameter(p?: any) { return p.value; }
function okOptionalAnyMethodCall(p?: any) { return p.run(1); }
function badOptionalNumberProperty() { const v = s.n.toFixed(); }
function badOptionalUnknownParameter(p?: unknown) { return p.value; }
