import tables from "./imported-function-iife-index-mutated-let-table.js";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v31",
  build: 35.0,
  enabled: false,
};
