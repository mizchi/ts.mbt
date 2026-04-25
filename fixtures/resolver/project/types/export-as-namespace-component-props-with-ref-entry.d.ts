declare namespace ReactLike {
  namespace JSX {
    interface IntrinsicElements {
      badge: BadgeProps;
    }
  }

  interface BadgeProps {
    label: string;
  }

  interface Element {
    id: string;
  }

  interface Ref<T> {
    current: T;
  }

  interface RefAttributes<T> {
    ref: Ref<T>;
  }

  type ComponentPropsWithRef<T extends keyof JSX.IntrinsicElements> =
    JSX.IntrinsicElements[T] & RefAttributes<Element>;

  function createBadge(
    props: ComponentPropsWithRef<"badge">
  ): ComponentPropsWithRef<"badge">;
}

export = ReactLike;
export as namespace ReactLike;
