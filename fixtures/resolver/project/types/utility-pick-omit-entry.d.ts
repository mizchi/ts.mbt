export interface User {
  readonly createdAt: string;
  id: string;
  name: string;
  age: number;
  active?: boolean;
}

export type InlineMapped = {
  [K in "id" | "name"]?: string;
};

export function pickUser(user: Pick<User, "id" | "name">): Pick<
  User,
  "id" | "active"
>;

export function omitUser(user: Omit<User, "age">): Omit<User, "active">;

export function patchUser(user: Partial<User>): Partial<User>;

export function readonlyUser(user: Readonly<User>): Readonly<User>;

export function requiredUser(user: Required<User>): Required<User>;

export function requireUser(
  id: NonNullable<string | undefined>
): NonNullable<User | null>;

export function extractUser(user: Extract<User | undefined, User>): Exclude<
  User | null,
  null
>;

export function getCount(): ReturnType<(value: string) => number>;

export function getArgs(): Parameters<
  (name: string, active: boolean) => void
>;

export function getStaticConditionalTrue(): string extends string
  ? number
  : boolean;

export function getStaticConditionalFalse(): number extends string
  ? number
  : boolean;

export function getAwaitedName(): Awaited<Promise<string>>;

export function getInferredPromiseName(): Promise<string> extends Promise<
  infer Name
>
  ? Name
  : never;

export type UnwrapPromise<T> = T extends Promise<infer Value> ? Value : never;

export function getGenericInferredPromiseName(): UnwrapPromise<Promise<string>>;

export function getInlineMapped(): InlineMapped;

export function getLabels(): Record<string, string>;

export function setLabels(labels: Record<string, string | number>): void;

export function getUsersById(): Record<string, User>;

export class UtilityError {
  readonly issues: [User, ...User[]];
  constructor(issues: [User, ...User[]]);
}
