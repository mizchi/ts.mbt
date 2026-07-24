export type To = string | { pathname?: string };

export interface NavigateOptions {
  replace?: boolean;
}

export interface Router {
  /**
   * Navigate forward/backward in the history stack.
   */
  navigate(to: number): Promise<void>;
  /**
   * Navigate to the given path.
   */
  navigate(to: To | null, opts?: NavigateOptions): Promise<void>;
  /**
   * Trailing-param overloads still merge (no companion).
   */
  fetch(key: string): Promise<void>;
  fetch(key: string, routeId: string): Promise<void>;
}
