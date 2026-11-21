// @strict: true

// A function declaration in a body is hoisted: a call made before it, or
// from a function declared before it, sees its signature. After
// `s.body = g(k)` with `g(k): Top`, `s.body` is a `Top`.

interface Top { t: number }
declare function make(k: string): Top;
class Slot { body: Top | undefined; constructor(readonly key: string) {} }
declare const slots: Slot[];

export function okHoistedInNested(): Top {
  const slots = new Map<string, Slot>();
  function resolve(key: string): Top {
    let slot = slots.get(key);
    if (slot === undefined) { slot = new Slot(key); }
    slot.body = later(key);
    return slot.body;
  }
  function later(k: string): Top { return make(k); }
  return resolve("a");
}
export function okHoistedSimple(s: Slot): Top {
  s.body = later2("k");
  return s.body;
  function later2(k: string): Top { return make(k); }
}
export function okHoistedInArrow() {
  const f = (s: Slot): Top => {
    s.body = later3("k");
    return s.body;
    function later3(k: string): Top { return make(k); }
  };
  return f;
}
export const okHoistedInFunctionExpression = function (s: Slot): Top {
  s.body = later5("k");
  return s.body;
  function later5(k: string): Top { return make(k); }
};
export function okHoistedInBlock(s: Slot, c: boolean): Top {
  if (c) {
    s.body = later6("k");
    return s.body;
    function later6(k: string): Top { return make(k); }
  }
  return make("x");
}
export const okHoistedInCallback: Top[] = slots.map((s) => {
  s.body = later7("k");
  const t: Top = s.body;
  return t;
  function later7(k: string): Top { return make(k); }
});
export function okHoistedInBareBlock(s: Slot): Top {
  {
    s.body = later8("k");
    const t: Top = s.body;
    return t;
    function later8(k: string): Top { return make(k); }
  }
}
export function okHoistedInLoop(s: Slot): Top {
  while (true) {
    s.body = later9("k");
    const t: Top = s.body;
    return t;
    function later9(k: string): Top { return make(k); }
  }
}
export function badHoistedReturnUsed(s: Slot): string {
  s.body = later4("k");
  return s.body;
  function later4(k: string): Top { return make(k); }
}
