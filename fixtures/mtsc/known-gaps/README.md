# `mtsc` known checker gaps

Each fixture is a valid TypeScript program for which `tsc --noEmit --strict`
reports the listed error, but the current `mtsc` checker emits no diagnostic.
They are an explicit backlog, not supported behavior.

| Fixture                   | TypeScript diagnostic | Missing checker capability                                            |
| ------------------------- | --------------------- | --------------------------------------------------------------------- |
| `no-implicit-any.ts`      | TS7006                | Preserve missing parameter annotations and implement `noImplicitAny`. |
| `primitive-member.ts`     | TS2551                | Model primitive prototype members without flagging valid members.     |
| `aliased-discriminant.ts` | TS2339                | Propagate narrowing through an aliased discriminant.                  |
| `overload-resolution.ts`  | TS2769                | Resolve overload candidates at a call site.                           |

The focused `mtsc` test asserts that every fixture is currently accepted. When
a checker capability is implemented, move the fixture's assertion to a normal
"reports an error" test and remove it from that known-gap corpus.

Compare the TypeScript baseline locally:

```sh
pnpm exec tsc --noEmit --strict fixtures/mtsc/known-gaps/*.ts
```

Run the focused corpus status test:

```sh
moon test src/cmd/mtsc/main_wbtest.mbt --target native \
  --filter 'mtsc known-gap corpus records current missed diagnostics'
```
