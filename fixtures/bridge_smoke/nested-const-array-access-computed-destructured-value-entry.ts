const KEYS = {
  nested: ["version", "build"],
};

export const {
  [KEYS.nested[0]]: runtimeVersion,
  [KEYS.nested[1]]: build,
  ...restMeta
} = {
  version: "v8",
  build: 12.0,
  enabled: false,
};
