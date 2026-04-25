declare namespace ReactLike {
  namespace JSX {
    interface Element {
      kind: string;
    }

    interface IntrinsicElements {
      badge: BadgeProps;
    }

    interface LibraryManagedAttributes<C, P> {
      props: P;
    }
  }

  interface BadgeProps {
    label: string;
  }

  function createElement(tag: keyof JSX.IntrinsicElements): JSX.Element;
}

export = ReactLike;
export as namespace ReactLike;
