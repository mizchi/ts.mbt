import {
  INDEXES,
  KEYS,
} from "./runtime/imported-reexported-const-table.js";

export const {
  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
  [KEYS.nested[INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v13",
  build: 17.0,
  enabled: true,
};
