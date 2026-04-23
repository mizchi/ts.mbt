const VERSION_KEY = "version"
const BUILD_KEY = "build"

const source = {
  version: "v3",
  build: 7.0,
  enabled: true,
}

export const {
  [VERSION_KEY]: runtimeVersion,
  [BUILD_KEY]: build,
  ...restMeta
} = source
