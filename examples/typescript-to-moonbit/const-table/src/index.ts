import { INDEXES, KEYS } from "./table";

export const {
  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
  [KEYS.nested[INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v12",
  build: 16.0,
  enabled: false,
};
