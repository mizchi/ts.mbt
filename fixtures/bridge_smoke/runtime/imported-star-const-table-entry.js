import {
  INDEXES,
  KEYS,
} from "./imported-star-const-table.js";

export const {
  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
  [KEYS.nested[INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v15",
  build: 19.0,
  enabled: true,
};
