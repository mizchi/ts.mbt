// @strict: true
// @target: esnext

// An object type with a computed key has an index signature for that key,
// so an object built with `{ [k]: v }` and held in a variable is assignable
// to an interface that declares nothing but string index signatures when
// every value fits the signature's value, the same as when the literal is
// passed inline. A union value type accepts a value that fits one member.

type LanguageValue = string | string[] | ILanguagePack | ILanguagePack[] | boolean;
interface ILanguagePack { [key: string]: LanguageValue }
interface ILocales { [key: string]: ILanguagePack }
interface Lang { [key: string]: { greeting: string } }
declare function load(l: Lang): void;
declare function loadAll(l: ILocales): void;
enum LocaleType { ZH = "zh", EN = "en" }

export function okComputedVar() { const K = "zh"; const locales = { [K]: { greeting: "a" } }; load(locales); }
export function okComputedInline() { const K = "zh"; load({ [K]: { greeting: "a" } }); }
export function okComputedDeclared(k: string) { const locales = { [k]: { greeting: "a" } }; load(locales); }
export function okNestedPack() { const locales = { [LocaleType.ZH]: { greeting: "a", nested: { welcome: "b" }, list: ["x"], on: true } }; loadAll(locales); }
export function badComputedVar() { const K = "zh"; const locales = { [K]: { greeting: 1 } }; load(locales); }
export function badNumberInPack() { const locales = { [LocaleType.ZH]: { greeting: 1 } }; loadAll(locales); }
export function badComputedInline(k: string) { load({ [k]: { greeting: 1 } }); }
export function okNumericKeyToStringSignature(n: number) { load({ [n]: { greeting: "a" } }); }
export function badNumericKeyToStringSignature(n: number) { load({ [n]: { greeting: 1 } }); }

// A symbol key lies outside every string and number index signature, so its
// value is not judged against one.
const sym = Symbol("s");
interface Strs { [k: string]: string }
declare function take(s: Strs): void;
export function okSymbolKeyInline() { take({ [sym]: 1 }); }
export function okSymbolKeyBound() { const o = { [sym]: 1 }; take(o); }
declare const usa: unique symbol;
declare const usb: unique symbol;
declare const unionKey: typeof usa | typeof usb;
declare const mixedKey: typeof usa | string;
export function okUnionSymbolKey() { take({ [unionKey]: 1 }); }
export function badMixedSymbolKey() { take({ [mixedKey]: 1 }); }
