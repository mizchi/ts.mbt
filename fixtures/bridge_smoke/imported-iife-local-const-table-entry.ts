import tables from "./runtime/imported-iife-local-const-table.js";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v25",
  build: 29.0,
  enabled: false,
};
