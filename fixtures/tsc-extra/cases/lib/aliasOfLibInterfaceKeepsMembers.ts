// @strict: true
// @target: esnext
// @lib: esnext,dom

// A type alias to a lib interface has that interface's members, however it
// is spelled: directly, through a top-level alias, and through an alias
// beside a namespace that declares an interface of the same name (the
// shape `@types/react` writes, `type NativeKeyboardEvent = KeyboardEvent`
// next to `namespace React { interface KeyboardEvent … }`), where the
// alias means the global one.

type NativeKE = KeyboardEvent;
declare namespace R { interface KeyboardEvent { key: string; nativeEvent: NativeKE } }
declare const d: KeyboardEvent;
declare const a: NativeKE;
declare const e: R.KeyboardEvent;

export function okDirect() { d.stopImmediatePropagation(); return d.isComposing; }
export function okAlias() { a.stopImmediatePropagation(); return a.isComposing; }
export function okThroughNamespace() { e.nativeEvent.stopImmediatePropagation(); return e.nativeEvent.isComposing; }
export function okNamespaceOwnMember() { return e.key; }
export function badAliasMissingMember() { return a.nope; }
export function badNamespaceMissingMember() { return e.nope; }
