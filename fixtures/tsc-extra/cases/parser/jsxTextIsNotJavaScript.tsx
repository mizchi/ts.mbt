// @jsx: preserve

// JSX text and a JSX attribute string are not JavaScript, so nothing in
// them is a numeric literal, a template or an escape: `0.08em`, `08`,
// `017`, `0x`, a backtick and `¬` are all just characters. An attribute
// string may also span lines, which is how a long Tailwind class list is
// written.

declare global {
  namespace JSX {
    interface IntrinsicElements { p: {}; div: { className?: string }; b: {} }
  }
}

declare const ok: boolean;

export const okNumbersInText = <p>width 0.08em, 08 px, 017, 0x</p>;
export const okBacktickInText = <p>cost `x</p>;
export const okSymbolInText = <p>a ¬ b</p>;
export const okMultilineClass = <div
  className="
    univer-tracking-[0.08em] univer-p-08
    univer-grid-cols-[32px_minmax(0,1fr)_32px]
  "
/>;
export const okNestedText = <p>{ok && <b>w 0.08em</b>}</p>;
