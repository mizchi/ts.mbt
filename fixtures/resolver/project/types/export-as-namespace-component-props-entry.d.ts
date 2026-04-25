declare namespace ReactLike {
  namespace JSX {
    interface IntrinsicElements {
      badge: BadgeProps;
    }
  }

  interface BadgeProps {
    label: string;
  }

  type ComponentProps<T extends keyof JSX.IntrinsicElements> =
    JSX.IntrinsicElements[T];

  function createBadge(
    props: ComponentProps<"badge">
  ): ComponentProps<"badge">;
}

export = ReactLike;
export as namespace ReactLike;
