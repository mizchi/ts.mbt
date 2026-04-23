import tables from "./imported-iife-reassigned-let-table.js";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v29",
  build: 33.0,
  enabled: false,
};
