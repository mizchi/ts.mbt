# `mbt2ts`: MoonBit package を TypeScript / npm として公開する

`mbt2ts` は MoonBit の `pkg.generated.mbti` と JavaScript build output から、
`.d.ts` と runtime JS を持つ TypeScript package を生成します。生成物は毎回
再生成する publish artifact です。

## Install

```sh
moon install mizchi/ts/cmd/mbt2ts
```

開発中は `moon run src/cmd/mbt2ts -- ...` を使えます。

## npm package を生成する: `--pkg`

MoonBit module root で実行します。

```sh
mbt2ts --pkg
cd npm
npm pack --dry-run
npm publish --access public
```

`--pkg` は `moon info` を実行し、`moon.mod` の version、description、license、
repository を manifest にコピーします。facade glue を生成して `moon build --target js`
で build し、`npm/` に `index.js`、`index.d.ts`、source map、`package.json`、
`AUTOLINK_DIAGNOSTICS.md` を書きます。README と license があれば同梱します。

library subdirectory の `moon.pkg` は npm subpath export になります。たとえば
`src/mtsc` は `@scope/package/mtsc` です。一方、`main` を持つ package は
`bin/<command>.js` と `package.json#bin` に出力されます。`moon.mod` の
`options(exclude: ...)` にある path は公開しません。

`--pkg` の主なオプション:

- `--out <dir>` — publish directory。既定は module root の `npm/`。
- `--import-rewrites <json>` — MoonBit import を公開 TypeScript specifier へ rewrite。
- `--strict` / `--no-strict` — autolink diagnostics に omitted member があれば失敗。
- `--no-facade` — top-level free function glue のみを生成。

生成済み `@mizchi/ts` の `mtsc` はグローバル install なしで実行できます。

```sh
npx --package=@mizchi/ts mtsc --help
```

## Interface から生成する

既存 interface を使う低水準フローです。

```sh
# Recursive .d.ts package と build-backed runtime scaffold
mbt2ts scaffold src/pkg.generated.mbti out/ts-pkg

# External MoonBit import を npm specifier へ置き換える
mbt2ts scaffold src/pkg.generated.mbti out/ts-pkg import-rewrites.json

# Local method / constructor の facade を opt-in
mbt2ts facade-scaffold src/pkg.generated.mbti out/ts-pkg

# 個別段階
mbt2ts link-config src/pkg.generated.mbti
mbt2ts package src/pkg.generated.mbti out/ts-pkg
mbt2ts decl src/pkg.generated.mbti
```

`--input <pkg-or-mbti> --out <dir>` は project-oriented lower-level flow です。
`--diagnostics <path>` で `AUTOLINK_DIAGNOSTICS.md` の出力先を変えられます。
完全な引数は `mbt2ts --help` を参照してください。

## 公開 API の契約

- root と child package の top-level public free function を JavaScript runtime から
  export します。
- struct は plain object、enum は `$tag` discriminant を使います。opaque brand により
  TypeScript の lookalike object を MoonBit value として渡せません。
- `raise` effect は TypeScript では `Result<Return, ErrorType>` になります。
- facade を有効にすると local の non-generic method / constructor と async member に
  top-level wrapper を生成します。
- runtime に届かない member、external import、omitted autolink surface は
  `AUTOLINK_DIAGNOSTICS.md` に記録します。

generic constructor、trait method、generic owner の method、trait-bound generic
function は安全な JS surface を作れないため export しません。temporary glue の
`moon.pkg` や generated `.mbt` は build input であり、最終 npm package には含めません。

## Vite integration

`vite-plugin-moonbit` では `moonbit({ npmPackage: { entry, outDir } })` を使って
publishable npm package を生成できます。TypeScript bridge と併用するときは
`generatorRoot` と command を共有します。詳細は plugin 側の API documentation を
参照し、package output の契約はこのページの `--pkg` と同じものとして扱ってください。
