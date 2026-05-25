import { Hono } from "hono";

const app = new Hono();

app.get("/", (c) => c.text("hello"));
app.get("/users/:id", (c) => c.json({ id: c.req.param("id") }));
app.post("/users", async (c) => {
  const body = await c.req.json();
  return c.json({ ok: true, body });
});
app.notFound((c) => c.text("not found", 404));
app.onError((err, c) => c.text("error: " + err.message, 500));

export default app;
