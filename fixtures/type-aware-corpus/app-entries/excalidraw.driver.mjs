// The one app entry that cannot use the shared driver.
//
// Excalidraw's sources read `import.meta.env.MODE` / `.DEV` / `.PROD`,
// which vite substitutes at build time; the harness rewrites those reads
// to the global below (`execReplace` in
// `scripts/measure_type_aware.mjs`). All six reads are inside function
// bodies, so the app entry's own top level could in principle set it —
// but that would hard-code the harness's rewrite target into a fixture.
// Setting it here, before a dynamic import, keeps the fixture about the
// library and the harness detail in the harness.
globalThis.__EXCALIDRAW_ENV__ = { MODE: "production", DEV: false, PROD: true };

const app = await import("./target.mjs");

const out = {};
for (const key of Object.keys(app).sort()) {
  if (key === "observe") continue;
  out[key] = app[key];
}
if (typeof app.observe === "function") {
  out.observe = await app.observe();
}
console.log(JSON.stringify(out, null, 1));
