name = "mizchi/ts"

version = "0.4.0"

import {
  "moonbitlang/async@0.20.2",
  "mizchi/x@0.2.2",
}

readme = "README.md"

repository = "https://github.com/mizchi/ts.mbt"

license = "Apache-2.0"

keywords = [ "typescript", "javascript", "moonbit", "bridge", "ffi", "d.ts" ]

description = "TypeScript <-> MoonBit bridge generator"

preferred_target = "native"

source = "src"

options(
  exclude: [ "fixtures", "typescript" ],
)
