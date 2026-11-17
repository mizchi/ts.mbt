// @strict: true
// @target: esnext

// An object literal spreading `any` (or a value this checker cannot see
// into) is `any`, so it is not missing any member of its target. A literal
// spreading a known shape still has to supply what that shape lacks.

interface R { s: number; e: number; id: string; kind: number; extra?: boolean }
interface P { s: number }

function okSpreadAny(a: any) { const x: R = { ...a, s: 0 }; }
function okSpreadAsAny(t: unknown) { const y: R = { ...(t as any), e: 1 }; }
function okSpreadKnownShapeComplete(p: P) { const z: R = { ...p, e: 1, id: "", kind: 0 }; }
function badMissingWithoutSpread() { const x: R = { s: 0, e: 1 }; }
function badSpreadKnownShapeIncomplete(p: P) { const y: R = { ...p, e: 1, id: "" }; }
