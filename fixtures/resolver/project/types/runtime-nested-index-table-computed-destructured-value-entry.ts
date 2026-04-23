const MATRIX = [[0, 1]];
const KEYS = {
  nested: ["version", "build"],
};

export const {
  [KEYS.nested[MATRIX[0][0]]]: runtimeVersion,
  [KEYS.nested[MATRIX[0][1]]]: build,
  ...restMeta
} = {
  version: "v11",
  build: 15.0,
  enabled: true,
};
