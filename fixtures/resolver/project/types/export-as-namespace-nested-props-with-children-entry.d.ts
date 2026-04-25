declare namespace ReactLike {
  namespace JSX {
    interface IntrinsicElements {
      badge: BadgeProps;
    }
  }

  type ReactNode = string | number;

  interface BadgeProps {
    label: string;
  }

  type ComponentPropsWithoutRef<T extends keyof JSX.IntrinsicElements> =
    JSX.IntrinsicElements[T];

  type PropsWithChildren<P> =
    P & { children?: ReactNode | undefined };

  function createBadge(
    props: PropsWithChildren<ComponentPropsWithoutRef<"badge">>
  ): PropsWithChildren<ComponentPropsWithoutRef<"badge">>;
}

export = ReactLike;
export as namespace ReactLike;
