import { z } from "zod";
const User = z.object({ name: z.string(), age: z.number().int().min(0).optional(), tags: z.array(z.string()) });
export type User = z.infer<typeof User>;
export function parseUser(input: unknown): User | null {
  const r = User.safeParse(input);
  if (!r.success) return null;
  const u: User = r.data;
  return { ...u, name: u.name.trim() };
}
export const Email = z.string().email();
export const n: number | undefined = User.parse({ name: "a", tags: [] }).age;
