declare module "node:sqlite" {
  interface DatabaseSyncOptions {
    open?: boolean;
  }

  class DatabaseSync {
    constructor(path: string, options?: DatabaseSyncOptions);
    exec(sql: string): void;
    prepare(sql: string): StatementSync;
  }

  class StatementSync {
    private constructor();
    get(): Record<string, string> | undefined;
  }

  const SQLITE_OK: number;
}
