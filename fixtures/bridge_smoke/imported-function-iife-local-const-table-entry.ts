import tables from "./runtime/imported-function-iife-local-const-table.js";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v26",
  build: 30.0,
  enabled: true,
};
