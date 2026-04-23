const VERSION_KEY = "version"
const BUILD_KEY = "build"

export const {
  [VERSION_KEY]: runtimeVersion,
  [BUILD_KEY]: build,
  ...restMeta
} = {
  version: "v3",
  build: 7.0,
  enabled: true,
}
