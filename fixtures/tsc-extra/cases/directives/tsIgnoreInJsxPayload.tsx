// @jsx: preserve

// A JSX payload is read by a sub-parser over its own text: a directive
// inside the payload still covers the next line.

declare global {
  namespace JSX {
    interface IntrinsicElements { div: {} }
  }
}

export function okPayload() {
  return <div>{(() => {
    // @ts-ignore
    const covered: string = 1;
    return covered;
  })()}</div>;
}

export function badPayload() {
  return <div>{(() => {
    const uncovered: string = 2;
    return uncovered;
  })()}</div>;
}
