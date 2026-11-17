// @strict: true
// @target: esnext

// An optional parameter's type is `T | undefined`, and a value that cannot be
// nullish meets that target exactly when it meets `T`: an object literal is
// checked against `T` itself, mismatched members included, and a non-literal
// source is related to `T` the same way it would be against a required
// parameter.

interface Box { value: number }
declare function takeOptional(p?: Box): void;
declare function takeUnion(p: Box | undefined): void;
declare function takeNullable(p: Box | null): void;
export function okLiteralToOptional() { takeOptional({ value: 1 }); }
export function okUndefinedToOptional() { takeOptional(undefined); }
export function badLiteralToOptional() { takeOptional({ value: "bad" }); }
export function badLiteralToUnion() { takeUnion({ value: "bad" }); }
export function badLiteralToNullable() { takeNullable({ value: "bad" }); }

interface Locale { code: string; localize: { month: (n: number) => string } }
interface Options { locale?: Pick<Locale, "localize"> }
declare function format(d: Date, f: string, o?: Options): string;
export function okOptionsViaConst(d: Date, locale: Locale) { const opts = { locale }; return format(d, "x", opts); }
export function badOptionsViaConst(d: Date) { const opts = { locale: 1 }; return format(d, "x", opts); }

declare function insert(index: number, text: string, attributes?: Object): void;
export function okNumberToOptionalObject() { insert(0, "a", 0); }
export function okStringToOptionalObject() { insert(0, "a", "s"); }

// Every array callback method takes the lib's optional `thisArg` after the
// callback.
declare const xs: string[];
const ctx = { n: 1 };
export const okFilterThisArg = xs.filter((x) => x.length > 0, ctx);
export const okMapThisArg = xs.map((x) => x.length, ctx);
export const okSomeThisArg = xs.some((x) => x === "a", ctx);
export const okEveryThisArg = xs.every((x) => x !== "", ctx);
export const okFindThisArg = xs.find((x) => x === "a", ctx);
export const okFindIndexThisArg = xs.findIndex((x) => x === "a", ctx);
export function okForEachThisArg() { xs.forEach((x) => x, ctx); }
export const okFlatMapThisArg = xs.flatMap((x) => [x], ctx);
export function badFilterTooMany() { return xs.filter((x) => x.length > 0, ctx, 1); }
