// @jsx: preserve

// A `{…}` payload is JavaScript, and one whose parse fails before it reaches
// a nested element still holds that element's lexer errors: here a `for`
// head has no `;` to end its condition.

declare global {
  namespace JSX {
    interface IntrinsicElements { p: {}; b: {} }
  }
}

export const badPayloadMissingSemicolon = <p>{(() => { for (; <b>{0x}</b> ) {} })()}</p>;
