export namespace JSX {
  interface Element {}
}

export type ElementType = string;
export type Key = string;

export interface ReactElement {}

export interface JSXSource {
  fileName?: string | undefined;
  lineNumber?: number | undefined;
  columnNumber?: number | undefined;
}

export function jsxDEV(
  type: ElementType,
  props: unknown,
  key: Key | undefined,
  isStatic: boolean,
  source?: JSXSource,
  self?: unknown,
): ReactElement;
