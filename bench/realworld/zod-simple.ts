import { z } from "zod";

const schema = z.string().min(2);
const ok = schema.safeParse("hello");
const ng = schema.safeParse("");

if (ok.success && !ng.success) {
  console.log("zod simple ok");
} else {
  console.log("zod simple fail:", ok.success, ng.success);
}
