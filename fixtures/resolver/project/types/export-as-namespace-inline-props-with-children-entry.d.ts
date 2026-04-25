declare namespace ReactLike {
  type ReactNode = string | number;
  type PropsWithChildren<P> = P & { children?: ReactNode | undefined };

  function createBadge(
    props: PropsWithChildren<{ label: string; count: number }>
  ): PropsWithChildren<{ label: string; count: number }>;
}

export = ReactLike;
export as namespace ReactLike;
