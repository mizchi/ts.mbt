// hono, used the way its README's only example uses it, widened to the
// surfaces the package-entry driver exercises (params, JSON, the error
// and not-found paths) so the two entries observe the same behaviour.
//
// `app` itself is not exported: an exported router would put every
// method name on the bundle's surface, which is the package-entry
// situation this row exists to contrast with. The exports are the
// strings the app produced.

import { Hono } from "./src/index.ts";

type Reply = { id: string; q: string | null };

const app = new Hono();
app.use("*", async (c, next) => {
  await next();
  c.res.headers.set("X-Trace", (c.req.header("x-in") ?? "-") + ":done");
});
app.get("/", (c) => c.text("root"));
app.get("/u/:id", (c) => {
  const reply: Reply = { id: c.req.param("id"), q: c.req.query("q") ?? null };
  return c.json(reply);
});
app.post("/echo", async (c) => c.json({ got: await c.req.json() }));
app.get("/boom", () => {
  throw new Error("boom");
});
app.onError((e, c) => c.json({ error: e.message }, 500));
app.notFound((c) => c.json({ missing: c.req.path }, 404));

async function call(
  method: string,
  url: string,
  body: string | null,
): Promise<string> {
  const res = await app.fetch(
    new Request(url, {
      method,
      body: body ?? undefined,
      headers: body
        ? { "content-type": "application/json", "x-in": "t" }
        : { "x-in": "t" },
    }),
  );
  return res.status + " " + res.headers.get("X-Trace") + " " + await res.text();
}

export async function observe(): Promise<string> {
  const out: string[] = [];
  out.push(await call("GET", "http://x/", null));
  out.push(await call("GET", "http://x/u/42?q=hi", null));
  out.push(
    await call("POST", "http://x/echo", JSON.stringify({ a: [1, 2], b: { c: true } })),
  );
  out.push(await call("GET", "http://x/boom", null));
  out.push(await call("GET", "http://x/nope", null));
  return out.join("\n");
}
