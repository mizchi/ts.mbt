declare namespace React {
  type ReactNode = string | number;
}

export interface RouteLike {
  element?: React.ReactNode | null;
  errorElement?: React.ReactNode | null;
}
