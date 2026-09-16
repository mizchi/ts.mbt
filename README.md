# mizchi/ts

Status: Experimental

MoonBit と TypeScript の間で bridge package を生成する toolchain です。TypeScript の
型定義から MoonBit bridge を生成し、MoonBit package から JavaScript runtime と
`.d.ts` を持つ npm package を生成します。生成物は再生成可能な output として扱います。

## Quick start

TypeScript dependencies を MoonBit から使う場合:

```sh
moon install mizchi/ts/cmd/mtsc
mtsc bridge generate
```

MoonBit package を npm package にする場合:

```sh
moon install mizchi/ts/cmd/mtsc
cd my-moonbit-library
mtsc pkg npm
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
moon install mizchi/ts/cmd/mtsc
```

install 後は `~/.moon/bin/` を `$PATH` に追加します。source checkout から実行する
場合は `moon run src/cmd/mtsc -- ...` を使います。

## Tools

binary は `mtsc` 1 つだけです。TypeScript の compile は default の位置引数で、
それ以外の機能は verb で分かれています。

| Command            | 概要                                                           | 詳細                                 |
| ------------------ | -------------------------------------------------------------- | ------------------------------------ |
| `mtsc [files...]`  | TypeScript / TSX を型検査して JavaScript に変換                | [`docs/mtsc.md`](./docs/mtsc.md)     |
| `mtsc bridge`      | TypeScript declaration / npm package を MoonBit bridge に変換  | [`docs/ts2mbt.md`](./docs/ts2mbt.md) |
| `mtsc pkg`         | MoonBit package を TypeScript declaration / npm package に変換 | [`docs/mbt2ts.md`](./docs/mbt2ts.md) |
| `mtsc check`       | 1 file の checker 診断（開発用）                               | [`docs/mtsc.md`](./docs/mtsc.md)     |
| `mtsc conformance` | TypeScript conformance corpus に対する精度集計（開発用）       | [`docs/tsacc.md`](./docs/tsacc.md)   |

compile mode の command line は `tsc` / `tsgo` の **superset** です。`tsc` の
option 名はそのまま通り、`-p` / `tsconfig.json` の読み取り、`--noEmit`、
`--watch`、`tsc` 準拠の exit code に対応します。mtsc が動作を持たない option
（`--target`、`--module`、`--strict` など）は受け取ったうえで「honour していない」
と 1 行報告します。黙って無視はしません。

`ts2mbt` / `mbt2ts` / `tscheck` / `tsacc` の 4 binary は `mtsc` に集約されました。
対応は `ts2mbt X` → `mtsc bridge X`、`mbt2ts X` → `mtsc pkg X`、
`mbt2ts --pkg` → `mtsc pkg npm`、`tscheck` → `mtsc check`、
`tsacc` → `mtsc conformance` です。

## Generated package contract

- `mtsc bridge` の output は consumer module の `internal/generated/` に置く bridge package
  です。`SCAFFOLD_DIAGNOSTICS.md` で widen / omit した surface を確認します。
- `mtsc pkg npm` の output は `npm/` です。`moon.mod` の version と metadata を使い、
  `package.json`、`index.js`、`.d.ts`、subpath export、必要なら npm `bin` を生成します。
- どちらも output を手編集せず、入力と option から再生成してください。

詳細な type boundary、facade、runtime validation、package export、unsupported surface は
各 tool guide に記載しています。

## Diagnostics and examples

- [`docs/ts2mbt.md`](./docs/ts2mbt.md) — `mtsc bridge`: `SCAFFOLD_DIAGNOSTICS.md`、vendor と bridge。
- [`docs/mbt2ts.md`](./docs/mbt2ts.md) — `mtsc pkg`: `AUTOLINK_DIAGNOSTICS.md`、npm publish。
- [`docs/mtsc.md`](./docs/mtsc.md) — checker の CLI、ABI、既知ギャップ。
- [`docs/mangle-safety.md`](./docs/mangle-safety.md) — 型追跡による安全な property mangling と、その検証 corpus。
- [`docs/minify-patterns.md`](./docs/minify-patterns.md) — minify / mangle パターンの一覧と、各パターンの証明義務。
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

軽量な conformance 集計には [`mtsc conformance` guide](./docs/tsacc.md) を参照してください。

優先度と既知の制約は [checker priority](./docs/checker-priority.md) を参照してください。

## License

Apache-2.0
