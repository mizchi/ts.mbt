declare namespace ReactLike {
  type JSXElementConstructor<P> =
    | ((
        props: P,
      ) => ReactNode | Promise<ReactNode>)
    | (new(props: P, context: any) => Component<any, any>);
}

export = ReactLike;
export as namespace ReactLike;
