extern "js" fn node_sqlite_memory_path() -> @sut.PathLike =
  #| () => ":memory:"

extern "js" fn node_sqlite_options() -> @sut.DatabaseSyncOptions =
  #| () => ({})

extern "js" fn node_sqlite_params() -> Array[@sut.SQLInputValue] =
  #| () => []

extern "js" fn node_sqlite_row_value(row : @sut.Record?) -> String =
  #| (row) => row.value

fn main {
  let db = @sut.new_database_sync(
    node_sqlite_memory_path(),
    Some(node_sqlite_options()),
  )
  if !db.get_database_sync_is_open() {
    abort("expected sqlite database to be open")
  }
  db.database_sync_exec("CREATE TABLE data (key INTEGER PRIMARY KEY, value TEXT) STRICT")
  db.database_sync_exec("INSERT INTO data (key, value) VALUES (1, 'hello')")
  db.database_sync_exec("UPDATE data SET value = 'world' WHERE key = 1")
  let stmt = db.database_sync_prepare("SELECT value FROM data WHERE key = 1", None)
  let row = stmt.statement_sync_get(node_sqlite_params())
  if node_sqlite_row_value(row) != "world" {
    abort("unexpected sqlite row value")
  }
  db.database_sync_close()
  if db.get_database_sync_is_open() {
    abort("expected sqlite database to be closed")
  }
}
