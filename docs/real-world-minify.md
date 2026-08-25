# 実コードでの minify 検証: React と TypeScript compiler

`fixtures/mangle-safety` の corpus は「この状況で壊れないか」を確かめる
ものです。通ったところで、**corpus に無い状況**が無いことは何も示しま
せん。そこで、公開されている実コードを minify して、同じ観測が返るかを
確かめました。

対象は 5 つ（+ terser との size 比較）。

| 対象 | 何を見るか |
| --- | --- |
| React 18.3.1（react / react-dom / scheduler） | 実行して観測が一致するか |
| hono（git clone、TS source 188 file） | npm を経由せず TS source を直接通し、HTTP 応答が一致するか |
| valibot（git clone、TS source 578 file） | overload set と quoted property dispatch を通せるか、parse 結果が一致するか |
| TypeScript 5.7.3（`src/compiler/checker.ts` と `lib/typescript.js`） | 3 MB / 9 MB の実 source を通せるか、出力が有効な JS か、compiler として動くか |

結論を先に書くと、**この検証を始めた時点では 1 つも通りませんでした**。
13 件の bug を潰して通るようになりました。うち 10 件は corpus では原理的に
出ない種類のものです。

その後「hono の使わない機能はもっと落とせるはずだ」を測る過程で、
**正しさ**の bug が 8 件出ました。

| # | 何が起きたか | 出る flag |
| --- | --- | --- |
| 14 | 動的 access の read と write の判定が逆で、`obj[k]` で dispatch される method が削除されていた | `--treeshake` |
| 18 | `this.f[k]` で読まれる property が rename されていた | `--mangle-properties` |
| 19a | computed key の destructuring が identifier mangling を crash させる | **素の `--mangle`** |
| 19b | 同じ形で property の唯一の write が落ちる | `--mangle-properties` |
| 20 | computed write が静的 read と食い違う | `--mangle-properties` |
| 21a | pattern default の参照が予約されず、parameter が shadow する | **素の `--mangle`** |
| 21b | pattern の computed key が rename されない（= 19a の予約側） | **素の `--mangle`** |
| 22 | default 付き parameter が method / arrow で必須扱い（checker の false positive） | 既定 |
| 23 | parameter list / catch clause の pattern default が予約されず TDZ | **素の `--mangle`** |

19a と 23 以外は crash ではなく**静かに違う答え**を返す形です。
そして 8 件のうち **4 件が property mangling 抜き**で壊れています。同じ調査で
`--explain-mangle` に method DCE の section を足し（#15）、class field
注釈が lowering で消えているのを直しました（#17）。

## compile 時間はどこに行っていたか

「重い場所を特定できるようにしたい」から始めて、`mtsc --timing` を
足しました。pipeline の各 pass が自分の wall time を報告し、CLI 側
（読み込み・parse・型検査）も同じ表に並びます。

**最初の 1 回で予想が外れました。** `checker.ts`（3 MB）の 31.6 秒のうち、
instrument した 20 個の transform pass の合計は **731 ms** でした。

```
     29402 ms   95.9%  cli: typecheck
       439 ms    1.4%  cli: read + parse files
       228 ms    0.7%  class-method-dce
       ...
     30647 ms  total
```

**型検査が 95.9%。** しかも `--no-check` を渡した状態です。当時の
`--no-check` は「診断を出すが fatal にしない」だったので、checker は
フル実行され、その成果物は**呼び出し側が「止めるな」と言った診断**だけ
でした。wall clock の 96% をそれに払う取引は成立しません。`--no-check`
は**検査自体を飛ばす**ようにしました（診断だけ見たいなら `tscheck`）。

次に出たのが自分で入れた quadratic です。9 MB の `typescript.js` で
`class-method-dce` が 5.5 秒 / 10.9 秒。原因は `numeric_vars.mbt` と
`container_vars.mbt` の fixed point で、`Var(n)` の照合ごとに
**全 symbol を走査**していました（round × symbol × symbol）。round ごとに
1 回だけ name へ射影するようにして 5.5 秒 → 0.7 秒。

`--reserve-typed-props` しか読まない `type_props` の収集が、全 file の
**2 回目の full parse** だったのも削りました（2.1 秒 → 1.35 秒）。

| target | 前 | 後 | 出力 |
| --- | --- | --- | --- |
| `checker.ts`（3 MB） | 31.6 s | **0.95 s** | byte 一致 |
| `typescript.js`（9 MB） | 約 390 s | **4.6 s** | byte 一致 |
| real-world 5 target 全体 | 約 7 分 | **12.5 s** | 5/5 pass |

`just bench-pipeline` で再現します。今の残りは **parse が 78〜94%** で、
同じ source を **2 回 parse** しています（CLI の loader が import 探索で
1 回、`load_module_graph` が module graph 構築で 1 回）。次に削るのはそこ
です。

```
    target          bytes in     wall ms     KiB/s
    minify-app          8,776         17       491
    hono              771,362        205      3669
    valibot         1,588,417       1461      1062     ← 578 file、1 file あたりの固定費が支配
    checker.ts      3,065,627        949      3155
    typescript.js  27,301,748       4611      5783
```

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

### 5. 単一ファイル経路が module の境界を落とす（emit）

`mtsc src/index.ts --out dist/index.js`（`--bundle` なし）は
`transform_source_full` を通り、**runtime 文だけ**を emit していました。
`mb.imports` / `mb.exports` を再出力しないので:

```ts
import { join } from "node:path";
export const dir = join("a", "b");
export default function main() { return dir; }
```
→
```js
const dir = join("a", "b");          // join は未定義参照
function main() { return dir; }      // export は 1 つも無い
```

README と `docs/mtsc.md` が最初に見せる使い方がこれです。この経路は
`preserve_top_level` で top-level 名を一切 rename しないので、
import 宣言を前に、export 節を後ろに出せば済みます（linker の rename map
が要る `--bundle` 経路と違う点）。

ただし**そのまま出すと壊れます**。TypeScript は型としてしか使われない
import を erase し、code はその erase に依存しています。checker.ts は
**interface** の `SymbolLinks` を import したうえで

```ts
const SymbolLinks = class implements SymbolLinks { … };
```

を宣言します。import が消えているから合法な形です。verbatim に出すと
1 つの名前に宣言が 2 つ並び、SyntaxError で file 全体が読み込まれません。

なので emit する import は「実行される code が実際に参照している binding」
だけに絞ります（tsc の import elision と同じ判断）。型注釈はこの時点で
既に erase されているので、残っている参照は値参照です。加えて
**block が同じ名前を自分で宣言しているなら import は落とす** ——
参照カウントだけでは足りません。その参照は local 宣言のものだからです。
side-effect のみの import（`import "./polyfill"`）は評価が目的なので
無条件に残します。

### 6. `return` の後の function 宣言が消える（peephole）

`return` の後の function 宣言は到達不能ではありません。**hoist される**
ので、return より前の code から呼べるし、`return f;` で外に渡せます。
`typescript.js` は全体がこの書き方です。

```js
var createUIStringComparer = (() => {
  return createIntlCollatorStringComparer;
  function createIntlCollatorStringComparer(locale) { … }
})();
```

peephole pass は最初の hard terminator で打ち切り、以降を全部落としてい
ました。結果、minify した compiler は
`var k2 = (() => d)()` —— **どこにも存在しない名前を return する形**に
なり、require した瞬間に `ReferenceError: d is not defined`。

`fold_block` は同じ問題を既に正しく扱っていて（宣言を集めて exit の前に
戻す）、`peep_block` に同じ処理が無かった、という形です。到達不能な文は
今も落とします。

これも組み合わせでしか出ません。`--mangle` 単体なら rename して残り、
`--minify` 単体ならこの block に到達せず、**両方指定すると消える**。
test は 4 通り回します。名前ではなく function の本体（`-1`）を見ています
——`--fold` を付けると 1 回しか使われない宣言は `return` の中に inline
されるのが正しい挙動なので、名前や `function` の個数では判定できません。

そして**この bug を捕まえられたのは「minify した compiler を実際に
動かす」leg だけ**です。出力は `node --check` を通り、corpus も通り、
それでも壊れていました。

### 7. 自己参照する宣言を return に畳み込む（peephole）

`let x = expr; return x;` → `return expr;` の畳み込みに、**`expr` が `x`
自身を参照していないかの検査が無かった**。closure に遅延された自己参照は
普通の JavaScript で、TypeScript の compiler host はまさにその形です。

```js
const compilerHost = {
  getSourceFile: getSourceFileWithCache(f => compilerHost.readFile(f)),
  …
};
return compilerHost;
```

畳み込むと closure が存在しない名前を指します。そして mangle 後は
`ReferenceError` より悪いことが起きます —— 短い名前が**別の関数のもの**に
なっていたので `compilerHost.readFile` が別物に解決され、read が throw し、
`getSourceFile` 自身の `catch { text = "" }` がそれを飲み込みました。
全 lib file が空文字列として読まれ、source file が 52 → 2 に。

結果、minify した compiler は正しい入力に対して
`Cannot find name 'Math'` と
`Property 'toFixed' does not exist on type 'number'` を出し、
`Box<string>` を `Box<any>` と推論しました。**crash ではなく静かに
間違った答え**です。

`inline.mbt` は同じ形を既に断っています（closure capture を見ている）。
peephole の tail fold にだけ guard が無かった、という形でした。
`expr_refers_to` は意図的に nested function の中まで見ます —— 問題になる
参照は遅延されたものなので、既存の local-only helper が止まる場所が
ちょうど間違っています。

### 8. TypeScript でない入力を通す手段が無かった（CLI）

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

3,065,627 → 1,542,261 bytes（50% 減）、`--minify --fold`、48 秒。
`node --check` 通過。

checker.ts 単体は module graph の一部（`./_namespaces/ts.js` に依存）なので
実行はできません。ここで確かめたのは、3 MB の実 TypeScript を parse して
有効な JS を吐けること、そして 1・2・3 の bug がすべてこの file で
発火していたことです。#16 が出たのもここです —— 依存先の 3 module は
build 生成物で repository に無く、それで compile 全体が落ちていました。
今はその 3 つが verbatim な import として出力に残るので、以前の記録
（1,537,847）よりわずかに大きくなっています。

### `lib/typescript.js`（compiler 本体）

9,044,103 → 3,581,914 bytes（60% 減）、`--minify --bundle --mangle`、
約 13 分。`node --check` 通過。

9 MB の published bundle を minify し、**minify した compiler で
TypeScript を compile して**診断を比べます。`checker.ts` を含む file なので、
これが「checker が動く」の実質的な確認になります。観測は
`transpileModule` の出力、`createProgram` + `getPreEmitDiagnostics` の
診断（code / 行 / message）、`TypeChecker` で引いた型の文字列、公開 API の形
——**すべて一致**。

harness 側の落とし穴を 1 つ記録しておきます。**出力は package の
`lib/` directory に置く必要があります。** TypeScript は既定の
`lib.*.d.ts` を自分の file 位置から解決するので、別の場所から動かした
compiler は lib 無しで型検査してしまい、`Math` が未知の名前になります。
pristine な copy を `lib/` の外に置くと同じ症状が出るので、最初にこれが
出たときは「minifier の bug ではない」をその方法で切り分けました
——そして `lib/` の中に置いて比べたら**本物の差**（bug 7）が残った、
という順序です。

## 未修正として残すもの

検証中に見つけたが、この作業の範囲外として報告だけしているもの。

- **exhaustive switch の false positive。** 全 case と `default` が
  `return` する switch に対して checker が
  `not all paths return` を出します。
- **9 MB 入力で 13 分。** 3 MB の checker.ts が 66 秒、9 MB の
  typescript.js が約 13 分。superlinear なので、どこかに quadratic な
  pass があります。

## terser との比較

`scripts/compare_terser.mjs`（`node scripts/compare_terser.mjs`）。全列を
**実行が通った出力**に対してのみ測ります —— 壊れている出力の byte 数は
結果ではありません。

React stack 5 file（1,625,744 bytes）:

| variant | bytes | gzip KiB | 減 | 挙動 |
| --- | --- | --- | --- | --- |
| mtsc `--mangle` | 493,820 | 150.9 | 70% | 一致 |
| mtsc `+ --mangle-properties` | 493,820 | 150.9 | 70% | 一致 |
| terser `--compress --mangle` | 478,129 | 145.2 | 71% | 一致 |
| terser `+ --mangle-props` | 426,330 | 138.1 | 74% | **throw する** |

読み取れること。

- **既定同士なら terser より 3.3%（gzip 3.9%）大きいだけ。** 一から書いた
  minifier としては妥当な位置です。
- **`--mangle-properties` を付けても 1 byte も変わらない。** これは失敗では
  なく、この target では解析が正しく降りているということです（下記）。
- **terser の unsafe な property rename の取り分は 11% で、React を壊します。**
  型駆動の安全な property mangling が奪おうとしている賞金の大きさが
  これです。上限が 11% だと分かっているのは有用な情報で、
  「まず正しく、次に 11%」という順序が正しいことも意味します。

## target の選び方（React は不適切）

React は **TypeScript ではない**うえに CJS です。CJS の `exports` /
`module` は host が所有する object なので wildcard が立ち、property
mangling は抑止されます。上の表で `mtsc` と `mtsc +props` が byte 単位で
同一なのがその証拠です。**つまり React は property mangling の主張を
何も測っていません。**

`--explain-mangle` を screening に使って、実在の TypeScript library を
当たった結果:

### hono: git clone した TS source を直接 minify

npm の dist を経由せず、`git clone honojs/hono` から `src/index.ts` を
entry に 188 file を bundle します。tsc + bundler + terser が分担する
仕事を mtsc が 1 段で行う形です。挙動は routing / middleware / params /
JSON / 404 / error handler を実際に叩いて response を diff します。

| variant | bytes | gzip | 挙動 |
| --- | --- | --- | --- |
| `--bundle`（未 minify） | 61,950 | 13,924 | baseline |
| mtsc `--minify --mangle` | 30,283 | 9,685 | 一致 |
| mtsc `+ --treeshake` | **24,493** | **7,817** | 一致 |
| mtsc `+ --mangle-properties` | **18,063** | **7,403** | 一致 |
| mtsc `+ --fold` | 18,097 | 7,397 | 一致 |
| terser `--compress --mangle` | 25,677 | 7,902 | 一致 |
| terser `+ --mangle-props` | 18,130 | 7,303 | **response が違う** |

**`--treeshake` を渡すと mtsc が terser を上回ります**（24,493 対 25,677、
gzip でも 7,817 対 7,902）。そして**安全な** property mangling を足した
18,063 は、terser の**危険な** `--mangle-props`（18,130、しかも response
が変わる）より raw で小さい。gzip では terser が 1.4% 上（7,403 対 7,303）
です。

> **訂正。** 最初にこの表を出したとき「terser のほうが 15% 強い」と
> 書きましたが、あれは **flag の非対称**でした。terser の `--compress` は
> `--module` があれば未参照の top-level 宣言を自分で落とします。mtsc 側に
> `--treeshake` を渡していなかったので、DCE 無しの mtsc と DCE 有りの
> terser を比べていたことになります。**同じ pass を両側で有効にしないと
> 数字は何も意味しません。** `scripts/compare_terser.mjs` の mtsc 列には
> `--treeshake` を入れました。

`--fold` はこの target では効きません（raw ではむしろ 34 byte 増える）。

この target で重要なのは byte 数ではありません。**clone した TS source を
直接通すと、npm の dist では出なかった bug が 3 件出ました。**

| # | 症状 | 原因 |
| --- | --- | --- |
| 9 | `./client` が読めない | `@fs.exists` が **directory にも true** を返すので、module path として directory を採用して "Is a directory" で死んでいた。`client/index.ts` に落ちる前に短絡していた |
| 10 | `src/hono-base.ts` が parse できない | `get!: T` / `get?: T` という **field**。`get` は contextual keyword なので accessor と解釈して `!` で失敗。hono は route method を全部この形で宣言している |
| 11 | **export される class が間違っている** | 下記 |

11 が深刻です。hono は `hono-base.ts` が `class Hono` を宣言して
`HonoBase` として re-export し、`hono.ts` が `class Hono extends HonoBase`
を宣言し、entry がそれを re-export します。linker は衝突する後者を
`Hono$1` に rename しますが、**entry の `export { Hono }` は import した
binding なので entry の rename map に載っておらず**、素の名前が merged
block の別宣言（= 抽象 base class）に解決されていました。

結果、bundle は base class を export し、`app.use(...)` が base が絶対に
設定しない `router` を触って落ちます。import 時には何も起きないので、
**動かして response を見るまで分からない**種類の bug です。

### valibot: overload set だらけの TS source

`git clone fabian-hiller/valibot` から `library/src/index.ts` を entry に
578 file。hono には無い書き方が入っています —— **公開 API のほぼ全部が
overload set** で、dispatch は quoted property (`~run`) 経由。

| variant | bytes | gzip | 挙動 |
| --- | --- | --- | --- |
| `--bundle`（未 minify） | 228,307 | — | baseline |
| mtsc `--minify` | 124,172 | 16,383 | 一致 |
| mtsc `--minify --mangle` | 88,642 | 14,932 | 一致 |
| mtsc `+ --treeshake` | 88,642 | 14,942 | 一致 |
| mtsc `+ --mangle-properties` | 88,642 | 14,932 | 一致 |
| terser `--compress --mangle` | 88,226 | 14,614 | 一致 |
| terser `+ --mangle-props` | 77,093 | 14,107 | **結果が違う** |

`--treeshake` の取り分が 0 なのは、valibot の entry がほぼ全部を
re-export するので落とせる top-level が無いからです。hono で 5.8 KB
効いたのは、router 実装のような**内部だけの code** があったからで、
「library だから効く／効かない」ではなく公開面の広さで決まります。

挙動は schema / pipe / transform / union / optional と error 側
（issue kind、dot path、`flatten`、`ValiError`）を実際に parse して比較。

ここでは **mtsc と terser がほぼ並びます**（88,642 対 88,226、gzip でも
14,933 対 14,615）。`+props` の取り分は 1 byte —— 予告どおり
quoted property dispatch で wildcard が立つので、property mangling は
正しく降りています。

そして**この target でしか出ない bug が 1 件**出ました。

### 13. mangle + treeshake + fold で export surface が全部消える（bundle）

2 回目の treeshake は **mangle 後の block** に対して走ります。root に
渡していたのは `export_roots` —— source が付けていた名前です。
top-level は `preserve_top_level: false` で全部 rename されているので、
**pre-mangle の名前は 1 つも一致せず、全 root が dead と判定されて
export surface ごと消えます。**

hono では 18 KB が 4 KB になり、`export` 節が 1 つも残りませんでした
（`SyntaxError: does not provide an export named 'Hono'`）。

`--mangle` / `--treeshake` / `--fold` の **3 つ全部**が必要です ——
2 回目の treeshake は fold branch の中にしかないので。`--mangle` を外すと
34,722 byte で正常に動くのが、原因の切り分けになりました。

root を mangle の rename map に通すだけの修正です。pass は無効化して
いません（到達不能な helper は今も落ちます）。

### 12. overload signature が runtime 宣言として emit される（parser）

TypeScript の overload signature は body を持ちません。型だけの宣言で、
1 つの実装の上に 2〜3 個並びます。mtsc はそれぞれを
`function f() {}` として emit していたので、1 つの名前に宣言が複数並び、
module では **SyntaxError で file 全体が読み込めません**。

```ts
export function pick(v: string): string;
export function pick(v: number): number;
export function pick(v: string | number): string | number { return v; }
```
→
```js
function pick$1(v) {}     // signature
function pick$1(v) {}     // signature
function pick$1(v) { return v; }
```

valibot は公開 API のほぼ全部がこの形で、`getDotPath` だけで 1 つの名前に
3 宣言が出ていました。`$1` という rename が付いているのも症状の一部です
—— signature が「宣言」として数えられ、衝突回避の rename を誘発していました。

`parse_function` は body 無しを 2 経路で扱っていて（`;` 即終了と
`{` が来ない場合）、どちらも空 body の `TsFunc` を返すので呼び出し側から
区別できませんでした。`last_function_bodiless` を parser state に立てて、
statement 化する 4 箇所（plain / async / export / export default）が
それを見て statement を落とします。**名前は export されたまま**です ——
続く実装がその名前を持つので。

`declare function` も同じ経路で消えます（型だけの宣言なので正しい）。

| target | 形 | 結果 | wildcard の理由 |
| --- | --- | --- | --- |
| zod 4.4.3 | TS source 116 file（npm に同梱） | bundle 成功 9.4 秒 → 310,621 bytes | `Proxy` / `Object.defineProperty` の handler 引数（`target` / `prop` / `receiver` / `mergedDescriptors`） |
| valibot 1.4.2 | TS source 557 file | bundle 成功 → 94,881 bytes | quoted property (`~run`) 経由の dispatch と `unknown` 型の入力 |
| TypeScript `src/compiler` | TS source | **不可** | `diagnosticInformationMap.generated.ts` が build 生成物でリポジトリに無い |
| @trpc/server | TS source 82 file | **不可** | 自己パッケージ名 import（`@trpc/server`）の path mapping 未対応 |

zod と valibot はどちらも「解析が正しく降りた」ケースです。動的
dispatch を持つ library では、door 2 が本当に開いています。

ただし valibot は最初、**こちらの過剰な保守性**で降りていました:
境界を越える `string` 引数（`lang` / `message` —— locale 参照と
error message）が単独で wildcard を立てていた。primitive は built-in
以外の property surface を持たないので予約すべき名前が無く、
これは bug でした（修正済み）。`unknown` / `any` は今も wildcard を
立てます —— そちらは本当に何の形にもなり得るので正しい判断です。

### 14. 動的 access の read と write が逆に判定されていた（class_method_dce）

unused class-method DCE は bundle 全体を 1 回 scan して、5 種類の construct
を「member 名を観測しうる」とまとめて扱い、どれか 1 つでも見つけたら
pass を止めていました。うち 2 つの判定が逆でした。

**computed key の write** (`obj[k] = v`) は receiver が `this` でない限り
sink 扱いでした。理由は `C.prototype[k] = v` で prototype を後から
生やす形があるから。しかし write は既存の名前を**観測しません**し、
新しい名前を生やしても pass が削除した method が戻ってくるわけでは
ないので、どの receiver でも sink になりません。

**computed key の read** は逆に、「1 つの property しか触らない」という
理由で素通しでした。触るのが 1 つでも、**どれを触るのか分からない**のが
問題です。これは実際に壊れていました。

```ts
class Handlers {
  alpha() { return "A" }
  beta()  { return "B" }
}
const h = new Handlers();
const key = process.argv[2] === "b" ? "beta" : "alpha";
const fn = (h as any)[key];      // 両方の名前の唯一の出現箇所
console.log(typeof fn === "function" ? fn.call(h) : "missing");
```

`alpha` も `beta` も静的 access が無いので両方削除され、出力は
`missing` / `missing`。正解は `B` / `A` です。

今は read が gate で、2 つの証明のどちらかで通します。

1. **key が数値だと証明できる。**`numeric_vars.mbt` が
   `arr[i]` / `arr[i + 1]` / `arr[n - 1]` を通します。整数 key は
   整数 slot しか指せません。
2. **receiver が member を持つ object ではなく keyed container だと
   宣言されている。**`table[k]`（`table: Record<string, string>`）は
   entry を引いているので method には届きません。array / tuple /
   string / `Record<…>` / index signature 型 / container だけの union。

`delete obj.m` も sink 扱いでした。class の prototype method は
configurable なので、method が有っても無くても `delete` は同じ `true`
を返します。instance に対する `delete` は prototype に届きません。
名前付きの形は access collector が `m` を pin するので、そもそも
消えません。今は operand を walk するだけです。

`Object.keys / values / entries / assign / fromEntries` と `for...in`、
spread は**own enumerable property しか見えません**。native class は
method を prototype 上の **non-enumerable** として置くので、これらでは
観測できません。`Object.assign(this, opts)` —— まさに hono の
constructor —— が bundle 全体の method DCE を止めていた形です。
ただし IIFE 化された `C.prototype.m = f` は own かつ enumerable なので、
bundle が enumerate している場合は IIFE 側の prototype method を全部
pin して native class だけ落とします。

non-enumerable まで見える reflection（`getOwnPropertyNames` /
`getOwnPropertyDescriptors` / `ownKeys` / `getOwnPropertyDescriptor`）は
そのまま sink です。

### 22. default 付き parameter が method / arrow で必須扱い（checker）

```ts
class C { m(n: number = 5): number { return n } }
new C().m();     // mtsc: expected 1 argument(s), got 0
const g = (n: number = 5) => n;
g();             // 同じ
```

free function と constructor は通ります —— そちらは rich な `TsParam`
metadata を持つので arity が正確に出ます。method / static method /
arrow は annotation だけから素の `Func` を組むので、default が
`param_defaults` に別置きされている事実が型に乗りません。

`(n = 5) => n` を拒否する false positive は、普通の TypeScript を
弾きます（`--no-check` が必要になっていた理由の 1 つ）。callable 型を
組むところで、default 付き parameter を `T | undefined` に widen
するようにしました —— parser が `n?: number` に対して既にやっている
のと同じ処理なので、`T | undefined` を理解している arity 経路が
そのまま理解します。6 形（free / method / constructor / arrow /
`?` / static）を 1 つの test で押さえています。

### 23. body の外に書かれた pattern default（mangle）

#21 と同じ根ですが、pattern が置かれている場所が違います。
**parameter list** と **catch clause** です。

```ts
const fallback = 9;
function pick({ n = fallback }: { n?: number }): number { return n; }
```
→
```js
function b({n: a = a}) { return a; }
```

`ReferenceError: Cannot access 'a' before initialization` ——
**素の `--mangle`** で TDZ です。

`ScopeFrame::function_child` は自由変数を **body から**しか集めて
いませんでした。parameter の default と分割代入 parameter の pattern は
この新しい scope で評価されるのに、**body の外に書かれている**ので、
`fallback` が予約されず、pattern の binder が同じ letter を取ります。

catch も同じ形です（`collect_var_refs_stmt` の `Try` arm が catch
binding を捨てていた）:

```ts
try { throw {}; } catch ({ message = label }) { return message; }
```
→ `catch ({message: a = a})`

corpus に `case38-param-pattern-scope` を追加しました。
`{ n = fallback }`、`{ n = fallback } = {}`、catch pattern の 3 形を
1 case で差分実行します。

### 21. binding pattern に隠れた値式（mangle）

pattern は 2 箇所に値式を隠します。element の default と computed key
です。どちらも enclosing scope で評価されるのに、walker が initializer
しか見ていませんでした。

**参照の予約漏れ**（静かに違う答え）:

```ts
const fallback = 9;                                    // → a
function pick(xs: number[]) { const [first = fallback] = xs; return first; }
```
→
```js
function b(a) { const [b = a] = a; return b; }   // `a` は今 xs
```

`fallback` が `pick` の body の自由変数として数えられていないので、
parameter allocator が同じ短名を割り当て、default が parameter に
解決されました。`pick([])` は 9 ではなく `[]` を返します。

**rename 漏れ**（crash）: `rename_binding_decl` /
`rename_binding_lhs` が `key_expr` を verbatim に通していたので、
`k` を rename した関数に `{ [k]: v }` が残り、**素の `--mangle` で
ReferenceError**。

`--mangle-properties` を付けると `dead_props` が「read が無い」と
判断して object literal の唯一の property まで落としていました
（#19 と同じ形）。corpus に `case37-pattern-default-scope` を
追加して、両方を差分実行で見ます。

### 20. computed write が静的 read と食い違う（mangle_safety）

read の逆向きです。書く側が computed key で、読む側が静的名:

```ts
const payload: { alphaTop?: number } = {};
function put(k: string, v: number): void { (payload as any)[k] = v; }
put("alphaTop", 1);
export const echoed = payload.alphaTop;      // 1 → undefined
```

write は `alphaTop` という名前を mangler に見えない形で installします。
一方 `payload.alphaTop` は普通に rename されるので、両者が食い違います。

read は素の binding receiver なら Phase 3+4 の observability が拾います
（`dynkey-binding` がそれを証明しています）。write は拾えません ——
Phase 3+4 が答えるのは「この binding の何を外から観測されるか」で、
**write は何も観測しない**からです。なので write は receiver を問わず、
key が narrow できなければ wildcard。

### 19. computed key の destructuring が 2 つの pass を同時に壊す

```ts
const payload = { alphaTop: 1 };
function pick(k: string): number | undefined {
  const { [k]: v } = payload as any;
  return v;
}
export const echoed = pick("alphaTop");
```

**素の `--mangle` で ReferenceError**。

```js
function b(b) {
  const {[k]: c} = a;    // param は b に rename、key の `k` はそのまま
  return c;
}
```

`rename_binding_decl` / `rename_binding_lhs` が
`TsObjectBindingProp.key_expr` を verbatim に通していました。computed key
は enclosing scope で評価される**普通の値式**なので、他の参照と同じく
rename が必要です。property rename 側（3 番目の site）も、
`{ [cfg.field]: v }` のように式の中の property を読み得るので walk します。

`--mangle-properties` を付けると、同じ形で**もう 1 つ**壊れていました。

```js
const a = {};              // { alphaTop: 1 } の property が消えている
```

`dead_props` が「read が無い」と判断して唯一の write を落としていました。
computed destructuring key を computed read と同じ扱いにして
`mangle_safety` が wildcard を立てるようにしたので、両方まとめて閉じます
（`dead_props` は reserved 集合で gate されているため）。

### 18. `this.f[k]` で読まれる key が rename されていた（mangle_safety）

#17 の corpus case を書いたら、method DCE とは別の pass が落ちました。
`--mangle-properties` **単体**で観測が変わります。

```ts
class Registry {
  #rows: Record<string, string> = { seed: "0" };
  read(k: string): string | undefined { return this.#rows[k]; }
}
console.log(new Registry().read("seed"));   // "0" → undefined
```

`seed` は object literal では**静的な key**、read では**string 値**として
届きます。前者だけ rename すれば lookup は外れます。crash ではなく
`undefined` —— 静かに違う答えです。

原因は wildcard の発火条件でした。computed index の read / write は
external chain の receiver に対してだけ wildcard を立て、それ以外は
「local binding なら Phase 3+4 の observability が追う」に任せていました。
`Var` receiver ならその通りです。`this.f[k]` / `a.b[k]` / `f()[k]` には
**追うべき binding が無い**ので、誰も key 集合を bound しないまま
mangling が走ります。

今は「index が narrow できない、かつ receiver が素の binding でない」なら
wildcard を立てます。数値 index（`this.items[i]`）は narrow 側で通るので
影響しません。実測でも hono / valibot / react / `examples/minify-app` の
size は 1 byte も変わりませんでした —— それらの bundle は別の理由で
既に wildcard が立っているか、string key の dynamic read が binding
receiver だけだったからです。

corpus に `case35-this-field-container` を追加しました。private field
経由（安全）と public field 経由（危険）の両方を 1 つの case に入れて、
差分実行で `viaDynamic` と `seeded` の 2 つが同時に見られます。

そのあと同じ形を `(this as any)[k]` で試したら**また落ちました**。
`this` は binding ではない —— symbol が無いので observability を
付ける先が無い —— のに、receiver 判定が `Var(_)` を一律 tracked と
見ていました。`this` / `super` / `globalThis` / `arguments` を除外。

### 生成器に 3 本目の軸を足した

ここまでで見つけた正しさの bug 2 件（#14 と #18）は、どちらも
**carrier × exit のどちらの軸にも乗らない**ところにありました。
「名前にどう到達するか」です。

```ts
const payload = { alphaTop: 1 };
const echoed = (payload as any)["alphaTop"];
```

宣言では静的 key、read では string 値。片方だけ rename すれば
`undefined` になります。**exit は関係ありません** —— 上の例は
bundle から何も出て行きません。

`scripts/generate_mangle_cases.mjs` に receiver の形を軸として
**10 件**払い出しました（`dynkey-*`）。binding / `this` の cast /
private field / public field / property chain / call 結果 /
array 要素 / computed write / destructuring key / `in` 演算子。
bug が全部ここに落ちていたのは、この形に「追える symbol」が
無く、それぞれ別扱い（か未対応）だったからです。

10 件とも harness の mutation self-check を通っています ——
`alphaTop` を rename すると観測が変わることが機械的に確認済みで、
歯の無い case ではありません。

この軸を足してから、**さらに 3 件**（#19 の 2 件と #20）出ました。
軸として払い出す価値はここにあります —— 1 件目を手で書いた時点では
「computed read の receiver」しか見えておらず、write 側と
destructuring 側は思いついていませんでした。

### 17. class の field 注釈が lowering で消えていた（parser / bundle）

computed key の read を通す receiver 側の証明は「宣言型が keyed
container」でした。ところが最小の形で通りません。

```ts
class Table {
  #rows: Record<string, string> = {};
  put(k: string, v: string): void { this.#rows[k] = v; }
  read(k: string): string | undefined { return this.#rows[k]; }
  unused(): number { return 99; }      // 落ちない
}
```

理由は lowering です。初期化子を持つ field は constructor への代入に
なるので、`class_method_dce` が見る `NativeClassStmt` の `properties`
は**空**です。注釈は parse 時には有って、そこで捨てられていました。

`TsModuleBlock.class_fields` に `(field 名, 宣言型)` を積むようにして
（private field は brand 名で）、`ModuleNode` 経由で bundle 全体分を
pass に渡します。per-module emit 経路でも graph 全体から集めます ——
ある module の computed read は、別の module で宣言された class の
member を名指しし得るので、証明も全体から組む必要があります。

同時に、注釈が無い binding のための container 推論を
`container_vars.mbt` として追加しました。`numeric_vars.mbt` と同じ形の
fixed point で、promote は証明があるときだけ。

| 形 | 根拠 |
| --- | --- |
| `[]` / string literal / template literal | 見たまま |
| `x \|\| y`、`x ?? y`、`c ? x : y` | **両辺**が container のときだけ（`foo \|\| []` の `foo` が object なら container ではない） |
| `await x` / `x!` | 内側 |
| `Promise.all(…)` / `Promise.allSettled(…)` | 常に array。bundle 自身が `Promise` を宣言していたら降りる |
| `s.match(…)` / `s.split(…)` / `s.matchAll(…)`（`s` が `string`） | array か `null`。`null[k]` は method が有っても無くても throw するので、名前は観測されない |
| `this.f` | bundle 内の**全 class** が `f` を container と宣言しているとき |
| alias | `type MatcherMap<T> = Record<string, Matcher<T>>` は綴りが違うだけの `Record`。型引数は代入しない —— 訊いているのは最も外側の形で、それは引数に依存しない |
| inline index signature | `{ [key: string]: Pattern }` は `Record<string, Pattern>` と同格 |
| container だけの union | どちらの arm でも container |

`this.f[k]` も receiver として認めます（`this.#matchers[method]`）。

hono では 18 個の sink のうち 6 個が消えました。残るのは関数の返り値型
からの推論が要るもの（`const { groups } = extractGroupsFromPath(…)`）と、
原理的に無理なもの（`req[cacheKey]`）です。

### 16. 解決できない relative import が compile 全体を落とす（CLI / bundle）

`checker.ts` を `--minify --fold` に通すと出力が 1 byte も出ず、exit code は
0 でした（`--fold` は `--bundle` を含むので import graph を歩きます）。

```
mtsc: read error _build/real-world/checker/_namespaces/ts.performance.js:
      No such file or directory
```

`checker.ts` は `./_namespaces/ts.js` / `ts.moduleSpecifiers.js` /
`ts.performance.js` を import します。**これらは build 生成物で、
repository には無い** file です。source checkout を直接 minify するという
target の性質上、これは異常ではなく普通の状態です。

bare specifier（`react` など）は最初から「vfs に無ければ external として
そのまま emit」でした。relative specifier にその経路が無かっただけです。
今は CLI が実 filesystem に問い合わせて 1 行報告し、bundler 側は
`allow_unresolved_imports` が立っているときだけ verbatim に残します。
vfs だけで動く呼び出し元は厳格なまま —— `./mising` の typo は今も error
です（`bundle: missing module fails with a clear error` がそれを守ります）。

checker.ts は 3,065,627 → **1,542,261 byte**（50% 減）で通り、出力は
parse します。以前の記録（1,535,419）より少し大きいのは、3 つの import が
verbatim に残るからで、そちらが正しい出力です。

### 15. `--explain-mangle` が method DCE について何も言わなかった

`--explain-mangle` は property 予約・declined parameter・dead field・
discriminant tag を説明していましたが、**class-method DCE については
無言**でした。呼ばれていない feature が残っていても、pass を読むしか
理由を知る方法がありませんでした。

新しい section は、scan が出会った sink を重複排除して**頻度順**に並べ、
gate が通っていたら落ちていた method を列挙します。どちらも rewrite が
使う `accessed` と同じ scan から出るので、説明と判定がずれません
（`escape_breakdown` と同じ規律）。説明時は top-level statement の loop
だけ short-circuit を外します —— これで bundle 全体で 1 つではなく
module ごとに 1 つ理由が集まります。

同時に numeric 推論の精度も 2 つ直しました。`number` / `int` 注釈は
それ単独で証明になります —— parameter には walk する def が無いので
これが唯一の証明で、しかも closure capture guard より優先します
（注釈に反する write は TypeScript が認める write ではありません）。
name 単位への射影は「その名前が unique なとき」ではなく
「**その名前を持つ binding が全部 numeric なとき**」で通します ——
`i` はどんな実 bundle でも十数個の function で宣言され、そのほぼ全部が
numeric です。

### 測った: application では 25% 効く

`examples/minify-app`（5 module 301 行、entry に `export` 無し）。
両者とも同じ **未 minify bundle** を入力にするので、bundler ではなく
minifier 同士の比較になります。

| variant | bytes | gzip | 挙動 |
| --- | --- | --- | --- |
| `--bundle`（未 minify） | 6,242 | 1,940 | baseline |
| mtsc `--minify --mangle` | 3,413 | 1,388 | 一致 |
| mtsc `+ --mangle-properties` | **2,561** | **1,134** | 一致 |
| terser `--compress --mangle` | 3,450 | 1,366 | 一致 |
| terser `+ --mangle-props` | 2,101 | 1,153 | **出力が違う** |

- **安全な property mangling が identifier mangling の上に 25%**
  （3,413 → 2,561、gzip では 18%）。React では 0 byte でした。
  同じ flag・同じ compiler で結果が正反対になり、違いは target の形
  だけです。
- **terser の既定より 26% 小さい**（2,561 対 3,450、gzip 17%）。terser は
  安全だと言われない限り property を rename できないので、既定では
  1 つも触りません。
- **terser の unsafe 版は raw では小さいが答えを間違えます** ——
  `actors=0 rejected=1206`（正しくは `actors=17 rejected=4`）。入力データの
  field 名を rename したせいで、`candidate[key]` という computed key
  経由で読む validator が全行を弾きました。`--explain-mangle` が予約
  すると言っていたのはまさにその名前です。
- **gzip 後は安全版（1,134）が unsafe 版（1,153）より小さい。** 全部を
  rename するより、少なく一貫して rename するほうが圧縮が効きます。

`--explain-mangle` の出力:

```
  enabled — no wildcard; only the names below are reserved.

  read off an external import or ambient global (3)
    log round MAX_SAFE_INTEGER
  reaches a side-effect sink (6)
    length eventId eventKind actorHandle occurredAtMs payloadBytes
  reachable through an observed value tree (4)
    eventKind peakBytes occurrences averageBytes
```

`trustScore` / `burstFactor` / `volumeRank` / `flagged` / `byteTotal` /
`firstSeenMs` / `displayLabel` / `volumeWeight` などは到達不能と証明
されて rename されています。

### framework 型の library は構造的に無理

hono の wildcard 原因を全部見ると 50 件あり、`valueIndex` / `keyIndex` /
`start` / `end` のような明らかな primitive も混じっていますが、残りは
`c` / `req` / `res` / `context` / `next` / `handlerData` —— **Hono の
Context と Request そのもの**です。

これは精度の問題ではありません。web framework の仕事は、自分の object を
**利用者が書いた handler に渡すこと**です。handler は解析対象の外にある
callee なので、door 2 は定義上開いています。どれだけ解析を精密にしても
閉じません。

つまり property mangling の適用可否は「library か app か」ではなく、
**自分の object を外部の code に手渡す設計かどうか**で決まります。

| 形 | property mangling |
| --- | --- |
| application（公開 API 無し） | 効く（実測 25%） |
| 内部が閉じた library | 効きうる |
| framework（callback に自分の object を渡す） | **構造的に不可** |
| 動的 dispatch（`Proxy` / quoted property） | **構造的に不可** |

hono で `--mangle-properties` が 6.4 KB 効いたのは、user の property 名では
なく mtsc が合成した `#private` field の brand（`__private_brand__N__X`）を
rename した分です。wildcard が立っていても内部 marker だけは安全に
rename できる、という fallback 経路が働いています。

### hono の「使わない機能」は落ちるのか

property mangling とは別に、**使わない feature 自体を落とせないか**を
測りました。hono を library として bundle するのではなく、**1 route だけの
application を entry にして**bundle します。

```ts
// app-entry.ts
import { Hono } from './src/index.ts';
const app = new Hono();
app.get('/', (c) => c.text('root'));
const res = await app.fetch(new Request('http://x/'));
console.log(res.status, await res.text());
```

`--bundle --minify --mangle --mangle-properties --treeshake --fold`:

| entry | 出力 | gzip |
| --- | --- | --- |
| `src/index.ts`（library 全体） | 18,097 | 7,398 |
| `app-entry.ts`（1 route だけの app） | **18,196** | 7,431 |

**1 byte も減らず、99 byte 増えました。**（app は正しく `200 root` を
返します。増分は app 自身の code です。）`c.text` しか呼ばない app が、
`parseBody` / `queries` / `blob` / `Hono.route` / `Hono.mount` まで全部
抱えています。

原因は 1 つに絞れました。unused class-method DCE の gate です。
`--explain-mangle` に section を足したので、名前で出ます。

```
unused class methods: what was dropped and why not

  SUPPRESSED — a sink in the bundle can observe a member name the pass
  cannot spell out, so every class keeps every method.
  sinks, most frequent first:
    [x2] `form[key]` reads a member under a computed key that is neither
         provably numeric nor an entry of a keyed container, …
    [x2] `groups[i]` …
    [x1] `middleware[i]` …
    [x1] `patternCache[cacheKey]` …
    [x1] `matchers[method]` …
    [x1] `req[cacheKey]` …
    … and 6 more distinct sink shape(s).
  would have dropped 26 unreached method(s):
    HonoRequest.param / query / queries / parseBody / json / bytes /
    blob / addValidatedData / valid / matchedRoutes / routePath
    Context.event / var
    Hono.route / mount
```

18 個の distinct sink があり、**全部が同じ種類**――computed key での
member read です。1 つでも残れば bundle 全体で pass が止まります。
下の #17 の精度改善で 6 個潰して 12 個になりました（潰すたびに、同じ
statement 内で隠れていた次の sink が出てくるので、報告される数は
その分戻ります）。

落ちるはずだった 26 method の本体は、未 minify の 46,964 byte 中
3,448 byte。ここが消えれば `_getQueryParam`(1,909) / `parseFormData`(594) /
`parseBody`(447) / `bufferToFormData`(248) / `getQueryParams`(69) も
treeshake で連鎖して消えるので、未 minify で **7 KB 前後（15%）**、
minify + mangle 後で **2〜2.5 KB（11〜14%）**の見込みです。無視できる量では
ありません。

では 18 個を潰せるか。receiver の宣言を 1 つずつ見ると、3 層に分かれます。

| 層 | 例 | 状況 |
| --- | --- | --- |
| 注釈が届く | `patternCache: { [key: string]: Pattern }`、`this.#matchers[method]`（`type MatcherMap<T> = Record<string, …>`）、`await Promise.all(buffer)` | **この作業で通した**。下の #17 |
| 注釈が届かない | `const { groups } = extractGroupsFromPath(…)`、`const form: BodyData = …` の連鎖、`this.#tries[method]` | 関数の返り値型からの推論と、name 単位の集約をやめた scope 解決が要る（`i` は bundle 内に十数個あり、注釈なしの `forEach((list, i) =>)` が 1 つあるだけで全部の `i` が失格する） |
| 原理的に無理 | `req[cacheKey]`、`headers[…]`、`this.#matchResult[…][…][key]` | **本物の動的 member read**。host object から計算した名前で member を引いている。どんな解析でも key を bound できない |

3 層目が残るので、**hono の app bundle は member 単位の DCE では縮みません**。
property mangling が構造的に不可なのと同じ結論に、別の経路で到達します。
片方は「自分の object を外部に渡すから」、もう片方は「自分の member を
計算した名前で引くから」です。

得られたものは 2 つあります。第一に、gate が「何を観測できるか」で
判定するようになったこと（下の #14 と #15）。第二に、`--explain-mangle`
が**落ちなかった method と、その理由になった pattern を頻度順に**出すので、
次に何を直せば効くかが推測ではなく計測になったことです。

### 何を target にすべきか

効く順に。

1. **library ではなく application。** app には公開 API が無いので door 1 が
   ほぼ空になります。上の実測がこれです（`examples/minify-app`）。
2. **内部 dispatch が静的な TS library。** `Proxy` を使わない、
   `Object.defineProperty` を使わない、`obj[dynamicKey]` を使わない、
   quoted property 経由で呼ばない。zod と valibot を落としたのは
   この条件です。
3. **注釈された object 内部を持つもの。** mangle する対象があること。
4. **公開面が狭いもの。**

そして screening は 1 コマンドで済みます。

```sh
mtsc <entry.ts> --bundle --explain-mangle --out /dev/null
```

`SUPPRESSED` なら、その下に**どの binding が原因か**が名前で出ます。
target 候補が使えるかどうか、使えないなら何を直せば使えるかが、
これで分かります。

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
- 6 と 7 は **flag の組み合わせ**が要る。`--mangle` 単体でも `--minify`
  単体でも正しく、両方で壊れます（7 に至っては、畳み込み自体が
  post-mangle の block でしか発火しません）。2 も同じ性質でした
  （`--fold` と `--minify`）。この形の bug は、pass を 1 つずつ検証する
  test では原理的に出ません。
- 7 は **意味のある入力を意味のある形で実行する**ことが要る。crash も
  しないし、valid な JS でもあるし、型検査も走って本物のエラーも見つける
  ——ただし答えが違う。「動いた」で止める検証では通ってしまいます。

そして 3 段の gate のうち、どこで捕まったかが段ごとに違います。

| gate | 捕まえた bug |
| --- | --- |
| compile が通るか | 1（parse できない） |
| 出力が有効な JS か（`node --check`） | 2、3 |
| load して動くか | 6（`ReferenceError`） |
| **出す答えが同じか** | **7（静かに間違う）** |
| 実 package の観測が一致するか | 4、5 |

段が下に行くほど、上の段では見えないものが出ます。6 の時点で
「`node --check` を通っても正しいとは限らない」でしたが、7 はさらに先で、
**load できて、実行できて、型検査も走って、本物のエラーも見つけて、
それでも答えが違う**という形でした。これを捕まえられるのは
「minify した compiler で実際に compile して診断を比べる」leg だけです。

そして 7 の副産物として、6 の修正で出力が 2,236,316 → 3,581,914 bytes に
増えました。差の **1.35 MB は削除されていた function 宣言**です。
「よく縮んだ」は「正しく縮んだ」でもありません。
