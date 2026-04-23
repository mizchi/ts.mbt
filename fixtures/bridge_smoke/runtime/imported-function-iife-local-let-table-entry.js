import tables from "./imported-function-iife-local-let-table.js";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v28",
  build: 32.0,
  enabled: true,
};
