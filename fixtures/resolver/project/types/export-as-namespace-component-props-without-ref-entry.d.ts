declare namespace ReactLike {
  namespace JSX {
    interface IntrinsicElements {
      badge: BadgeProps;
    }
  }

  interface BadgeProps {
    label: string;
  }

  type ComponentPropsWithoutRef<T extends keyof JSX.IntrinsicElements> =
    JSX.IntrinsicElements[T];

  function createBadge(
    props: ComponentPropsWithoutRef<"badge">
  ): ComponentPropsWithoutRef<"badge">;
}

export = ReactLike;
export as namespace ReactLike;
