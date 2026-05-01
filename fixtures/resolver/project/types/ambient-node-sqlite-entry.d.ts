declare module "node:sqlite" {
  type SQLInputValue = null | number | bigint | string;

  interface DatabaseSyncOptions {
    open?: boolean;
  }

  interface StatementResultingChanges {
    changes: number | bigint;
    lastInsertRowid: number | bigint;
  }

  class DatabaseSync {
    constructor(path: string, options?: DatabaseSyncOptions);
    exec(sql: string): void;
    prepare(sql: string): StatementSync;
  }

  class StatementSync {
    private constructor();
    get(): Record<string, string> | undefined;
    run(...anonymousParameters: SQLInputValue[]): StatementResultingChanges;
  }

  const SQLITE_OK: number;
}
