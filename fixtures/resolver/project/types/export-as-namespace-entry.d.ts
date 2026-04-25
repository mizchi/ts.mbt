declare namespace ReactLike {
  interface Context<T> {
    value: T;
  }

  function createContext<T>(defaultValue: T): Context<T>;
}

export = ReactLike;
export as namespace ReactLike;
