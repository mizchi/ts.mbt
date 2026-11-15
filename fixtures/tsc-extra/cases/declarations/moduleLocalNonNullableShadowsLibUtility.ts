// @strict: true
// @target: esnext

// In a MODULE, a file's own `type NonNullable<T> = T` is not the lib utility.
// (In a script the same declaration is TS2300 against the lib.)

export {};
type NonNullable<T> = T;
function okLocalNonNullable<T>(x: T) { const y: NonNullable<T> = x; return y; }
function badLibSpelling<T>(x: T) { const y: T & {} = x; return y; }
