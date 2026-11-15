// @strict: true
// @target: esnext

// `fx<>` is TS1099; `fx<string>` is a legal instantiation expression.

declare function fx<T>(x: T): T;
function bad1(): unknown { return fx<>; }
function ok1(): unknown { return fx<string>; }
