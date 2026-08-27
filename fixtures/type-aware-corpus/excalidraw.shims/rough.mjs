// `roughjs/bin/rough` — the default export, `{ canvas, svg, generator,
// newSeed }`. This IS roughjs's own default export, taken from the
// rollup build it publishes as `module`; `bin/rough.js` is unloadable in
// Node (see README.md).
export { default } from "roughjs/bundled/rough.esm.js";
