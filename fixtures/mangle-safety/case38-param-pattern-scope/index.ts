// A pattern default is evaluated in the scope the pattern introduces
// names into, but it is WRITTEN outside the body — in a parameter list
// or on a catch clause. The free-variable walk that reserves short
// names looked only at the body, so `fallback` was never reserved and
// the pattern's own binder took its letter:
//
//   function b({n: a = a}) { return a; }        // TDZ
//   catch ({message: a = a}) { return a; }      // TDZ
//
// Both throw `ReferenceError: Cannot access 'a' before initialization`
// under plain `--mangle`, with no property mangling involved.
const fallback = 9;
const label = "fb";

function fromParam({ n = fallback }: { n?: number }): number {
  return n;
}

function fromParamWholeDefault({ n = fallback } = {}): number {
  return n;
}

function fromCatch(): string {
  try {
    throw {};
  } catch ({ message = label }: any) {
    return message;
  }
}

export const report = {
  param: fromParam({}),
  paramDefaulted: fromParamWholeDefault(),
  caught: fromCatch(),
};
console.log(report);
