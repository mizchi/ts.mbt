import { sql, eq, and } from "drizzle-orm";
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";
export const users = sqliteTable("users", { id: integer("id").primaryKey(), name: text("name").notNull() });
export const where = and(eq(users.id, 1), eq(users.name, "a"));
export const raw = sql`select 1`;
