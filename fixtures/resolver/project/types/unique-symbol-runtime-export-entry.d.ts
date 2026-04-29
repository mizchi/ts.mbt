declare module "node:assert" {
  export const kOptions: unique symbol;
  export function ok(value: boolean): void;
}
