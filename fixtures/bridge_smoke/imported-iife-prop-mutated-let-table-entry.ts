import tables from "./runtime/imported-iife-prop-mutated-let-table.js";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v30",
  build: 34.0,
  enabled: true,
};
