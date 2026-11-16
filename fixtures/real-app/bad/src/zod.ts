import { z } from "zod";

const s = z.string();
// `parse` on a string schema returns a string.
export const bad: number = s.parse("x");
