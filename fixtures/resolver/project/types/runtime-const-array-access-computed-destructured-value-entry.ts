const KEYS = ["version", "build"];

export const {
  [KEYS[0]]: runtimeVersion,
  [KEYS[1]]: build,
  ...restMeta
} = {
  version: "v7",
  build: 11.0,
  enabled: true,
};
