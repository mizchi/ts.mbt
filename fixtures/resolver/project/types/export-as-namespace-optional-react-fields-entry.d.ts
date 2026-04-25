declare namespace ReactLike {
  type ReactNode = string | number;

  interface Ref<T> {
    current: T;
  }

  interface BadgeProps {
    label?: string | undefined;
    children?: ReactNode | undefined;
    ref?: Ref<string> | undefined;
  }

  function renderBadge(props: BadgeProps): BadgeProps;
}

export = ReactLike;
export as namespace ReactLike;
