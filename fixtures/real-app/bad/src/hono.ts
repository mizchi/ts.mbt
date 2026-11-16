import { Hono } from "hono";

const app = new Hono();
// `app.fetch` is the request handler.
export const bad: number = app.fetch;
