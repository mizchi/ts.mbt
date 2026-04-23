import tables from "./runtime/imported-default-const-table.js";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v21",
  build: 25.0,
  enabled: false,
};
