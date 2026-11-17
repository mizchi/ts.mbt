// @strict: true
// @target: esnext

// A type guard narrows its subject whatever spelling reaches it: a static
// method called through its class, and a subject that is a property path
// or an optional chain rather than a bare binding. A chain whose guarded
// value cannot be nullish did not short-circuit, so the receivers its `?.`
// guarded are non-nullish too, which an `unknown` or `any` result does not
// prove. The negative branch of a chain says nothing,
// since the guard may have failed because a receiver was nullish.

class Tools {
  static isDefine<T>(value?: T | void): value is T { return value !== undefined && value !== null }
  static isNum(value: unknown): value is number { return typeof value === "number" }
}
declare function isDefine<T>(value?: T | void): value is T;
interface P { top?: number; other?: number }
declare function accepts(x: unknown): x is unknown;
declare const loose: { p?: any; q: number } | undefined;

function okStaticOnVariable(x: number | undefined) { let t = 0; if (Tools.isDefine(x)) { t = x; } }
function okStaticConcrete(x: unknown) { let t = 0; if (Tools.isNum(x)) { t = x; } }
function okFunctionOnPath(props: P) { let t = 0; if (isDefine(props.top)) { t = props.top; } }
function okStaticOnPath(props: P) { let t = 0; if (Tools.isDefine(props.top)) { t = props.top; } }
function okStaticOnChain(props?: P) { let t = 0; if (Tools.isDefine(props?.top)) { t = props.top; } }
function okFunctionOnChain(props?: P) { let t = 0; if (isDefine(props?.top)) { t = props.top; } }
function badElseOfPath(props: P) { let t = 0; if (isDefine(props.top)) { } else { t = props.top; } }
function badElseOfChain(props?: P) { let t = 0; if (Tools.isDefine(props?.top)) { } else { t = props.top; } }
function badSiblingMember(props?: P) { let t = 0; if (Tools.isDefine(props?.top)) { t = props.other; } }
function badUnguarded(props: P) { let t = 0; t = props.top; }
function badUnknownTargetProvesNothing() { if (accepts(loose?.p)) { const n = loose.q; } }
