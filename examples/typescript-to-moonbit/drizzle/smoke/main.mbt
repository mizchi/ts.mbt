// Drizzle ORM bridge smoke. Drizzle's TS-only `$inferSelect` cannot
// propagate through MoonBit's type system, so the schema stays
// JSValue-typed at construction; everything else flows through the
// generated bridge.
//
// `#module("...")` tells the MoonBit JS backend to emit top-level
// ESM imports. Class constructors (`QueryBuilder`, `DatabaseSync`)
// need `new`, which the bare extern import form doesn't emit, so
// they're wrapped in `helpers.mjs`.

#module("drizzle-orm/sqlite-core")
extern "js" fn sqlite_table_js(
  name : String,
  columns : @sut.JSValue,
) -> @sut.JSValue = "sqliteTable"

#module("drizzle-orm/sqlite-core")
extern "js" fn sqlite_integer_js(name : String) -> @sut.JSValue = "integer"

#module("drizzle-orm/sqlite-core")
extern "js" fn sqlite_text_js(name : String) -> @sut.JSValue = "text"

extern "js" fn integer_primary_key_js(b : @sut.JSValue) -> @sut.JSValue =
  #| (b) => b.primaryKey()

extern "js" fn text_not_null_js(b : @sut.JSValue) -> @sut.JSValue =
  #| (b) => b.notNull()

extern "js" fn make_columns_object_js(
  id : @sut.JSValue,
  name : @sut.JSValue,
  email : @sut.JSValue,
  age : @sut.JSValue,
) -> @sut.JSValue =
  #| (id, name, email, age) => ({ id, name, email, age })

#module("#drizzle-smoke/helpers")
extern "js" fn select_all_to_sql_js(t : @sut.JSValue) -> @sut.JSValue = "selectAllToSql"

#module("#drizzle-smoke/helpers")
extern "js" fn build_insert_sql_js(
  table : @sut.JSValue,
  id : Int,
  name : String,
) -> @sut.JSValue = "buildInsertSql"

#module("#drizzle-smoke/helpers")
extern "js" fn open_db_js(schema_sql : String) -> @sut.JSValue = "openDb"

extern "js" fn db_run_js(
  db : @sut.JSValue,
  sql : String,
  params : Array[@sut.JSValue],
) -> Unit =
  #| (db, sql, params) => { db.prepare(sql).run(...params); }

extern "js" fn db_all_js(
  db : @sut.JSValue,
  sql : String,
  params : Array[@sut.JSValue],
) -> @sut.JSValue =
  #| (db, sql, params) => db.prepare(sql).all(...params)

extern "js" fn js_query_sql(query : @sut.JSValue) -> String =
  #| (q) => q.sql

extern "js" fn js_query_params(query : @sut.JSValue) -> Array[@sut.JSValue] =
  #| (q) => q.params

extern "js" fn rows_length(rows : @sut.JSValue) -> Int =
  #| (r) => r.length

extern "js" fn row_str(rows : @sut.JSValue, i : Int, k : String) -> String =
  #| (r, i, k) => String(r[i][k])

extern "js" fn smoke_print_ok() -> Unit =
  #| () => console.log("ok")

fn[A, B] test_unsafe_cast(value : A) -> B = "%identity"

fn main {
  // Build a `users` schema using drizzle's runtime sqliteTable + column
  // builders. The result is structurally a drizzle Table at JS level;
  // cast it through the bridge's typed `Table[T]` for any pass-through
  // signatures that need the receiver to look like a generated Table.
  let id_col = integer_primary_key_js(sqlite_integer_js("id"))
  let name_col = text_not_null_js(sqlite_text_js("name"))
  let email_col = sqlite_text_js("email")
  let age_col = sqlite_integer_js("age")
  let columns = make_columns_object_js(id_col, name_col, email_col, age_col)
  let users = sqlite_table_js("users", columns)
  let typed_users : @sut.Table[@sut.JSValue] = test_unsafe_cast(users)
  let _ = typed_users

  // Run an INSERT + SELECT round-trip against Node 24's built-in
  // `node:sqlite` driver — no native deps required.
  let db = open_db_js(
    "create table users (id integer primary key, name text not null, email text, age integer)",
  )
  let insert = build_insert_sql_js(users, 1, "alice")
  db_run_js(db, js_query_sql(insert), js_query_params(insert))
  let select_all = select_all_to_sql_js(users)
  let rows = db_all_js(db, js_query_sql(select_all), js_query_params(select_all))
  if rows_length(rows) != 1 || row_str(rows, 0, "name") != "alice" {
    abort("drizzle smoke: expected one row with name='alice'")
  }

  // Bridge primitives are directly usable from MoonBit and keep their
  // generic parameters across the SQL composition surface.
  let name_value : @sut.Name = @sut.new_name("users")
  if name_value.get_name_value() != "users" {
    abort("drizzle smoke: Name primitive round-trip failed")
  }
  let chunk : @sut.StringChunk = @sut.new_string_chunk(
    @sut.StringValue("SELECT 1"),
  )
  if chunk.get_string_chunk_value() != ["SELECT 1"] {
    abort("drizzle smoke: StringChunk primitive round-trip failed")
  }
  let _eq : @sut.BinaryOperator = @sut.get_eq()
  let sql_value : @sut.SQL[@sut.JSValue] = chunk.get_sql()
  let _ : @sut.SQL[@sut.JSValue] = sql_value.append(sql_value)

  smoke_print_ok()
}
