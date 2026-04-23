import * as tables from "./runtime-imported-const-table.ts";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v20",
  build: 24.0,
  enabled: true,
};
