const source = {
  undefined: "void",
  "-1": 9.0,
  enabled: true,
}

export const {
  [void 0]: undefinedValue,
  [-1n]: negativeBigint,
  ...restMeta
} = source
