// Trailing-parameter trimming, and the conditions that must block it —
// all in one file so the differential run covers each together.
let ticks = 0;
function bump(): number {
  ticks = ticks + 1;
  return 1;
}

// Trimmable: `unusedOpts` is dead and every argument for it is pure.
function fmt(value: number, unusedOpts: { pad: boolean }): string {
  return String(value);
}

// Not trimmable — its arity is part of the package ABI.
export function exported(a: number, unused: number): number {
  return a;
}

// Not trimmable — held as a value, so any caller may pick the arity.
function asValue(a: number, unused: number): number {
  return a;
}
const held: (a: number, u: number) => number = asValue;

// Not trimmable — the dropped argument has an effect.
function impureArg(a: number, unused: number): number {
  return a;
}

// Not trimmable — `arguments` sees the real list whatever the
// parameters say.
function readsArguments(a: number, unused: number): number {
  return a + arguments.length;
}

// Not trimmable — dropping the parameter would stop evaluating the
// default.
function withDefault(a: number, unused: number = bump()): number {
  return a;
}

export const report = {
  formatted: fmt(1, { pad: true }) + fmt(2, { pad: false }),
  exported: exported(1, 9),
  held: held(2, 9),
  impure: impureArg(3, bump()),
  argCount: readsArguments(4, 9),
  defaulted: withDefault(5),
  ticks,
};
