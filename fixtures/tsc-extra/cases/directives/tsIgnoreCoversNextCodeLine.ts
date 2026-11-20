// A `@ts-ignore` or `@ts-expect-error` comment suppresses what tsc reports on
// the first line after it that is neither blank nor a `//` comment. The
// directive may follow code on its own line, may have no space after `//`,
// and may be a one-line block comment. A block comment counts only on its
// last line, a report on the line BEFORE the directive stands, and a report
// on a later line of the statement the directive starts stands too.

declare const n: number;

export class okNoSpace {
  constructor(readonly w: number) {}
  m() {
    //@ts-ignore
    this.w = 1;
  }
}
export class okExpectError {
  constructor(readonly w: number) {}
  m() {
    // @ts-expect-error
    this.w = 2;
  }
}
export class badNoDirective {
  constructor(readonly w: number) {}
  m() {
    this.w = 3;
  }
}
// @ts-ignore
export const okTopLevel: string = n;
// @ts-ignore

export const okBlankLine: string = n;
// @ts-ignore
// a comment line in between
export const okCommentLineBetween: string = n;
export const trailing = 1; // @ts-ignore
export const okAfterTrailing: string = n;
/* @ts-ignore */
export const okBlockComment: string = n;
/* @ts-ignore
 */
export const badBlockFirstLine: string = n;
/* @ts-ignore
*/ export const badBlockEndsBeforeCode: string = n;
// @ts-ignore
export const okAfterNestedBody: string = ((() => { return 1; })(), n);
export function okInsideStatement() {
  const s: number = Math.max(
    // @ts-ignore
    "a",
    1,
  );
  return s;
}
export function badDirectiveAfterError() {
  const s: string =
    // @ts-ignore
    n;
  return s;
}
export function badInsideCompound(c: boolean) {
  // @ts-ignore
  if (c) {
    const inner: string = n;
    return inner;
  }
  return "";
}
export function okCompoundHead(c: number) {
  // @ts-ignore
  if (c.nope) {
    return 1;
  }
  return 0;
}
// @ts-ignore
export const badLaterLineOfStatement: { a: string } = {
  a: n,
};
export function okParenArrowInCondition() {
  if ((() => {
    // @ts-ignore
    const x: string = n;
    return true;
  })()) {
    return 1;
  }
  return 0;
}
export function badMissingReturnAfterCovered(c: boolean): number {
  if (c) {
    return 1;
  }
  // @ts-ignore
  const z: string = n;
}
export function okLoopHeadAfterBody(c: number) {
  let i = 0;
  // @ts-ignore
  while (c.nope && i < 3) {
    i++;
  }
  return i;
}
export function coveredLast() {
  // @ts-ignore
  const z: string = n;
}
export function badDefaultAfterCovered(x: string = n) {
  return x;
}
