// @strict: true
// @target: esnext

// `x = a || b` is never nullish when `b` is not, whatever `a` is, so it
// removes the declared `undefined`. A right operand that may be nullish
// keeps it.

class Viewport { x = 1; }
class Scene {
    private _all: Viewport[] = [];
    private _main = new Viewport();
    find(n: number) { return this._all.find((v) => v.x === n); }
    getDefault() { return this._main; }
    use(v: Viewport) { return v.x; }
    okOrFallback(n: number, vp?: Viewport) {
        if (!vp) {
            vp = this.find(n) || this.getDefault();
        }
        return this.use(vp);
    }
    okOrNew(n: number, vp?: Viewport) {
        if (!vp) {
            vp = this.find(n) || new Viewport();
        }
        return this.use(vp);
    }
    badOrMaybe(n: number, vp?: Viewport) {
        if (!vp) {
            vp = this.find(n) || this.find(n + 1);
        }
        return this.use(vp);
    }
}
