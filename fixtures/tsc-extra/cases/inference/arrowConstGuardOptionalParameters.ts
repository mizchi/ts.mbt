// @strict: true
// @target: esnext

// A type guard written as a generic arrow `const` keeps its optional and
// defaulted parameters omittable, accepts `null` where its parameter does,
// and still narrows. Too many arguments is TS2554.

interface El { locked: boolean; type: string }
interface Arrow extends El { kind: "arrow" }
const isBindingElement = <T extends El>(
  element?: T | null,
  includeLocked = true,
): element is T & Arrow => element != null && (!element.locked || includeLocked === true);

function okOneArgument(e: El) { if (isBindingElement(e)) { const k: "arrow" = e.kind; } }
function okNullableArgument(e: El | null) { const b: boolean = isBindingElement(e); }
function okNoArguments() { const b: boolean = isBindingElement(); }
function badTooManyArguments(e: El) { isBindingElement(e, false, 3); }
function badNarrowedMemberType(e: El) { if (isBindingElement(e)) { const k: number = e.kind; } }
