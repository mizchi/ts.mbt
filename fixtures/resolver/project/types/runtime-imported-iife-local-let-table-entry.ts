import tables from "./runtime-imported-iife-local-let-table.ts";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v27",
  build: 31.0,
  enabled: false,
};
