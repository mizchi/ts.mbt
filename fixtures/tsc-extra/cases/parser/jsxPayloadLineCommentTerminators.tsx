// @jsx: preserve

// A line comment inside a JSX `{…}` payload ends at a line terminator, and
// LS and PS are line terminators as LF and CR are: the call after the
// comment is part of the payload, and its argument is checked. The file
// holds the raw characters.

declare global {
  namespace JSX {
    interface IntrinsicElements { div: {} }
  }
}

declare function f(n: number): number;

export function badAfterLs() { return <div>{ // note  f("x") }</div>; }
export function badAfterPs() { return <div>{ // note  f("y") }</div>; }
export function badAfterLf() {
  return <div>{ // note
    f("z") }</div>;
}
export function okAfterLs() { return <div>{ // note  f(1) }</div>; }
