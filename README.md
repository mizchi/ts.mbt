# mizchi/ts

Status: Experimental

MoonBit と TypeScript の間で bridge package を生成する toolchain です。TypeScript の
型定義から MoonBit bridge を生成し、MoonBit package から JavaScript runtime と
`.d.ts` を持つ npm package を生成します。生成物は再生成可能な output として扱います。

## Quick start

TypeScript dependencies を MoonBit から使う場合:

```sh
moon install mizchi/ts/cmd/ts2mbt
ts2mbt generate
```

MoonBit package を npm package にする場合:

```sh
moon install mizchi/ts/cmd/mbt2ts
cd my-moonbit-library
mbt2ts --pkg
cd npm && npm publish --access public
```

公開済み `@mizchi/ts` の type checker は global install なしで実行できます。

```sh
npx --package=@mizchi/ts mtsc --help
```

Hono を MoonBit から使う完全な手順は [Quick start](./docs/quick-start.md) を参照してください。

## Requirements

- [MoonBit toolchain](https://www.moonbitlang.com/)（`moon` が `$PATH` にあること）
- Node.js 24+
- `pnpm`（verification scripts 用）
- 任意: [`just`](https://github.com/casey/just)

## Install

```sh
moon install mizchi/ts/cmd/ts2mbt
moon install mizchi/ts/cmd/mbt2ts

# 両方を一度に install
moon install mizchi/ts/...
```

install 後は `~/.moon/bin/` を `$PATH` に追加します。source checkout から実行する
場合は `moon run src/cmd/{ts2mbt,mbt2ts} -- ...` を使います。

## Tools

| Tool     | 概要                                                           | 詳細                                 |
| -------- | -------------------------------------------------------------- | ------------------------------------ |
| `ts2mbt` | TypeScript declaration / npm package を MoonBit bridge に変換  | [`docs/ts2mbt.md`](./docs/ts2mbt.md) |
| `mbt2ts` | MoonBit package を TypeScript declaration / npm package に変換 | [`docs/mbt2ts.md`](./docs/mbt2ts.md) |
| `mtsc`   | TypeScript / TSX を型検査して JavaScript に変換                | [`docs/mtsc.md`](./docs/mtsc.md)     |

`tscheck` と `tsacc` は開発用 command であり、公開 tool には含めません。

## Generated package contract

- `ts2mbt` の output は consumer module の `internal/generated/` に置く bridge package
  です。`SCAFFOLD_DIAGNOSTICS.md` で widen / omit した surface を確認します。
- `mbt2ts --pkg` の output は `npm/` です。`moon.mod` の version と metadata を使い、
  `package.json`、`index.js`、`.d.ts`、subpath export、必要なら npm `bin` を生成します。
- どちらも output を手編集せず、入力と option から再生成してください。

詳細な type boundary、facade、runtime validation、package export、unsupported surface は
各 tool guide に記載しています。

## Diagnostics and examples

- [`docs/ts2mbt.md`](./docs/ts2mbt.md) — `SCAFFOLD_DIAGNOSTICS.md`、vendor と bridge。
- [`docs/mbt2ts.md`](./docs/mbt2ts.md) — `AUTOLINK_DIAGNOSTICS.md`、npm publish。
- [`docs/mtsc.md`](./docs/mtsc.md) — checker の CLI、ABI、既知ギャップ。
- [`examples/`](./examples/) — `just verify-examples` で検証する runnable fixture。

## Development

```sh
moon fmt
moon info
just check
just test
just verify-scaffolds
just verify-examples
```

checker の TypeScript conformance gate は次を使います。

```sh
just checker-conformance-oracle --max-fp 0 --max-legal-parsefail 1
```

軽量な conformance 集計には [tsacc guide](./docs/tsacc.md) を参照してください。

優先度と既知の制約は [checker priority](./docs/checker-priority.md) を参照してください。

## License

Apache-2.0
