import {
  INDEXES,
  KEYS,
} from "./imported-mixed-barrel-const-table.js";

export const {
  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
  [KEYS.nested[INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v17",
  build: 21.0,
  enabled: true,
};
