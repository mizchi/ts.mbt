# 実コードでの minify 検証: React と TypeScript compiler

`fixtures/mangle-safety` の corpus は「この状況で壊れないか」を確かめる
ものです。通ったところで、**corpus に無い状況**が無いことは何も示しま
せん。そこで、公開されている実コードを minify して、同じ観測が返るかを
確かめました。

対象は 2 つ。

| 対象 | 何を見るか |
| --- | --- |
| React 18.3.1（react / react-dom / scheduler） | 実行して観測が一致するか |
| TypeScript 5.7.3（`src/compiler/checker.ts` と `lib/typescript.js`） | 3 MB / 9 MB の実 source を通せるか、出力が有効な JS か、compiler として動くか |

結論を先に書くと、**この検証を始めた時点では 1 つも通りませんでした**。
5 件の bug を潰して通るようになりました。うち 3 件は corpus では原理的に
出ない種類のものです。

## 見つかった bug

### 1. 比較演算子が file を丸ごと食う（parser）

最小再現はこれです。

```js
{ a < b; } c > (1);
```

`<` が type argument list の開始かどうかを決める先読みが、`>` に着くまで
**任意の token を通していました**。`a < b; } c >` は `<`…`>` として釣り
合ってしまい、直後の `(` を見て「generic call `a<…>(1)`」と確定し、
block の閉じ括弧ごと飲み込みます。

`<` が 1 つと、後ろのどこかに `> (` が 1 つあれば発火します。大きな実
source では確率ではなく確定で、`checker.ts`（3 MB）も `typescript.js`
（9 MB）も**まったく parse できませんでした**。報告されるのは
`Expected RBrace, got Eof` の 1 行だけ —— 入力が尽きた場所の話しかしない
ので、原因の位置は何も分かりません。

修正は、候補の type argument list 内部で bracket の nesting を数え、型に
現れ得ないものが来たら降りる（開いていない閉じ括弧、`{…}` の外の `;`、
statement keyword）。降りる方向が安全側で、`<` は本来の比較として読まれ
ます。`f<{ a: number; b: T }>()` や `f<(x: A) => B>()` は実在するので、
brace / paren / bracket と member 区切りの `;` は通したままです。

同じ関数には**同種の bug の修正済み記録が既にありました**（for 条件の
`S<N;` が EOF まで走る）。そのときの対処は「釣り合いを要求する」でした。
釣り合いでは足りません。要件は「間にあるものが全部型に現れ得る」です。

### 2. `else` の中括弧は scope である（fold / peephole）

else-hoist は `if (c) { … return } else { … }` を
`if (c) { … return } …` にします。制御フローとしては正しく（then が抜けた
ときしか else は走らない）、**scope としては誤り**です。あの中括弧は、
中の `let` が外側の同名 binding と衝突しないようにしている唯一のものです。

そして衝突の結果は微妙な誤動作ではありません。duplicate lexical
declaration は SyntaxError なので、**file 全体が読み込まれません**。

`checker.ts` にちょうどその形があります。

```ts
case SyntaxKind.AsteriskToken:
  if (…) { … return numberType; }
  else { … let resultType: Type; … }
case SyntaxKind.PlusToken:
  … let resultType: Type | undefined; …
```

1 つの switch block に `let resultType` が 2 つ。片方が `else` の中に
あるので合法です。hoist すると
`Identifier 'resultType' has already been declared` になります。

この rewrite は `fold_stmt_into` と peephole pass の**2 箇所**にあり、
どちらにも同じ guard（top-level に `let` / `const` / class を宣言する
block は hoist しない）が必要でした。1 箇所目を直した時点では
`--fold` 単体でも `--minify` 単体でも通り、**両方指定すると再発**します。
test は 3 通りの組み合わせを回します。

### 3. 初期化子なし宣言が ReferenceError を吐く（emit）

`let x: T;` には初期化子がありません。parser はこれを
`Var("__ts_no_init__")` という marker で表します。emitter はこれを
`= undefined` / `= void 0` と同じ扱いで、**`--minify` のときだけ**落として
いました。後者 2 つは実在する式で、落とすのは最適化です。marker は式では
なく、出力すると `let x = __ts_no_init__` —— その行に到達した瞬間に
`ReferenceError` です。

つまり素の `mtsc --bundle` が、TypeScript で最もありふれた文の 1 つに
対して throw を出力していました。

### 4. `--mangle-properties` が解析なしで走る経路があった（CLI）

escape 解析は `bundle_modules` の中にしかありません。単一ファイル経路
（`transform_source_full`）には door 1 も door 2 も wildcard もありません。
そこで `--mangle-properties` を指定すると、**何の証明もなしに** property
を rename します。CJS module に対して実際にこうなりました。

```js
exports.useThing = useThing;      // 入力
exports.c = b;                    // 出力（module の公開 API が消える）
module.exports.extra = …;         // 入力
module.b.a = …;                   // 出力（`exports` まで rename）
```

安全な形が 1 つしかない flag は、その経路を自分で選ぶべきです。
`--mangle-properties`（と `--explain-mangle` /
`--mangle-properties-shape-color`）は `--treeshake` / `--fold` と同じく
`--bundle` を含意するようにしました。同じ入力を `--bundle` 経由で通すと、
`exports` / `module` が未宣言参照 = external として扱われ、wildcard が
立って property mangling が抑止されます —— 安全側の判定は最初から正しく
働いていて、届いていなかっただけです。

### 5. TypeScript でない入力を通す手段が無かった（CLI）

型エラーは既定で出力を止めます。プログラムが間違っているときはそれが
正しい。しかし**そもそも TypeScript でない入力**に対しては、pipeline
全体が到達不能になります。公開済みの `.js` bundle では object literal が
runtime で property を増やすのが普通で、その各箇所が型エラーとして出ます
（React の dev build で数十件）。

`--no-check` は診断を出したうえで emit します。型検査を切る flag では
ありません。

## 結果: React 18.3.1

`scripts/verify_mangle_safety.mjs` と同じ考え方で、install 済みの
package の file を差し替えて同じ観測を取り直します。観測は SSR の
描画結果（`renderToStaticMarkup` / `renderToString`）、hooks・context・
memo・class component・error boundary を通した component tree、そして
`Object.keys(React)` や element の key 集合といった API の形です。

`--minify --bundle --mangle --mangle-properties`、5 file 同時:

| file | before | after |
| --- | --- | --- |
| `react.development.js` | 87,593 | 27,068 |
| `react-dom-server-legacy.node.development.js` | 246,340 | 90,505 |
| `react-dom-server.node.development.js` | 244,692 | 89,347 |
| `react-dom.development.js` | 1,029,622 | 282,044 |
| `scheduler.development.js` | 17,497 | 4,874 |
| **合計** | **1,625,744** | **493,838**（70% 減） |

**観測は完全一致**（`node --check` も 5 file すべて通過）。

property mangling については、CJS の `exports` / `module` が host 所有の
object なので wildcard が立ち、user 定義の property 名は rename され
ません。つまりこの 70% は identifier mangling と dead code 除去による
ものです。**`--mangle-properties` を付けても壊れない**ことの確認であって、
property mangling が効いた結果ではありません。react-dom が
`React.__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED.ReactCurrentDispatcher`
を読むような package 間の private ABI も、この判定で守られます
（bug 4 の単一ファイル経路ではこれが壊れていました）。

## 結果: TypeScript 5.7.3

### `src/compiler/checker.ts`

3,065,627 → 1,521,251 bytes（50% 減）、`--minify`、68 秒。
`node --check` 通過。

checker.ts 単体は module graph の一部なので実行はできません
（`./_namespaces/ts.js` に依存し、単一ファイル経路は import / export を
落とすため —— 下の「未修正」参照）。ここで確かめたのは、3 MB の実
TypeScript を parse して有効な JS を吐けること、そして 1・2・3 の bug が
すべてこの file で発火していたことです。

### `lib/typescript.js`（compiler 本体）

9 MB の published bundle を minify し、**minify した compiler で
TypeScript を compile して**診断を比べます（`verify/tsapp.cjs`）。
`checker.ts` を含む file なので、これが「checker が動く」の実質的な確認に
なります。観測は `transpileModule` の出力、`createProgram` +
`getPreEmitDiagnostics` の診断（code / 行 / message）、`TypeChecker` で
引いた型の文字列、公開 API の形。

数値と結果は次節の表に入れています。

## 未修正として残すもの

検証中に見つけたが、この作業の範囲外として報告だけしているもの。

- **単一ファイル経路が import / export を落とす。**
  `mtsc src/index.ts --out dist/index.js`（`--bundle` なし）は
  `transform_source_full` を通り、runtime 文だけを emit します。
  `mb.imports` / `mb.exports` を再出力しないので、
  `import { join } from "node:path"` は消え（`join` は未定義参照になる）、
  `export` は 1 つも残りません。README / `docs/mtsc.md` が最初に見せる
  使い方がこれです。`--bundle` 経路は正しく出力します。
- **exhaustive switch の false positive。** 全 case と `default` が
  `return` する switch に対して checker が
  `not all paths return` を出します。
- **9 MB 入力で 15 分。** 3 MB の checker.ts が 68 秒、9 MB の
  typescript.js が約 15 分。superlinear なので、どこかに quadratic な
  pass があります。

## この検証が corpus と違うところ

corpus の 148 件は「思いついた状況」の集合です。生成器
（`scripts/generate_mangle_cases.mjs`）で carrier × exit の直積を払い出す
ようにしたのは、その穴を機械的に埋めるためでした。それでも、上の 1・2・3
は 1 件も出していません。理由は軸が違うからです。

- 1 と 2 は **file の大きさと statement の隣接関係**が要る。corpus の case
  は数十行で、`<` と `> (` が離れて並ぶ確率も、1 つの switch block に同名
  `let` が 2 つ現れる形も、まず作られません。
- 3 は **`--minify` を付けない出力**を誰も見ていなかった。corpus は
  baseline と mangled を比較しますが、両方 minify 済みなので、marker は
  両方で落ちていました。「両方の出力に同じ bug がある」を見るために
  reference leg（元の TS を Node の type stripping で実行）を足したのと
  同じ話が、flag の組み合わせについても要ります。

追加した gate は 2 つです。

1. **出力が有効な JS であること。** `node --check`。minifier が invalid な
   JS を吐くのは minify ではないのに、これまで suite の中で誰も見ていま
   せんでした。
2. **実 package の実行差分。** 上の React の表がそれです。
