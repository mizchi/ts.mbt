// A NAMED FUNCTION EXPRESSION held in an object-literal property, whose
// body calls itself by that name.
//
// The parser stored `{ foo() {} }` and `{ foo: function foo() {} }`
// identically as `("foo", FuncExpr { name: "foo" })`, and two consumers
// then guessed which one they had:
//
//   - the emitter reconstructed a method shorthand by testing
//     `f.name == key`, which is also true of the named function
//     expression — so this file re-emitted as `{ fact(n) { … } }` and
//     `fact` stopped being bound at all;
//   - `emit_function_expr` additionally drops the name whenever the body
//     references it, which is right for a BORROWED member key (a class
//     method lowered to `C.prototype.m = function m() {}` must not
//     shadow an outer `m` — see `outerCollision` below) and wrong here,
//     where the reference IS the recursion the source wrote.
//
// Either one alone turns `b.fact(5)` into `ReferenceError: fact is not
// defined`, under plain `mtsc` with no optimization flag. `TsFunc` now
// carries `name_is_member_key`, so the two shapes are told apart rather
// than guessed.
//
// Both directions are observed, because a fix that simply stopped
// dropping the name would break the class-method case this file also
// covers: `shadowed` must call the OUTER `helper`, not itself.

function helper(n: number): number {
  return n * 2;
}

// Direction 1: the name IS a binding — recursion must survive.
const b = {
  fact: function fact(n: number): number {
    return n <= 1 ? 1 : n * fact(n - 1);
  },
};

// Direction 2: a real method shorthand binds NOTHING, so a body
// reference of the same spelling must reach the outer declaration.
const shorthandReachesOuter = {
  helper(): number {
    return helper(10);
  },
};

// Direction 2 again, through the class-method lowering: the emitted
// function expression must stay anonymous or `helper` would resolve to
// itself and recurse forever.
class Holder {
  x: number = 3;
  helper(): number {
    return helper(this.x);
  }
}

export const factorial = b.fact(5);
export const viaShorthand = shorthandReachesOuter.helper();
export const viaClassMethod = new Holder().helper();
