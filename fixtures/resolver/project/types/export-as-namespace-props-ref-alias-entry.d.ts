declare namespace ReactLike {
  type ReactNode = string | number;

  interface BadgeProps {
    label: string;
  }

  type PropsWithChildren<P> = P & { children?: ReactNode | undefined };
  type PropsWithoutRef<Props> = Props;
  type PropsWithRef<Props> = Props;

  function stripRef(
    props: PropsWithoutRef<BadgeProps>
  ): PropsWithoutRef<BadgeProps>;

  function keepRef(
    props: PropsWithRef<BadgeProps>
  ): PropsWithRef<BadgeProps>;

  function nested(
    props: PropsWithoutRef<PropsWithChildren<BadgeProps>>
  ): PropsWithoutRef<PropsWithChildren<BadgeProps>>;
}

export = ReactLike;
export as namespace ReactLike;
