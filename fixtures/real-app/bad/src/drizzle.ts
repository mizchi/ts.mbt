import { sql } from "drizzle-orm";

// `sql` is a tagged-template function, not a number.
export const bad: number = sql;
