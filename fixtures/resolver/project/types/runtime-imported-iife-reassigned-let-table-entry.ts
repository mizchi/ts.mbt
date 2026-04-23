import tables from "./runtime-imported-iife-reassigned-let-table.ts";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v29",
  build: 33.0,
  enabled: false,
};
