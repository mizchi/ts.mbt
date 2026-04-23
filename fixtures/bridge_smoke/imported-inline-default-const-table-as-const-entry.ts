import tables from "./runtime/imported-inline-default-const-table-as-const.js";

export const {
  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v23",
  build: 27.0,
  enabled: false,
};
