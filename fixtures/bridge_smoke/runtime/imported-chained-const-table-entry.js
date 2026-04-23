import {
  INDEXES,
  KEYS,
} from "./imported-chained-const-table.js";

export const {
  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
  [KEYS.nested[INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v14",
  build: 18.0,
  enabled: false,
};
