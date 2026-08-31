// `import type`, not a value-form import of a type. TypeScript accepts
// the value form and mtsc erases it, but Node's transform mode cannot —
// it keeps the import, and `./types` has no runtime export — which left
// this whole case with no reference leg and therefore no oracle beyond
// comparing mtsc against itself. The erasure of the value form is a
// compilation question, so it lives in `bundle_wbtest.mbt` instead.
import type { LocalObj } from "./types";

const createLocalObj = (): LocalObj => {
  return {
    local: 1,
  };
};

export function runLocal() {
  const localObj = createLocalObj();
  console.log(localObj.local);
}
