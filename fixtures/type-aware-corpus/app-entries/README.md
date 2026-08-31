# app entries

`node scripts/measure_type_aware.mjs --app` compiles these instead of
each library's package entry. One `*.app.ts` per target, plus the
shared `driver.mjs` that prints what the app computed.

## Why a second entry at all

The corpus's default rows compile a library's *package* entry — the
barrel that exports its whole public API. Two of the questions this
harness asks are unanswerable in that shape:

- **Tree-shaking has nothing to remove.** A barrel's exports are all
  live by definition.
- **Every property name is on the API boundary.** A library's object
  shapes *are* its wire format, so the mangler is right to reserve them.
  The reserved-set census on a package entry therefore says nothing
  about what the pass could do for a consumer.

An application is the other case: it uses a slice of the library, and
its own object shapes are private. These entries are that case.

## The rule about where the usage comes from

**The usage in each app entry is copied from that library's own
README.** Not adapted, not improved — where the README's example throws
or is async it is wrapped, and nothing else changes. Two exceptions,
both recorded in the file's own header: `immer.app.ts` takes its example
from immer's docs site, because its readme carries no TypeScript block
at all; and `excalidraw.app.ts` has no README to copy from
(`packages/element` is an internal workspace package), so it is lifted
from `excalidraw.driver.mjs`, with every call written out statically
instead of reached through `El[name]`.

The rule exists because an entry *I* wrote would be an entry written to
make the passes fire. A harness that flatters the compiler is worse than
no harness — it produces a number nobody can act on, which is the
failure mode `docs/type-aware-measurement.md` keeps running into from
other directions.

## What an app entry has to look like

- **Import the library by a relative path into its sources**
  (`./src/index.ts`). The fixture is staged into the checkout root, so
  the path resolves against the library's own TypeScript. A bare
  specifier would resolve through `node_modules` to the published `.js`,
  which is the measurement this harness exists to avoid.
- **Export only scalars** (or strings built from them). That is what
  makes the app's own property names internal, which is the whole point
  of the row — an exported object would put them back on the boundary.
- **Export nothing whose value moves between runs.** Same rule as the
  drivers: pin or drop anything drawn from a PRNG or the clock, because
  a value that is not a function of the input cannot witness a mangling
  bug, only produce a false `BROKEN`.
- **Where the work is async, export one `observe(): Promise<string>`.**
  The shared driver awaits it. `hono.app.ts` is the only one so far.

## `driver.mjs`

One driver serves every app entry: it imports `./target.mjs`, sorts the
export names (the emitter may reorder an export clause), calls
`observe()` if there is one, and prints JSON.

A target can name its own with `appDriver` when the bundle needs
something set before it is evaluated. `excalidraw.driver.mjs` is the
only case — its sources read `import.meta.env`, which the harness
rewrites to a global, so the import has to be dynamic.

## Adding one

1. Write `<name>.app.ts` here, importing the library by relative path.
2. Add `appEntry: "<name>.app.ts"` to that target's row in `CORPUS`.
3. `node scripts/measure_type_aware.mjs --app --only <name>` — all three
   legs must print the same observation.
4. `node scripts/measure_type_aware.mjs --app --update` to record
   `../expected.app.json`.
