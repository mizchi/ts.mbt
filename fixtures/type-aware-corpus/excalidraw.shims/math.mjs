// `roughjs/bin/math` — the seeded PRNG.
//
// `bin/math.js` is the one file in roughjs's `bin/` tree with no
// relative imports, so the real module loads once the extension is
// supplied.
export { Random, randomSeed } from "roughjs/bin/math.js";
