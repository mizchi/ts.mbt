declare namespace ReactLike {
  const version: string;

  interface Context<T> {
    value: T;
  }

  class Component<P, S> {
    props: P;
    state: S;
  }

  function useContext<T>(context: Context<T>): T;
}

export = ReactLike;
export as namespace ReactLike;
