declare namespace ReactLike {
  type Dispatch<A> = (value: A) => void;
  type ActionDispatch<A> = (action: A) => void;
  type TransitionFunction = () => void;

  function useState<S>(initialState: S): [S, Dispatch<S>];
  function useReducer<S, A>(
    reducer: (prevState: S, action: A) => S,
    initialState: S
  ): [S, ActionDispatch<A>];
  function useTransition(): [boolean, TransitionFunction];
  function useOptimistic<State>(
    passthrough: State
  ): [State, (action: State) => void];
  function useActionState<State>(
    action: (state: State) => State | Promise<State>,
    initialState: State,
    permalink?: string
  ): [State, () => void, boolean];
}

export = ReactLike;
export as namespace ReactLike;
