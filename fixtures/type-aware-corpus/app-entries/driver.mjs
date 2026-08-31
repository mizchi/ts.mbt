// The one driver every app entry shares.
//
// A `*.driver.mjs` next to this directory has to be written per target
// because a package entry exports the library's whole API and there is
// no generic way to exercise it. An app entry is the opposite: it has
// already done the exercising, and its exports are deliberately scalars
// (and, where the work is async, a single `observe()` returning one).
// So the observation is just "print what the app computed", which is the
// same code for every target.
//
// Sorting the keys matters: the emitter is free to reorder an export
// clause, and an observation that changed with declaration order would
// report a mangling bug that is not there.
import * as app from "./target.mjs";

const out = {};
for (const key of Object.keys(app).sort()) {
  if (key === "observe") continue;
  out[key] = app[key];
}
if (typeof app.observe === "function") {
  out.observe = await app.observe();
}
console.log(JSON.stringify(out, null, 1));
