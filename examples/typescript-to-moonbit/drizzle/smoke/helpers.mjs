// ESM helper for the drizzle smoke. MoonBit's `extern "js" fn ... =
// "X"` import form generates `function f() { return X(...) }` which
// calls `X` without `new`; class constructors like `QueryBuilder` and
// `DatabaseSync` need `new`, so we wrap them here and re-export
// plain functions the bridge can call directly.
import { QueryBuilder } from "drizzle-orm/sqlite-core";
import { sql } from "drizzle-orm";
import { DatabaseSync } from "node:sqlite";

const dialectConfig = {
  escapeName: (n) => `"${n}"`,
  escapeParam: () => "?",
  escapeString: (s) => `'${s}'`,
};

export function selectAllToSql(table) {
  return new QueryBuilder().select().from(table).toSQL();
}

export function buildInsertSql(table, id, name) {
  return sql`insert into ${table} (id, name) values (${id}, ${name})`.toQuery(
    dialectConfig,
  );
}

export function openDb(schemaSql) {
  const db = new DatabaseSync(":memory:");
  db.exec(schemaSql);
  return db;
}
