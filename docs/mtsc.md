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
mtsc [options] [files...]          # compile（default mode）
mtsc -p <tsconfig.json|dir>        # project を compile
mtsc                               # cwd の tsconfig.json を読む
mtsc <command> [args...]           # verb
```

`mtsc` はこの toolchain の唯一の binary です。`ts2mbt` / `mbt2ts` /
`tscheck` / `tsacc` の 4 binary は verb として集約されました:

| Verb               | 旧 binary | 用途                                                   |
| ------------------ | --------- | ------------------------------------------------------ |
| `mtsc bridge`      | `ts2mbt`  | TypeScript → MoonBit bridge 生成                       |
| `mtsc pkg`         | `mbt2ts`  | MoonBit → TypeScript / npm package 生成                |
| `mtsc check`       | `tscheck` | 1 file の checker 診断（開発用、常に exit 0）          |
| `mtsc conformance` | `tsacc`   | conformance corpus に対する精度集計（開発用）          |

verb は同名の file よりも優先されます。`mtsc check` が「`check` という
directory があるかどうか」に依存しないためで、source file は `x.ts` と
書かれるので実害はありません。file を指したいときは `mtsc ./check` です。

`mtsc check` と `mtsc --noEmit` は別物です。違いは **program** の単位で、
`--noEmit` は `tsc` と同じく import graph をたどって 1 つの program として
検査し、`mtsc check` は 1 file を単一 file model で検査します。後者は
conformance corpus が求める形（4,484 件それぞれが 1 file の program）で、
`checker_conformance_oracle.sh` などが出力行を parse するので、その 1 行の
文面は interface として固定されています。`mtsc check` は何を見つけても
exit 0 です（corpus を回す script が `set -e` で動くため）。

### `tsc` / `tsgo` compatibility

compile mode の command line は `tsc` の **superset** です。option 名は
大文字小文字と `-` / `_` を無視して照合するので、`--noEmit`、`--no-emit`、
`--noemit`、`--NoEmit` は同じ option です（`tsc` 自身は小文字化のみ）。

`tsc` の option は 3 つの tier に分かれます。

1. **honour する** — `-p` / `--project`、`--noEmit`、`--noCheck`、
   `--outFile` / `--out` / `-o`、`--outDir`、`--declaration` / `-d`、
   `--emitDeclarationOnly`、`--sourceMap`、`--jsx`、`--jsxImportSource`、
   `--jsxFactory`、`--jsxFragmentFactory`、`--watch` / `-w`、`--init`、
   `--showConfig`、`--listFiles`、`--listFilesOnly`、`--version` / `-v`。
2. **受け取るが動作しない** — `--target`、`--module`、`--strict`、
   `--incremental` など。1 行だけ「honour していない」と報告します。
   `tsc` を前提にした pipeline が `--target es2020 --strict` を渡すのは
   普通なので、ここで hard-fail すると superset を名乗る意味がなく、
   黙って受け取ると `--strict false` が効いたように見えてしまいます。
   報告するのはその 2 つを避けるためです。
3. **拒否する** — `tsc` の option でも mtsc の option でもないもの。
   `tsc` と同じく diagnostic を出して non-zero で終了します（以前の
   `mtsc` は unknown option で exit 0 だったので、build script の typo が
   見えませんでした）。

`--build` / `-b` は拒否側です。project reference と up-to-date 判定が
必要で mtsc にはどちらもなく、`tsc -b` を solution file に対して実行する
のは「その file を compile してほしい」という要求ではないからです。

exit code は `tsc` 準拠で、0 が成功、1 が「診断があり output を書かな
かった」です。`tsc` の 2（診断はあるが output は書いた）には到達しません
— 検査が失敗すれば emit は止まり、`--noCheck` は検査を降格ではなく
skip するので、報告する診断が存在しません。

### Project mode

引数に file を並べた場合は `tsc` と同じく `tsconfig.json` を完全に無視
します。file を並べなかった場合のみ `-p` の指す config、あるいは cwd の
`tsconfig.json` を読み、`files` / `include` / `exclude` を展開します。
glob は `tsc` の 3 形式（`*`、`?`、`**/`）だけです。config からは
`outDir` / `outFile` / `noEmit` / `declaration` / `emitDeclarationOnly` /
`sourceMap` / `noCheck` を読み、いずれも command line の下に置きます。

`node_modules` は走査中に枝刈りします。依存を install した project では
自分の source tree より 2〜3 桁多い file がそこにあるので、走査後に
exclude で落とすのでは読む cost を払ってしまいます。

### Watch mode

`--watch` は polling です。`mizchi/x/fs` にも `moonbitlang/async/fs` にも
watch syscall がないので、`mtime` を 300ms 間隔で比較します。監視対象は
entry list ではなく **解決済みの program** で、bundle では import graph を
たどった結果です。よって import された file の変更でも rebuild します。

限界を 2 つ明示します。`include` が覆う directory に **追加** された file
は、既存 file が変わるまで気づきません（新しい path には比較対象の mtime
が無く、poll は既に持っている集合を比較するからです）。もう 1 つは
間隔そのもので、短くすれば大きな program で CPU を食い、長くすれば壊れて
いるように見えます。

### mtsc 固有のオプション

- `--out`, `-o <file.js>` — 出力先。指定しなければ stdout。
- `--outDir <dir>` — 入力ごとの JavaScript を `<dir>` 直下に置く。
- `--bundle` — relative import をたどり単一 bundle を出力。
- `--treeshake` / `--fold` / `--minify` — bundle を最適化。
- `--dts` — `tsc` の `--declaration` と同じ。`--bundle` を含意。
- `--sourcemap` / `--sourceMap` — output の隣に v3 source map を出力。
- `--mangle`、`--mangle-properties` — internal name / property の rename。
- `--explain-mangle` — `--mangle-properties` が「なぜその名前を rename しな
  かったか」を出力（下記）。
- `--no-check` / `--noCheck` — 型検査を skip して JavaScript を出力。
  TypeScript ではない入力（公開済みの `.js` bundle など）向け。
- `--jsx-runtime automatic|classic`、`--jsx-import-source <pkg>`、`--jsx-dev` — JSX
  transform の設定。`tsc` の `--jsx` / `--jsxImportSource` /
  `--jsxFactory` / `--jsxFragmentFactory` も同じ設定に入ります。

すべてのオプションは `mtsc --help` で確認できます。

`--mangle-properties`（および `--explain-mangle` /
`--mangle-properties-shape-color`）は `--bundle` を含意します。escape 解析は
`bundle_modules` の中にしかないので、単一ファイル経路では解析なしで
property を rename してしまい、CJS の `exports.foo` まで書き換えていました。
安全な形が 1 つしかない flag は、その経路を自分で選ぶべきです。

## 非 TypeScript 入力: `--no-check`

型エラーは既定で出力を止めます。プログラムが間違っているときはそれが
正しい挙動ですが、**そもそも TypeScript でない入力**に対しては pipeline
全体が到達不能になります。公開済みの `.js` bundle では object literal が
runtime で property を増やすのが普通で、その各箇所が型エラーとして出ます。

`--no-check` は診断を出したうえで emit します。minify / mangle pass を
実 JS に対して走らせるための escape hatch で、型検査を無効化する意味では
ありません（診断は今までどおり全部出ます）。

## `--explain-mangle`

`--mangle-properties` は安全側に倒れる解析なので、「rename されなかった」が
既定の結果です。その理由を出すのがこの flag です（`--mangle` と
`--mangle-properties` を暗黙に有効化します）。

```sh
mtsc --bundle src/index.ts --external ext --explain-mangle --out dist/index.js
```

出力は 4 つの pass に対応する 4 節で、読む順に並びます。最初の節が
「なぜ property 名を予約したか」で、そこに `*`（wildcard）が出た場合は
残り 3 pass も連鎖して止まるため、まずここを消す必要があります。

```
property mangling: why names are reserved

  SUPPRESSED — the analysis reserved the wildcard, so no
  user-declared property name is renamed. Causes:
    * binding `cfg` crosses the bundle boundary and carries no closed
      type annotation, so every name on it is assumed reachable — …

  read off an external import or ambient global (3)
    info post channel
  literal key handed straight to a sink (1)
    stage
  reachable through an observed value tree (2)
    retries timeoutMs

trailing-parameter trimming: why a function kept its arity

  * `announce`: the entry exports it, so its arity is package ABI
…
```

節の見出しがそのまま予約の理由です。`retries` が消えないのは
「観測される値の木から到達できる」からで、`stage` が消えないのは
「sink に直接渡した literal の key だから」——どちらも直し方が違います。
解析の分類そのものは [`docs/mangle-safety.md`](./mangle-safety.md)、pass ごとの
証明義務は [`docs/minify-patterns.md`](./minify-patterns.md) にあります。

実装上の要点として、この出力は判定を再計算したものではありません。
`collect_externally_visible_props` は `escape_breakdown` の結果を merge する
だけの関数で、説明と判定が同じ 1 回の解析から出ます。説明だけが古くなる
ことがないようにするためです。

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

ゲートになっている数値は TypeScript 7（tsgo）の conformance 結果との照合です
（`just verify-checker-soundness`、2026-09-20 測定）。

| Metric                    | Result                                   |
| ------------------------- | ---------------------------------------- |
| TP（TS7 error & 検出）    | 2,670（うち parse rejection 経由 390）   |
| MISS in scope（未検出）   | 45                                       |
| OUT OF SCOPE（宣言済み）  | 19（`scripts/checker_out_of_scope.txt`） |
| FP（TS7 accept & 検出）   | 0                                        |
| PFLEGAL（合法構文の拒否） | 0                                        |
| TN（TS7 accept & 沈黙）   | 1,750                                    |

残り 45 件の内訳（必要な機構ごと）と、実測した未対応のコード形状は
[`src/checker/UNSUPPORTED.md`](../src/checker/UNSUPPORTED.md) に、tier と
スコープ外の判断は [checker triage](./checker-triage.md) にあります。

この表だけでは見えないものがある点に注意してください。corpus の 4,484 件は
どれも数十行の単一ファイルなので、**実コードでしか踏まない false positive は
FP 0 のままでも存在しえます**。batch FB はその実例で、conformance の数値は
一切動かさずに（TP 2,670 / MISS 45 / FP 0 のまま）、zod のソースに出ていた
false positive を 5 件消しました（118 → 113 diagnostics）。`node_modules` 配下の
`.d.ts` 4,085 件のスイープは前後でバイト一致です。batch FC はこれをさらに大きな
実入力に向けたもので、`typescript.d.ts`（tsc がそのまま受理する、最大の宣言
ファイル）に対する **88 件の diagnostics は全部 false positive、うち 80 件が
1 つのルール**（TS2430）でした。conformance の数値を一切動かさずに 88 → 15、続く
batch FD（`.d.ts` は `declare` の有無によらず全宣言が ambient）でさらに 7 まで下がり、
preact は 4 → 0 になりました。conformance corpus に `.d.ts` は 1 つも無いので、
oracle が動かないことがそのまま「ファイル単位の免除であってルールの弱体化ではない」
ことの確認になっています。batch FE（namespace からファイル先頭の import を
re-export できる）で vitest も 6 → 0 になり、FB〜FE 合計で実コードの
false positive を **1,244 件削除・追加 0**、その間 TP / MISS / FP はすべて不変です。
batch FF で `typescript.d.ts` は **88 → 1** になりました（残り 1 件は `JSDoc.parent`）。

参考として、2026-09-16 に `moon run src/cmd/mtsc -- conformance` で測定した pinned subset
（TS6 時代の `.errors.txt` baseline を正解とする軽量計測）の結果も残します。

| Metric             | Result                |
| ------------------ | --------------------- |
| Parsed files       | 1,189 / 1,229 (96.7%) |
| Error recall       | 771 / 815 (94.6%)     |
| TS-clean precision | 409 / 414 (98.8%)     |
| False positives    | 5                     |

これは `mtsc conformance` の permissive checker による限定 corpus の互換性計測であり、完全な
`tsc` 互換性や `mtsc` CLI の strict mode を保証する数値ではありません。この表の
「false positive」は TS6 baseline に対するもので、TS7 オラクル（上表、FP 0）とは
正解が異なります。再計測方法と対象ディレクトリは
[`mtsc conformance` guide](./tsacc.md) に記載しています。

構文受理はこれとは別に、TypeScript 7 conformance corpus の単一ファイルケースで測定して
います。`mtsc check` と `mtsc` は同じ parser を使い、TS7 が合法とする 1,750 件を 1,750 件
受理しています（PFLEGAL: 0）。TS7 が構文エラーとする 390 件は parser が rejection します。
一方、直前の pinned subset 表で parse できなかった 40 件も、意図的に不正な構文を含む
conformance fixture であり、
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
