import { z } from "zod";

const Schema = z.object({
  name: z.string(),
  age: z.number().int().positive(),
});

const parsed = Schema.safeParse({ name: "Alice", age: 30 });
console.log("zod parse ok:", parsed.success, parsed.success ? parsed.data : null);
