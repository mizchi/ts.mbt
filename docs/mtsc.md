# `mtsc`: TypeScript の型検査と JavaScript 変換

`mtsc` は TypeScript / TSX を JavaScript へ変換する CLI です。変換前に MoonBit
checker を実行し、診断があれば JavaScript を書き出さず non-zero で終了します。

## Run without a global install

公開済みの `@mizchi/ts` package を使う場合:

```sh
npx --package=@mizchi/ts mtsc src/index.ts --out dist/index.js
```

`npx` を実行する前に、存在する directory へ `cd` してください。削除済みの
directory を current working directory にした Node/npm は `uv_cwd` で開始前に
失敗します。

## CLI

```sh
mtsc <input.ts> [options]
```

主なオプション:

- `--out`, `-o <file.js>` — 出力先。指定しなければ stdout。
- `--bundle` — relative import をたどり単一 bundle を出力。
- `--treeshake` / `--fold` / `--minify` — bundle を最適化。
- `--dts` — `--bundle` と併用して entry の `.d.ts` を出力。
- `--sourcemap` — output の隣に v3 source map を出力。
- `--mangle`、`--mangle-properties` — internal name / property の rename。
- `--jsx-runtime automatic|classic`、`--jsx-import-source <pkg>`、`--jsx-dev` — JSX
  transform の設定。

すべてのオプションは `mtsc --help` で確認できます。

## Module graph checker ABI

Vite integration が使う公開 JavaScript ABI は `checkModuleGraph` だけです。Vite が
解決済み module と edge を渡し、`mtsc` は import / re-export を含めて checker を走らせ
ます。`checkSource` / `checkModuleSources` は実装・開発用 API であり、consumer ABI に
は含めません。

`--bundle` の CLI も同じ graph を通ります（`collect_module_graph_issues`）。file 単位
で checker を走らせると import された型がすべて未解決になり、実在するエラーを見逃す
一方で同一 shape を mismatch と誤検出します。graph 検査のために、runtime code を持た
ない type-only の relative import も loader が読み込みます。

import 解決の diagnostic は CLI では出しません。型としてのみ使う値形式の import
（`import { LocalObj } from "./types"` で `LocalObj` が type alias — TypeScript として
は合法）と、本当に存在しない export を、この層では区別できないためです。

## Ambient declaration files

entry と同じ directory の `.d.ts` を program に含めます。import も export も持たない
script 形式の宣言ファイルは ambient として扱われ、その宣言が全 module の scope に入り
ます（`declare const MyGlobal: …` を `env.d.ts` に置く慣習）。`tsc` は tsconfig の
`include` でこれを解決しますが、`mtsc` は tsconfig を読まないので directory 規約に
従います。

ambient global の property surface は host の ABI です。`--mangle-properties` は
bundle が宣言していない名前を external として扱い、その property を rename しません。

## Namespace lowering

`namespace N { … }` / `module N { … }` は runtime 値なので、TypeScript と同じ形に
lowering します。

```js
var N = N || {};
(function (N) {
  /* body */
  N.member = member;
})(N);
```

`var` + `N || {}` は declaration merging のためです。`export let` は
`Object.defineProperty` の getter で公開し、namespace 内部で再代入されても読み取りが
live であることを保ちます。lowering 対象外の形（`module "foo" { … }` のような quoted
name、`namespace A.B { … }` の dotted path、`declare global`）は従来どおり erase され
ます。ambient（`declare namespace` 等）も erase されます — 型しか宣言していないので
それが正しい挙動です。

## TypeScript compatibility snapshot

2026-07-28 に `moon run src/cmd/tsacc` で測定した pinned TypeScript conformance
subset の結果です。

| Metric             | Result                |
| ------------------ | --------------------- |
| Parsed files       | 1,189 / 1,229 (96.7%) |
| Error recall       | 719 / 815 (88.2%)     |
| TS-clean precision | 411 / 414 (99.3%)     |
| False positives    | 3                     |

これは `tsacc` の permissive checker による限定 corpus の互換性計測であり、完全な
`tsc` 互換性や `mtsc` CLI の strict mode を保証する数値ではありません。再計測方法と
対象ディレクトリは [tsacc guide](./tsacc.md) に記載しています。

構文受理はこれとは別に、TypeScript 7 conformance corpus の単一ファイルケースで測定して
います。`tscheck` と `mtsc` は同じ parser を使い、TS7 が合法とする 1,750 件を 1,750 件
受理しています（PFLEGAL: 0）。TS7 が構文エラーとする 389 件は parser が rejection します。
上表で parse できなかった 40 件も、意図的に不正な構文を含む conformance fixture であり、
有効な TypeScript 構文の未対応を意味しません。

構文受理後にも source-level の型情報を保持します。callable parameter の `?` は
`T | undefined` への意味論的な widening と区別して AST に残り、union callable の arity
判定に使われます。callable / construct signature の generic `extends` 制約も保持し、
`--dts` は `?` と制約を含む自然な宣言を再出力します。computed class method key も
`key_expr` として保持されています。

## 現在の既知ギャップ

checker は TypeScript 全仕様の代替ではありません。次の「`tsc --strict` は失敗するが、
現在の `mtsc` は診断しない」fixture を明示的な backlog として管理しています。

- implicit `any` parameter（TS7006）
- primitive prototype member（TS2551）
- aliased discriminant narrowing（TS2339）
- overload resolution（TS2769）

ソース・TypeScript baseline・更新ルールは
[`fixtures/mtsc/known-gaps`](../fixtures/mtsc/known-gaps/README.md) を参照してください。
対応時は fixture を通常の diagnostic test へ移します。
