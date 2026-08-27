// A type guard applied to an argument that does something.
//
// `predicate-inline` substitutes the guard's body at the call site, and
// the substitution copies the ARGUMENT once per reference to the
// parameter. Nothing checked that the argument was safe to write twice,
// so a three-term guard turned
//
//   isOne(bump())
//
// into `bump() === 1 && bump() !== 2 && bump() > 0` and the counter came
// back 3 instead of 1. Every shape below puts an effect in the argument
// position of a guard whose body reads its parameter more than once.

let effects = 0;

function bump(): number {
  effects = effects + 1;
  return 1;
}

const log: string[] = [];

function record(tag: string): { tag: string; n: number } {
  log.push(tag);
  return { tag, n: 1 };
}

// 1. A multi-term guard over a plain value.
function isOne(x: number): x is 1 {
  return x === 1 && x !== 2 && x > 0;
}
const first = isOne(bump());

// 2. A guard whose body reads a property of the parameter twice: the
//    receiver is a getter, so each read is observable.
type Tagged = { tag: string; n: number };
function isTagged(v: { tag: string; n: number }): v is Tagged {
  return typeof v.tag === "string" && v.n > 0;
}
const second = isTagged(record("first"));

// 3. The same guard where the argument IS safe to duplicate — an
//    identifier. This one may be inlined, and must still be correct.
const held = record("held");
const third = isTagged(held);

// 4. An increment in the argument position.
let counter = 0;
const fourth = isOne(++counter);

// `held` goes into the report so its `tag` / `n` are observable: the
// corpus's mutation self-check requires every `expectKeep` name to
// change what the program prints, or the case cannot witness a rename.
export const report = { first, second, third, fourth, effects, log, counter, held };
console.log(JSON.stringify(report));
