const KEYS = {
  version: "version",
  build: "build",
};

export const {
  [KEYS.version]: runtimeVersion,
  [KEYS["build"]]: build,
  ...restMeta
} = {
  version: "v5",
  build: 9.0,
  enabled: true,
};
