// @target: esnext
// @lib: esnext

// A directive covers what tsc reports on the line it targets. Each cell
// reaches its statement somewhere other than a plain statement list: the
// declarators of one declaration, a `for` head's init, the `if` of an
// `else if`, a `using` declaration and the disposal of what it acquired,
// an `as` type, and an arrow body inside a template substitution.

declare const x: unknown;
type D = { [Symbol.dispose](): void };
declare const d: D;
declare function tag(s: TemplateStringsArray, ...v: unknown[]): string;

export function okAsDup() {
  // @ts-ignore
  return x as { a: string; a: string };
}
export function badAsDup() {
  return x as { b: string; b: string };
}

// @ts-ignore
export let okGroupA: string = 1, okGroupB: string = 2;
export let badGroupA: string = 1, okGroupC = 2;

// A directive inside the declaration covers the declarator on its line.
export let okGroupLaterA = 1,
  // @ts-ignore
  okGroupLaterB: string = 2;
export let laterA = 1,
  badGroupLaterB: string = 2;

export function okElseIf(c: boolean) {
  if (c) {
    return 0;
  } else
  // @ts-ignore
  if (1 === "x") {
    return 1;
  }
  return 2;
}

export function okForHead() {
  // @ts-ignore
  for (let a: string = 1, b: string = 2; ;) { break; }
}

// The head is covered and the body is not.
export function badForBody() {
  // @ts-ignore
  for (let a: string = 1; ;) {
    const body: string = 2;
    break;
  }
}

export function okUsing() {
  // @ts-ignore
  using u: D = 1;
}

export function okUsingGroup() {
  // @ts-ignore
  using u1: D = d, u2: D = 2;
}

export function badUsing() {
  using v: D = 3;
}

export function okForUsing() {
  // @ts-ignore
  for (using w: D = 4; ;) { break; }
}

export function okTemplate() {
  return `${(() => {
    // @ts-ignore
    const inTemplate: string = 3;
    return inTemplate;
  })()}`;
}

export function badTemplate() {
  return `${(() => {
    const inTemplate: string = 4;
    return inTemplate;
  })()}`;
}

export function okTagged() {
  return tag`${(() => {
    // @ts-ignore
    const inTagged: string = 5;
    return inTagged;
  })()}`;
}
