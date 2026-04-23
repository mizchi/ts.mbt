const { version: VERSION_KEY, build: BUILD_KEY } = {
  version: "version",
  build: "build",
};

export const { [VERSION_KEY]: runtimeVersion, [BUILD_KEY]: build, ...restMeta } = {
  version: "v4",
  build: 8.0,
  enabled: false,
};
