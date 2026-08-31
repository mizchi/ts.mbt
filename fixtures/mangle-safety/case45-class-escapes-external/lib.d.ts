declare module "host-registry" {
  // A host that receives a value and, later, calls something on it.
  // The declaration says nothing about WHICH method — that is the
  // point: the bundle cannot know, so it must not delete any.
  export function register(handler: unknown): void;
  export function runAll(): string[];
}
