// @strict: true
// @target: esnext

// A static factory's inferred return reads each `return` in its own scope:
// a nested `const value = null` shadows the parameter `value`, so the
// factory can return `null` and a field assigned from it stays nullable.
// A nested declaration of an unrelated name changes nothing.

declare function takeS(s: string): void;

export class K { static make(value: string, flag: boolean) { if (flag) { const value = null; return value; } return value; } }
export class BadShadowedReturnKeepsNull { p: string | null = null; set(v: string) { this.p = K.make(v, true); takeS(this.p); } }
export class K2 { static make(value: string) { if (value) { const other = 1; return value + other; } return value; } }
export class OkUnrelatedNestedName { p: string | null = null; set(v: string) { this.p = K2.make(v); takeS(this.p); } }
export class K3 { static make(value: string, flag: boolean) { if (flag) { const value = null; } return value; } }
export class OkTopLevelReturnReadsParameter { p: string | null = null; set(v: string) { this.p = K3.make(v, true); takeS(this.p); } }
export class K4 { static make(value: string) { for (const value of [null]) { return value; } return value; } }
export class BadLoopHeadShadows { p: string | null = null; set(v: string) { this.p = K4.make(v); takeS(this.p); } }
