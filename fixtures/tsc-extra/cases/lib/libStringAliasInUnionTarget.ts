// @strict: true
// @target: esnext

// A DOM string-union alias (`CanvasFontKerning = "auto" | "none" |
// "normal"`) accepts its members whether the parameter is the bare alias,
// optional, or the alias in a union with `undefined` or `null`. A string
// outside the alias is an error in every spelling.

declare function bare(k: CanvasFontKerning): void;
declare function optional(k?: CanvasFontKerning): void;
declare function withUndefined(k: CanvasFontKerning | undefined): void;
declare function withNull(k: CanvasTextAlign | null): void;
export function okBare() { bare('normal'); }
export function okOptional() { optional('none'); }
export function okWithUndefined() { withUndefined('auto'); }
export function okWithNull() { withNull('left'); }
export function badBare() { bare('bogus'); }
export function badWithUndefined() { withUndefined('bogus'); }
