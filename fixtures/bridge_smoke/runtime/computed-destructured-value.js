const source = {
  version: "v3",
  build: 7.0,
  enabled: true,
}

export const { ["version"]: runtimeVersion, ["build"]: build, ...restMeta } = source
