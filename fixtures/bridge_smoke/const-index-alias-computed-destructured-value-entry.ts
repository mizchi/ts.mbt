const INDEX = 0;
const NEXT_INDEX = 1;
const KEYS = {
  nested: ["version", "build"],
};

export const {
  [KEYS.nested[INDEX]]: runtimeVersion,
  [KEYS.nested[NEXT_INDEX]]: build,
  ...restMeta
} = {
  version: "v9",
  build: 13.0,
  enabled: true,
};
