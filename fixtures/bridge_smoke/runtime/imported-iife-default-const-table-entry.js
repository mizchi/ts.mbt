import tables from "./imported-iife-default-const-table.js";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v24",
  build: 28.0,
  enabled: true,
};
