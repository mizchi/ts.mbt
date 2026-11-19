// @strict: true
// @target: esnext

// A binding widens an enum member to its enum only where the member was
// written: an object literal, a call taking an inline callback, and an
// unannotated function's inferred return all widen, so a later write of
// another member is legal. A parameter typed with a member and held in
// `{ t }`, and a declared function returning `{ tag: S.X }`, keep the
// declared member type.

enum S { X = "x", Y = "y" }
declare const xs: number[];

const mapped = xs.map(() => ({ tag: S.X, n: 1 }));
export function okPushAnotherMember() { mapped.push({ tag: S.Y, n: 2 }); }
export function okWriteAnotherMember() { mapped[0].tag = S.Y; }
export function okInferredReturn() { return { tag: S.X }; }
export function okWriteThroughInferredReturn() { const r = okInferredReturn(); r.tag = S.Y; }
const nested = { inner: xs.map(() => ({ tag: S.X })) };
export function okPushIntoNestedArray() { nested.inner.push({ tag: S.Y }); }
export function okParameterKeepsMember(t: S.X) { const x = { t }; const y: { t: S.X } = x; return y; }
declare function declaredArray(): { tag: S.X }[];
const fromDeclaredArray = declaredArray();
export const okDeclaredArrayKeepsMember: { tag: S.X }[] = fromDeclaredArray;
declare function declaredObject(): { tag: S.X };
const fromDeclaredObject = declaredObject();
export const okDeclaredObjectKeepsMember: { tag: S.X } = fromDeclaredObject;
const widened = xs.map(() => ({ tag: S.X }));
export const badWidenedToEnum: { tag: S.X }[] = widened;
const literal = { tag: S.X };
export const badLiteralWidenedToEnum: { tag: S.X } = literal;
const returned = okInferredReturn();
export const badInferredReturnWidened: { tag: S.X } = returned;
export const badInferredReturnCall: { tag: S.X } = okInferredReturn();
declare function load(cb: () => void): { tag: S.X }[];
const loaded = load(() => {});
export const okDeclaredResultWithCallbackKept: { tag: S.X }[] = loaded;
declare const raw: { tag: "raw" };
const spreadLast = [{ tag: S.X, ...raw }];
export const okLaterSpreadWins: { tag: "raw" }[] = spreadLast;
const enumLast = [{ ...raw, tag: S.X }];
export const badLaterEnumWidened: { tag: S.X }[] = enumLast;
declare function load2(cb: () => { tag: S }): { tag: S.X }[];
const loadedBesideAWrite = load2(() => ({ tag: S.Y }));
export const okDeclaredKeptBesideACallbackWrite: { tag: S.X }[] = loadedBesideAWrite;
