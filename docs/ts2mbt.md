# `ts2mbt`: TypeScript を MoonBit から使う

`ts2mbt` は TypeScript の宣言またはソースを読み、MoonBit から JavaScript
ライブラリを呼ぶための bridge package を生成します。生成物は再生成可能な出力です。
手編集せず、入力の型定義または生成オプションを変更して再実行してください。

## Install

```sh
moon install mizchi/ts/cmd/ts2mbt
```

開発中はリポジトリから `moon run src/cmd/ts2mbt -- ...` として実行できます。

## 最短の使い方

1つの npm パッケージを MoonBit module 内へ vendor します。

```sh
ts2mbt vendor hono
```

`package.json` の `dependencies` と `devDependencies` をまとめて処理するには:

```sh
ts2mbt generate
```

出力先の既定値は `<moon source>/internal/generated/<package>/` です。各 bridge
には `bridge.mbti`、`bridge.mbt`、`bridge.js`、`moon.pkg`、`package.json`、
`SCAFFOLD_DIAGNOSTICS.md` が入ります。

生成後、案内された `@tsmbt-bridge/<name>` の `file:` dependency を consumer の
`package.json` に追加して `pnpm install` または `npm install` を実行します。次に
consumer の `moon.pkg` から生成 package を import します。

```moonbit
import {
  "yourname/yourmod/internal/generated/hono" @hono,
}
```

完全な Hono の例は [Quick start](./quick-start.md) を参照してください。

## Project-oriented input

`--input` は宣言ファイル、TypeScript source、または npm package specifier を受けます。

```sh
# Installed package の型を bridge package にする
ts2mbt --input neverthrow --out dist

# ファイル入力では runtime module specifier も与える
ts2mbt --input path/to/entry.d.ts --module-spec /runtime/module.js --out dist
```

`--diagnostics <path>` は `SCAFFOLD_DIAGNOSTICS.md` の出力先を変更します。
`--strict` は unsupported export、unsafe fallback、未予算の `JSValue` が残る場合に
失敗させます。通常モードでは生成可能な package を出力し、判断理由を diagnostics に
残します。

## Low-level commands

高水準の `--input` / `vendor` / `generate` を通常は使います。個別の生成段階が必要な
tooling には以下もあります。

```sh
ts2mbt scaffold path/to/entry.d.ts /runtime/module.js out/moonbit-pkg
ts2mbt package path/to/entry.d.ts /runtime/module.js out/moonbit-pkg
# runtime validator を public API に追加する opt-in variant
ts2mbt package-validated path/to/entry.d.ts /runtime/module.js out/moonbit-pkg
ts2mbt bridge path/to/entry.d.ts /runtime/module.js
ts2mbt ffi path/to/entry.d.ts /runtime/module.js
ts2mbt decl path/to/entry.d.ts
```

`vendor` は `--module-spec <specifier>` と `--out <dir>` を、`generate` は
`--package-json <path>` と `--out <dir>` を受けます。完全なオプションは
`ts2mbt --help` を参照してください。

## 型境界と diagnostics

primitive、array、optional、literal union、object option bag、および多くの一般的な
utility type は MoonBit の型へ写されます。複雑な `any` / `unknown`、conditional /
mapped type、overload、function callback、異種 tuple、namespace/value merge は
`JSValue` へ widen されることがあります。

`SCAFFOLD_DIAGNOSTICS.md` が唯一の判断記録です。頻繁に使う widened surface は、
consumer 側の小さな `extern "js"` shim で補うのが推奨されます。実 package の
fallback budget と品質確認は `just bridge-quality` および
`just verify-realworld-typescript` を使います。

## Generated output の扱い

`internal/generated/` は cache です。`ts2mbt generate` / `vendor` は `.gitignore`
と `AGENTS.md` を置き、生成ファイルには `AUTO-GENERATED` ヘッダーを付けます。
upstream typings が変わったら同じコマンドを再実行してください。
