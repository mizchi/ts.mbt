// valibot, used the way its README's first example uses it, plus the
// failure path (the README's `output1` throws, so it is wrapped).
//
// Every export is a scalar.

import * as v from "./library/src/index.ts";

const LoginSchema = v.object({
  email: v.pipe(v.string(), v.email()),
  password: v.pipe(v.string(), v.minLength(8)),
});

type LoginData = v.InferOutput<typeof LoginSchema>;

function attempt(input: unknown): string {
  const r = v.safeParse(LoginSchema, input);
  if (r.success) {
    const data: LoginData = r.output;
    return "ok:" + data.email + "/" + data.password.length;
  }
  return "fail:" +
    r.issues.map((i) => i.kind + "." + i.type + "@" + (i.path ?? []).length)
      .join(",");
}

export const bad: string = attempt({ email: "", password: "" });
export const good: string = attempt({
  email: "jane@example.com",
  password: "12345678",
});
export const wrongType: string = attempt({ email: 1, password: null });
export const notObject: string = attempt(42);
