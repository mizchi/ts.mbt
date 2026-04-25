declare namespace ReactLike {
  interface Props {
    type: string;
    ref: string;
  }

  interface ReactElement {
    type: string;
    ref: string;
  }

  function jsx(type: string, props: Props): ReactElement;
  function use(promise: Promise<string>): string;
  function forwardRef(Component: any): any;
  function useActionState(fn: any, initialState: string, permalink: string): string;
  function Fragment(children: string): ReactElement;
  function StrictMode(children: string): ReactElement;
}

export = ReactLike;
export as namespace ReactLike;
