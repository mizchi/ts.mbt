import {
  INDEXES,
  KEYS,
} from "./runtime-imported-star-const-table.ts";

export const {
  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
  [KEYS.nested[INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v15",
  build: 19.0,
  enabled: true,
};
