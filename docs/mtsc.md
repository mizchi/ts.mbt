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
ます。CLI の単一 source checker と `checkSource` / `checkModuleSources` は実装・開発用
API であり、consumer ABI には含めません。

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
