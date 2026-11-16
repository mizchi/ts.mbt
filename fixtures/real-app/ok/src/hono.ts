import { Hono } from "hono";
import type { Context } from "hono";
const app = new Hono();
app.get("/", (c) => c.text("hi"));
app.post("/json", async (c: Context) => { const body = await c.req.json(); return c.json({ ok: true, body }); });
export default app;
export const handler: (req: Request) => Response | Promise<Response> = (req) => app.fetch(req);
