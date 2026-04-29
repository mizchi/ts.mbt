export interface User {
  id: string;
  name: string;
  age: number;
  active?: boolean;
}

export function pickUser(user: Pick<User, "id" | "name">): Pick<
  User,
  "id" | "active"
>;

export function omitUser(user: Omit<User, "age">): Omit<User, "active">;

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

export function getLabels(): Record<string, string>;

export function setLabels(labels: Record<string, string | number>): void;

export function getUsersById(): Record<string, User>;

export class UtilityError {
  readonly issues: [User, ...User[]];
  constructor(issues: [User, ...User[]]);
}
