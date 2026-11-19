// @strict: true
// @target: esnext

// A constructor's destructuring parameter binds every name it declares, as a
// method's or a function's does, each with its member's type. A checker that
// keeps one name per parameter has to keep the pattern too, or the names
// after the first are unbound.

export class OkObjectPattern {
  x: number; y: string;
  constructor({ a, b }: { a: number; b: string }) { this.x = a; this.y = b; }
}
export class OkArrayPatternWithRest {
  z: string[];
  constructor([c, ...d]: string[]) { const s: string = c; this.z = d; }
}
export class OkDefaultedPattern {
  constructor({ a, b }: { a: number; b: string } = { a: 1, b: "" }) { const n: number = a; const s: string = b; }
}
export class BadSecondNameMistyped {
  constructor({ a, b }: { a: number; b: string }) { const n: number = b; }
}
export class BadFirstNameMistyped {
  constructor({ a, b }: { a: number; b: string } = { a: 1, b: "" }) { const s: string = a; }
}
