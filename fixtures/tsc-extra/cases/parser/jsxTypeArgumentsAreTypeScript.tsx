// @jsx: preserve

// A JSX element's type arguments are TypeScript, not JSX text, so a
// malformed numeric literal there is an error; the element's text is still
// text. A payload inside a parenthesized expression that does not parse is
// still read, and an unterminated block comment after an element starts
// outside it (a `/*` inside JSX text is `jsxTextOpensNoBlockComment`).

declare global {
  namespace JSX {
    interface IntrinsicElements { p: {}; b: {} }
  }
}

declare function Box<T>(p: { children?: unknown }): any;

export const badTypeArgumentHex = <Box<0x> />;
export const okTypeArgumentText = <Box<string>>08 px</Box>;
export const badPayloadInFailedParens = <p>{(true && <b>{0x}</b>,)}</p>;
export const badPayloadInFailedForHead = <p>{(() => { for (; <b>{0x}</b>, ; ) {} })()}</p>;
export const badCommentAfterElement = <p /> /*