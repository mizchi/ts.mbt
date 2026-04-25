declare namespace ReactLike {
  type ReactNode = string | number;
  type PropsWithChildren<P> = P & { children?: ReactNode | undefined };

  interface BadgeProps {
    label: string;
  }

  function createBadge(
    props: PropsWithChildren<BadgeProps>
  ): PropsWithChildren<BadgeProps>;
}

export = ReactLike;
export as namespace ReactLike;
