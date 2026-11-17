// @strict: true
// @target: esnext

// An accessor pair carries one visibility per half. A read reaches the
// getter and a write the setter, so a public getter beside a protected or
// private setter is readable anywhere, while assigning to it outside the
// class is an error. A compound assignment both reads and writes, so the
// stricter setter decides it. tsc requires the getter to be at least as
// accessible as the setter, which is why only that direction appears.

class B {
  private _l = 0;
  protected x = 0;
  get left(): number { return this._l }
  protected set left(v: number) { this._l = v }
  get top(): number { return this._l }
  private set top(v: number) { this._l = v }
  private get secret(): number { return 1 }
  private set secret(v: number) {}
  static get count(): number { return 0 }
  protected static set count(v: number) {}
}

declare const b: B;

class OkSubclassReadsAndWrites extends B {
  m() { this.left = 2; this.left += 1; return this.left; }
}
function okReadPublicGetter() { const n: number = b.left; }
function okReadInExpression() { const n = b.left + b.top; }
function okDestructurePublicGetter() { const { left } = b; }
function okStaticRead() { const n: number = B.count; }
function badWriteProtectedSetter() { b.left = 1; }
function badWritePrivateSetter() { b.top = 1; }
function badCompoundWrite() { b.left += 1; }
function badReadPrivatePair() { const n = b.secret; }
function badStaticWrite() { B.count = 1; }
function badProtectedFieldCompound() { b.x += 1; }
function badPostIncrement() { b.left++; }
function badPreDecrement() { --b.left; }
