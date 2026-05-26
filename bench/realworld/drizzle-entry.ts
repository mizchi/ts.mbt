import { sql } from "drizzle-orm";

const q = sql`select ${1} + ${2}`;
console.log("drizzle ok:", q.queryChunks.length > 0);
