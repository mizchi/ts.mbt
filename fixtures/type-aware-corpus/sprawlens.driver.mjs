// @sprawlens/viz — the corpus's first real APPLICATION.
//
// Every other target is a library: a package entry that exports its
// whole API, so tree-shaking has nothing to remove and every object
// shape is on the ABI. This one is `packages/viz/src/main.tsx`, which
// mounts a preact app and exports NOTHING, across 265 TypeScript files
// in four workspace packages.
//
// The observation is a FIRST PAINT. `main.tsx` ends in
// `render(<App/>, document.getElementById("root"))`, so giving it a
// document and serializing what comes out exercises the app's real code
// path — component tree, hooks, the layout engine the scene builder
// calls — and yields a string the three legs must agree on.
//
// What is NOT observed, and why:
//
//   * Nothing waits for data. 55 of the app's reads go through `fetch`,
//     and the shim below returns a promise that never settles. A
//     resolved fetch would make the observation depend on a fixture of
//     server responses, and a REJECTED one would make it depend on how
//     each effect handles failure — neither is the bundle's behaviour.
//     The synchronous first render is.
//   * No timers are advanced. `requestAnimationFrame` is a no-op, so the
//     solver loop does not run. Its output is a converged layout, which
//     is iteration-count-sensitive and would make a flake out of a
//     harness whose job is to catch mangling bugs.
//
// The digest rather than the HTML: the string is 287 bytes today and
// nothing about the test depends on its content, only on the three legs
// producing the same one. A digest also keeps a diff readable when it
// does change.
import { parseHTML } from "linkedom";

const dom = parseHTML(
  `<!doctype html><html><body><div id="root"></div></body></html>`,
);
for (const k of [
  "window",
  "document",
  "HTMLElement",
  "Element",
  "Node",
  "Text",
  "SVGElement",
  "CustomEvent",
  "Event",
  "MutationObserver",
  "getComputedStyle",
]) {
  if (dom[k] === undefined) continue;
  // `navigator` and friends are getter-only on globalThis in Node, so a
  // bare assignment throws. The app does not read them; the ones it does
  // read are set explicitly below.
  try {
    globalThis[k] = dom[k];
  } catch {
    /* read-only global */
  }
}

// The browser surface the app actually touches. Anything it reads and
// this does not provide shows up as a TypeError at import time, which is
// the right failure: a silently missing global would make the leg
// observe a different code path rather than fail.
globalThis.location = {
  href: "http://localhost/",
  search: "",
  pathname: "/",
  hash: "",
  hostname: "localhost",
  host: "localhost",
  protocol: "http:",
  origin: "http://localhost",
  port: "",
};
globalThis.history = { pushState() {}, replaceState() {}, state: null };
globalThis.window.location = globalThis.location;
globalThis.window.history = globalThis.history;
globalThis.window.innerWidth = 1280;
globalThis.window.innerHeight = 800;
globalThis.window.devicePixelRatio = 1;
globalThis.matchMedia = () => ({
  matches: false,
  media: "",
  addEventListener() {},
  removeEventListener() {},
  addListener() {},
  removeListener() {},
});
globalThis.window.matchMedia = globalThis.matchMedia;
globalThis.requestAnimationFrame = () => 0;
globalThis.cancelAnimationFrame = () => {};
globalThis.ResizeObserver = class {
  observe() {}
  unobserve() {}
  disconnect() {}
};
globalThis.EventSource = class {
  constructor() {
    this.readyState = 0;
  }
  addEventListener() {}
  close() {}
};
globalThis.fetch = () => new Promise(() => {});

// An effect that throws asynchronously is a real difference between
// legs, so count them rather than letting Node print them and move on.
const unhandled = [];
process.on("unhandledRejection", (e) =>
  unhandled.push(String((e && e.message) || e)),
);

await import("./target.mjs");
// One macrotask, so preact's effect queue drains. Not more: see above.
await new Promise((r) => setTimeout(r, 30));

const root = globalThis.document.getElementById("root");
const html = root?.innerHTML ?? "";
const digest = [...html].reduce(
  (h, c) => (h * 31 + c.charCodeAt(0)) % 1000000007,
  7,
);
const tags = [...new Set(html.match(/<([a-zA-Z][\w-]*)/g) ?? [])].sort();

const out = [];
out.push(`rootChildren: ${root?.childNodes?.length ?? -1}`);
out.push(`htmlLength: ${html.length}`);
out.push(`htmlDigest: ${digest}`);
out.push(`tags: ${tags.join(",")}`);
out.push(`unhandledRejections: ${unhandled.length}`);
console.log(out.join("\n"));
