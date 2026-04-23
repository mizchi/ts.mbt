import tables from "./runtime/imported-inline-default-const-table.js";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v22",
  build: 26.0,
  enabled: true,
};
