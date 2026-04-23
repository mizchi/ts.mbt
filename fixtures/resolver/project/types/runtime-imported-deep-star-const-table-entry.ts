import {
  INDEXES,
  KEYS,
} from "./runtime-imported-deep-star-const-table.ts";

export const {
  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
  [KEYS.nested[INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v16",
  build: 20.0,
  enabled: false,
};
