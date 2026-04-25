declare namespace ReactLike {
  type Dispatch<A> = (value: A) => void;
  type TransitionFunction = () => void;

  function useState<S>(initialState: S): [S, Dispatch<S>];
  function useTransition(): [boolean, TransitionFunction];
}

export = ReactLike;
export as namespace ReactLike;
