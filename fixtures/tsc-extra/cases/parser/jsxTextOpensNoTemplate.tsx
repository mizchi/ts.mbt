// @jsx: preserve

// JSX text is not JavaScript: a backtick in JSX text is text, not the start of a template literal, so
// the declarations after the element are still checked.

declare global {
  namespace JSX {
    interface IntrinsicElements { p: {} }
  }
}

export const okOpenerInText = <p>cost `x</p>;
export const badAfterElement: string = 1;
export function badLaterFunction(): number { return "s"; }
