export const {
  [true]: truthy,
  [null]: nilValue,
  [-1]: negative,
  [1n]: bigintValue,
  ...restMeta
} = {
  "true": "yes",
  "null": 7.0,
  "-1": false,
  "1": "one",
  enabled: true,
}
