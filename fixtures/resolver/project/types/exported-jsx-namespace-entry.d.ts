export namespace JSX {
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

export interface BadgeProps {
  label: string;
}

export function jsx(
  tag: keyof JSX.IntrinsicElements,
  props: BadgeProps,
): JSX.Element;
