# Quick start

End-to-end walkthrough: vendor TypeScript libraries from npm into a
fresh MoonBit module, build a tiny Hono server, and serve real HTTP
traffic. Mirrors the smoke under
[`examples/typescript-to-moonbit/hono-server`](../examples/typescript-to-moonbit/hono-server/).

## Prerequisites

- [`moon`](https://www.moonbitlang.com/) on `$PATH` (any toolchain
  shipped after 2026-04-09 works).
- Node.js 24+ and `pnpm`.

## 1. Install the CLIs

```bash
moon install mizchi/ts/cmd/ts2mbt   # TypeScript -> MoonBit
moon install mizchi/ts/cmd/mbt2ts   # MoonBit -> TypeScript (optional)
```

Verify:

```bash
ts2mbt --version
# ts2mbt 0.4.0 (mizchi/ts)
```

`~/.moon/bin` must be on `$PATH`.

## 2. Scaffold a new MoonBit module

```bash
mkdir -p ~/projects/hono-app && cd $_
moon new --user yourname --name app
```

Make it a JS-target module so you can `moon run` straight to Node:

```bash
cat > moon.mod.json <<'EOF'
{
  "name": "yourname/app",
  "version": "0.1.0",
  "preferred-target": "js"
}
EOF
```

The default `moon new` template creates `cmd/main/` for the entry
point and a `app.mbt` library file at the module root. You can keep
that layout or carve your own.

## 3. Add the npm dependencies

```bash
pnpm init
pnpm add hono @hono/node-server
```

## 4. Generate the bridges

```bash
ts2mbt generate
```

Output:

```
vendor: @hono/node-server -> internal/generated/hono__node_server (#module "@tsmbt-bridge/hono__node_server")
vendor: hono              -> internal/generated/hono              (#module "@tsmbt-bridge/hono")

generate summary: 2 ok, 0 failed (of 2)

Add to your consumer moon.pkg import block:
  "yourname/app/internal/generated/hono__node_server" @hono__node_server,
  "yourname/app/internal/generated/hono" @hono,

Add to your consumer package.json (`dependencies` field):
  "dependencies": {
    "@tsmbt-bridge/hono": "file:./internal/generated/hono",
    "@tsmbt-bridge/hono__node_server": "file:./internal/generated/hono__node_server"
  }
Then run `pnpm install` / `npm install` to materialize the link.
```

## 5. Wire the `file:` deps and install

Each generated bridge is a real npm package under
`@tsmbt-bridge/<name>`. List them as `file:` dependencies so
`pnpm install` / `npm install` materialize them under
`node_modules/@tsmbt-bridge/`:

```json
{
  "name": "app",
  "type": "module",
  "dependencies": {
    "hono": "^4.12.0",
    "@hono/node-server": "^2.0.0",
    "@tsmbt-bridge/hono": "file:./internal/generated/hono",
    "@tsmbt-bridge/hono__node_server": "file:./internal/generated/hono__node_server"
  }
}
```

Then:

```bash
pnpm install
```

`pnpm install` survives every regeneration, and `moon test --target js`
can resolve `require("@tsmbt-bridge/<name>")` because the bridge
sits at a stable `node_modules/` path rather than behind a
`package.json#imports` mapping that the test scaffold's intermediate
`package.json` would shadow.

Layout under your module:

```
internal/
└── generated/
    ├── .gitignore             # ignores the whole tree by default
    ├── AGENTS.md              # "do not hand-edit" guardrail
    ├── hono/
    │   ├── bridge.mbti        # public surface
    │   ├── bridge.mbt
    │   ├── bridge.js
    │   ├── moon.pkg
    │   ├── package.json
    │   └── SCAFFOLD_DIAGNOSTICS.md
    └── hono__node_server/
        └── ... (same shape)
```

Treat `internal/generated/` as a regenerable cache. Re-run
`ts2mbt generate` whenever you bump npm versions or add new
dependencies.

## 6. Add the bridge imports to your `moon.pkg` files

Root `moon.pkg` (next to `app.mbt`):

```
import {
  "yourname/app/internal/generated/hono" @hono,
  "yourname/app/internal/generated/hono__node_server" @node_server,
}
```

`cmd/main/moon.pkg`:

```
import {
  "yourname/app" @lib,
}

options(
  "is-main": true,
)
```

## 7. Library code

`app.mbt`:

```moonbit
// Build a Hono app and serve it via @hono/node-server.

///|
pub fn build_app() -> @hono.Hono {
  let app = @hono.new_hono(None)
  let _ = app.get("/", fn(c) { c.text("hello from moonbit + hono", None, None) })
  let _ = app.get("/ping", fn(c) { c.text("pong", None, None) })
  app
}

///|
pub fn serve(app : @hono.Hono, port : Int) -> Unit {
  let opts = make_serve_options(app, port)
  let _ = @node_server.serve(
    opts,
    Some(fn(_info) { println("listening on http://localhost:\{port}") }),
  )

}

///|
extern "js" fn make_serve_options(
  app : @hono.Hono,
  port : Int,
) -> @node_server.Options =
  #| (app, port) => ({ fetch: app.fetch.bind(app), port })
```

A few notes:

- Class methods on bridge types use their natural TypeScript name —
  `app.get(...)`, `c.text(...)`. Reserved words get a trailing
  underscore (`match` → `match_`).
- `@node_server.Options` is opaque, so the small `extern "js"`
  factory builds the underlying `{ fetch, port }` object. Hono's
  `app.fetch` is a method on the Hono instance, hence the `.bind`.
- Anything the generator widened to `JSValue` is listed in the
  bridge's `SCAFFOLD_DIAGNOSTICS.md`. For surfaces you reach for
  often, hand-rolled `extern "js"` shims (like
  `make_serve_options`) are the escape hatch.

## 8. Entry point

`cmd/main/main.mbt`:

```moonbit
fn main {
  let app = @lib.build_app()
  @lib.serve(app, 3000)
}
```

## 9. Run it

```bash
moon run cmd/main
# listening on http://localhost:3000
```

In another terminal:

```bash
curl http://localhost:3000/
# hello from moonbit + hono

curl http://localhost:3000/ping
# pong

curl -i http://localhost:3000/missing
# HTTP/1.1 404 Not Found
# ...
```

## Re-generation

Whenever the upstream typings change, just rerun `ts2mbt generate`.
The `.gitignore` and `AGENTS.md` markers are idempotently
overwritten, so the regen surface stays the same shape every time.
For one-off testing of a single package:

```bash
ts2mbt vendor hono
```

## Where to go next

- `bridge.mbti` is the source of truth for the public surface of
  any vendored package — `grep` it before reaching for
  `extern "js"`.
- `SCAFFOLD_DIAGNOSTICS.md` lists what was widened to `JSValue` and
  why; it's the map for "where do I still need a hand-rolled shim".
- The combined hono + node-server example at
  [`examples/typescript-to-moonbit/hono-server`](../examples/typescript-to-moonbit/hono-server/)
  drives the same flow under `just verify-examples`.
