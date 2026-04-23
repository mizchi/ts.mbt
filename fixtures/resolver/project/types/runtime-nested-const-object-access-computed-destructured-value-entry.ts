const KEYS = {
  nested: {
    version: "version",
    build: "build",
  },
};

export const {
  [KEYS.nested.version]: runtimeVersion,
  [KEYS.nested["build"]]: build,
  ...restMeta
} = {
  version: "v6",
  build: 10.0,
  enabled: false,
};
