// @jsx: preserve

// A `{…}` payload inside a JSX element is JavaScript, so a malformed
// numeric literal there is an error, in a child, an attribute value, a
// nested element's payload, and a payload that does not parse.

declare global {
  namespace JSX {
    interface IntrinsicElements { p: { a?: unknown }; b: {} }
  }
}

declare const ok: boolean;

export const badChildHex = <p>{0x}</p>;
export const badAttributeOctal = <p a={0o9} />;
export const badNestedHex = <p>{ok && <b>{0x}</b>}</p>;
export const okText = <p>0x and 08</p>;
