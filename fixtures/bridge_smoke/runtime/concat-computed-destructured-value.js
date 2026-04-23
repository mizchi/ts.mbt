const source = {
  version: "v3",
  build: 7.0,
  enabled: true,
}

export const {
  ["ver" + "sion"]: runtimeVersion,
  ["bu" + "ild"]: build,
  ...restMeta
} = source
