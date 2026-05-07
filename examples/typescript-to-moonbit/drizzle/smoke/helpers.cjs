// CommonJS helper for the drizzle smoke. MoonBit's `extern "js" fn ... =
// "X"` import form generates `function f() { return X(...) }` which calls
// `X` without `new`; class constructors like `QueryBuilder` and
// `DatabaseSync` need `new`, so we wrap them here and call from extern
// bodies via `require("./helpers.cjs")`.
//
// drizzle's `sql` template tag is also stateful (carries an internal
// chunk array), so the simplest way to drive it from MoonBit is to
// build the prepared `Query` (`{ sql, params }`) here and hand the
// raw fields back.

const { QueryBuilder } = require("drizzle-orm/sqlite-core");
const { sql } = require("drizzle-orm");
const { DatabaseSync } = require("node:sqlite");

const dialectConfig = {
  escapeName: (n) => `"${n}"`,
  escapeParam: () => "?",
  escapeString: (s) => `'${s}'`,
};

function newQueryBuilderSelectAll(table) {
  return new QueryBuilder().select().from(table).toSQL();
}

function buildInsertSql(table, id, name) {
  return sql`insert into ${table} (id, name) values (${id}, ${name})`.toQuery(
    dialectConfig,
  );
}

function openDb(schemaSql) {
  const db = new DatabaseSync(":memory:");
  db.exec(schemaSql);
  return db;
}

module.exports = { newQueryBuilderSelectAll, buildInsertSql, openDb };
