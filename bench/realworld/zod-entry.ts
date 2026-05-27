import { z } from "zod";

const schema = z.object({
  name: z.string().min(1),
  age: z.number().int().nonnegative(),
  tags: z.array(z.string()).default([]),
});

const ok = schema.safeParse({ name: "ada", age: 36, tags: ["math"] });
const ng = schema.safeParse({ name: "", age: -1 });

if (ok.success && !ng.success) {
  console.log("zod ok:", ok.data.name, ok.data.age, ok.data.tags.length);
} else {
  console.log("zod fail");
}
