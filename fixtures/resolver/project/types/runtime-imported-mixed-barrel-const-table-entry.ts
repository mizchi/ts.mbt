import {
  INDEXES,
  KEYS,
} from "./runtime-imported-mixed-barrel-const-table.ts";

export const {
  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
  [KEYS.nested[INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v17",
  build: 21.0,
  enabled: true,
};
