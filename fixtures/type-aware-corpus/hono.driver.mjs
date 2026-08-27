// Routing, middleware order, params, JSON bodies, and the error path.
// Every observation goes through the router, so a mangled property that
// the router reads by name shows up as a changed status or body.
import { Hono } from "./target.mjs";
const app = new Hono();
app.use("*", async (c, next) => {
  await next();
  c.res.headers.set("X-Trace", (c.req.header("x-in") ?? "-") + ":done");
});
app.get("/", (c) => c.text("root"));
app.get("/u/:id", (c) => c.json({ id: c.req.param("id"), q: c.req.query("q") ?? null }));
app.post("/echo", async (c) => c.json({ got: await c.req.json() }));
app.get("/boom", () => { throw new Error("boom"); });
app.onError((e, c) => c.json({ error: e.message }, 500));
app.notFound((c) => c.json({ missing: c.req.path }, 404));
const calls = [
  ["GET", "http://x/", null],
  ["GET", "http://x/u/42?q=hi", null],
  ["POST", "http://x/echo", JSON.stringify({ a: [1, 2], b: { c: true } })],
  ["GET", "http://x/boom", null],
  ["GET", "http://x/nope", null],
];
const out = [];
for (const [method, url, body] of calls) {
  const res = await app.fetch(new Request(url, {
    method,
    body: body ?? undefined,
    headers: body ? { "content-type": "application/json", "x-in": "t" } : { "x-in": "t" },
  }));
  out.push({ url, status: res.status, trace: res.headers.get("X-Trace"), body: await res.text() });
}
console.log(JSON.stringify(out, null, 1));
