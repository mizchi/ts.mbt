const INDEXES = [0, 1];
const KEYS = {
  nested: ["version", "build"],
};

export const {
  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
  [KEYS.nested[INDEXES[1]]]: build,
  ...restMeta
} = {
  version: "v10",
  build: 14.0,
  enabled: false,
};
