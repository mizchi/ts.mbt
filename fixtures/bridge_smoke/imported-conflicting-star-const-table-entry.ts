import {
  INDEXES,
  KEYS,
} from "./runtime/imported-conflicting-star-const-table.js";

export const {
  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
  [KEYS.nested[INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v18",
  build: 22.0,
  enabled: false,
};
