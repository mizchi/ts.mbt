# Why Excalidraw's bundle needs three shim modules to run under Node

Excalidraw imports roughjs by deep path:

    import rough from "roughjs/bin/rough";
    import { RoughGenerator } from "roughjs/bin/generator";
    import { Random } from "roughjs/bin/math";

Node cannot load any of those, and the reason has nothing to do with
this project:

* The specifiers carry no extension, and roughjs publishes no `exports`
  map, so Node's ESM resolver rejects them outright
  (`ERR_MODULE_NOT_FOUND`, "Did you mean to import
  roughjs/bin/math.js?"). Appending `.js` is not enough —
* `bin/rough.js` itself does `import { RoughCanvas } from './canvas'`,
  and `bin/generator.js` reaches `bin/fillers/filler.js`, which imports
  `./hachure-filler`. The whole `bin/` tree is extension-less ESM,
  which is to say it is a **bundler-only** build. Excalidraw is built
  with vite, whose resolver fills in the extensions; Node's does not.

So there is no arrangement of `node_modules` under which
`import "roughjs/bin/rough"` loads in Node. The shims here fill in what
a bundler's resolver would have, and each one hands back the **real**
roughjs code — reached through `bundled/rough.esm.js`, the rollup build
that roughjs itself publishes as its `module` entry, which is what vite
resolves for the browser anyway.

The one thing not reachable that way is `RoughCanvas` / `RoughSVG`.
Both need a DOM, so nothing in a Node driver could have used them.

`measure_type_aware.mjs` rewrites the three specifiers in the copy of
the bundle it EXECUTES, identically for every leg. The measured byte
counts come from the unmodified leg outputs.
