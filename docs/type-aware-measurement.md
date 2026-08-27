# 型情報は何バイト効いているのか

`--mangle-properties` の安全性は 4 つの harness で検査してあります。
効果を測ったものは一つもありませんでした。「type-aware minify」を名乗る
以上、**型を知っていることが実際に何バイトになるのか**は測れる質問です。

```sh
node scripts/measure_type_aware.mjs
node scripts/measure_type_aware.mjs --only hono --verbose
node scripts/measure_type_aware.mjs --update      # expected.json を再記録
```

## なぜ公開版の .js では測れないか

型を読んでいる phase は `src/transform/bundle.mbt` に 6 つあります。

| phase | 読んでいるもの |
| --- | --- |
| `predicate-inline` | `x is T` の型述語 |
| `switch-fold` | 閉じた string literal union の param 型 |
| `as-const-inline` | `as const` |
| `tag-rewrite` | discriminated union（`combined_type_aliases`）|
| `class-method-dce` | `combined_class_fields` + `combined_type_aliases` |
| `type-fold` | primitive の型注釈 |

これらが読む `combined_type_aliases` / `combined_interfaces` /
`combined_class_fields` は、**parse した TypeScript module** から
bundler が詰めています。公開済みの `.js` を渡すと 3 つとも空のままで、
6 つのうち 1 つも発火できません。つまり `verify-real-world` が
`typescript.js` や `react` で測っているものは、定義上ゼロです。

だから corpus は git から**ソースを clone** します。

## 測り方

同じ flag で 2 回最適化し、**入力の形だけ**を変えます。

| leg | 何 |
| --- | --- |
| `unopt` | `mtsc <entry.ts> --bundle` — TS in / plain JS out、最適化なし。サイズの分母かつ挙動の基準 |
| `aware` | `mtsc <entry.ts> --bundle --treeshake --fold --minify --mangle` — 注釈があるので 6 phase が発火できる |
| `blind` | `mtsc <unopt.mjs> --bundle …同じ flag` — 型を消した同じコード。型 table は全部空。これが公開 `.js` の状況 |

`delta = blind - aware`。正なら型情報が効いています。

`--no-check` は全 leg で有効です。これは**診断だけ**を飛ばします——実際の
library は subset checker を通りませんし、6 phase が読む型 table は check
ではなく parse から来るので、leg の差は入力の形だけになります。

### 引かないといけない分

`blind` の入力は一度 emit を通っているので、`blind` は `aware` にはない
**2 回目の最適化**を受けています。2 回目は 1 回目の取りこぼしを拾うので、
これは型とは無関係な下駄です。`aware2` leg が `aware` 自身の出力を
再最適化してその分を値付けし、`--verbose` が両方を出します。

### 信用の条件

3 つの leg が driver に対して**同一の観測**を出すことが条件です
（`fixtures/type-aware-corpus/*.driver.mjs`）。bundle がそもそも動かない
target は `size-only` と理由付きで報告されます。誰も実行できない byte 数は
証拠ではありません。

## 結果

`--mangle-properties` は**外してあります**。ここで測った library では
どれも完全に不発で（fail-closed な callee-provenance scan が
bundle 内と証明できない call を見つけて全部 reserve する）、
付けても両 leg で 1 byte も動かず実行時間だけ伸びます。
**実際の library に対して property mangler が動いていない**という事実
自体が、この harness が出した一番大きな発見です。

型情報の寄与は library によって符号が変わります。hono では効き、
valibot と immer では実質ゼロ、typebox では**マイナス**です。
最新の数字は `fixtures/type-aware-corpus/expected.json` にあります。

## corpus に入れられなかったもの

9 個試して測れるようになったのは 8 個です（うち 2 個は bundle が
動かないので `size-only`）。残り 1 個は表に `BLOCKED` として残してあります——理由が finding であり、理由が消えた日に
そのまま measurement になるからです。

| target | 状態 | 理由 |
| --- | --- | --- |
| hono | measured | — |
| valibot | measured | — |
| neverthrow | measured | 元 BLOCKED。export-surface の memo で 420s 未完 → 1 秒未満 |
| ts-pattern | measured | 元 BLOCKED。同上。ただし `P` が bundle に無い（下記）|
| zod | measured | 元 BLOCKED。4 件の修正を経て挙動検証まで到達（+1,096 bytes / +0.61% の WIN）|
| superstruct | measured | 元 BLOCKED → 15ms、さらに元 BROKEN → 挙動一致（下記の `.name` reserve）|
| typebox | size-only | `TTypeArray` は解消。今は別件の TDZ で throw: `IntegerKey` の宣言が使用より後に並ぶ |
| immer | size-only | bundle が load で throw: module 跨ぎの `const enum ArchType` が emit も inline もされない |
| remeda | BLOCKED | `setPath.ts` の parse error: `Expected Semicolon, got Extends` |

### 原因の取り違えを 2 回やった

「戻ってこない」4 target に対して、**gdb sample 1 回で原因を決めつけた**のが
2 回とも間違いでした。

1 回目: 4 つ全部を export-surface の blowup に帰した。直したら 2 つしか
該当しなかった。

2 回目: 残り 2 つのうち superstruct を sample したら
`parse_conditional_type_tail` の中にいたので「再帰的 conditional type の
parser blowup」と書いた。**違います**。parser の中にいたのは、
parser が指数的に再入されていたからでした。

3 つ目の原因が本命で、これが 4 target すべての残りを説明します。

### 直したもの 1: export-surface の blowup

`--bundle` **だけ**でも再現します（最適化 flag は要りません）:
`bundle.mbt:1102` の非最適化パスが `exported_surface_props` を
無条件で呼んでいます。

`surface_escape_expr` には `SURFACE_MAX_DEPTH`（96）の深さ制限が
ありますが、**class は memo されていませんでした**。`new C(…)` が N 箇所
あれば class は N 回 escape され、その都度全 method の return を walk し、
そこから更に `new` に届く——call graph の分岐に対して指数的で、96 の cap
では全く抑えられません。加えて `class_this_writes` は呼ばれるたびに
scratch walk を作り直して constructor と全 method body を walk しなおします。

`surface_should_walk` がこれを抑えます。memo は once-only ではなく
**深さ**で keying してあります: 深いところで先に truncate された walk が
key を取ってしまうと、後から浅く到達した経路が skip され、その先の名前が
**under-reserve** される——つまり rename されて consumer が壊れる。
浅い到達は再 walk します。

| | before | after |
| --- | --- | --- |
| neverthrow | 420s 未完 | 1 秒未満 |
| ts-pattern | 100s 未完 | 0s |

reserved set が縮んでいないことは mangle-safety 162/162 が変わらないこと、
および `export_surface_wbtest.mbt` の「3 経路から届く class の surface が
全部残る」test で確認しています（`new` から class を walk しないよう
mutate すると 5 test が落ちます）。

深さ次元そのものは test で覆えていません。once-only に mutate しても
どの test も落ちません。区別する case を作るには `SURFACE_MAX_DEPTH`
より深くネストした式が必要で、そのサイズだと walk 自体が病的になり、
実際 test suite が 10 分を超えました。再 walk は名前を**増やす**方向
なので保守的側であり、既存の `fn:` memo は once-only だったので、
どちらにしてもこれは安全側の変更です。

### 直したもの 2: module graph の walk が指数的だった

`mtsc_load_bundle_files` は**module が書いた specifier** で dedup して
いました。1 つの file に解決する 2 つの綴りに対して、それは同じ問いでは
ありません。

| specifier | 解決 | dedup |
| --- | --- | --- |
| `'./util'` | `util.ts` | 拡張子を**足した**ので拡張子なしの key も張られ、2 回目は捕まる |
| `'./util.js'` | `util.ts` | 拡張子を**置き換えた**。alias は張られず、何も dedup しない |

後者は TypeScript-with-NodeNext のソースが書く形です。dedup が効かないと
再訪ごとに file を読み直し、parse し直し、自分の import を再 push し、
それがまた再訪する——**diamond graph では 2^depth**。

合成した chain（各 module が次段の 2 module を両方 import）で測った値:

| depth | `.js` specifier | 拡張子なし |
| --- | --- | --- |
| 4 | 9ms | 8ms |
| 6 | 19ms | 8ms |
| 8 | 61ms | 8ms |
| 10 | 217ms | 9ms |
| 12 | 853ms | 11ms |

2 段ごとに約 4 倍 対 ほぼ平坦。zod は `from "../core/util.js"` を
133 file 中 65 回書いており、hono と valibot は拡張子なしなので
最初から問題ありませんでした。zod の個別 file は 11〜167ms で parse
できるので、parser 自体は何も悪くありませんでした。

修正は解決後パスでの guard 1 つです（alias の書き込みは dedup 経路でも
保持してあり、link が壊れないようにしています）。

| | before | after |
| --- | --- | --- |
| zod | 18 分以上未完 | 227ms |
| superstruct | 150s 未完 | 15ms |

gate は `just verify-graph-walk`（`ci` に入っています）。合成 chain を
生成して、**2 つの深さの間の伸び率**を見ます——ミリ秒ではなく比なので
閾値がマシン速度に依存しません。bundle が正しい値を出すことも確認します
（dedup guard はまさに module を落としうる変更なので）。

### 直したもの 3: arrow の body が `{` で始まるときの括弧

zod の bundle は上を直した後も load で落ちました。

```js
(self) => {...standardProps(self), jsonSchema: {…}}   // SyntaxError
```

source はこうです。

```ts
"~standard": (self) =>
  ({ ...core.standardProps(self), … }) as ZodType["~standard"],
```

arrow の式 body が `{` で始まるなら括弧が必要です。その判定が
`ObjectLit` と、それを包む postfix 3 種を**手で並べた表**になっていて、
`as` / `satisfies` / `!` はそこに載っていませんでした。型注釈は
消えるので、消した後に `{` が露出します。

判定を `expr_starts_with_brace` に置き換えました。中身は
`expr_leading_byte`——emitter が空白を決めるのに使っている同じ表——なので、
2 つの表が食い違うことがありません。同時に、消える wrapper
（`as` / `satisfies` / `!`）と、左オペランドから emit が始まる演算子
（`BinOp` / `Cond` / `Seq` / 複合代入）も表に足しました。1 つの arm では
なく family を閉じたつもりです。

test は 11 の形（素、assertion 3 種、2 段重ね、postfix、演算子の左、
wrapper と演算子の入れ子）と、括弧が**不要**な 8 形の両方を見ています。
assertion を再び opaque に mutate すると落ちます。

### ついでに見つかったもの: alias 付き re-export が落ちる

ts-pattern の entry は

```ts
import * as Pattern from './patterns';
export { Pattern, Pattern as P };
```

と書いていますが、bundle の export は
`export { match, isMatching, NonExhaustiveError }` だけです。
**別 module から束縛された名前を alias 付きで re-export すると、
両方の綴りが落ちます**。`P` は ts-pattern の API の半分なので、これは
実用上致命的です。

driver は bundle が実際に出している export の範囲に留めてあり
（`P` を使わない）、この件は独立した bug として残しています。

### 直したもの 5: class 名が観測される（corpus が見つけた実挙動の差）

superstruct が **BROKEN** でした。`error.ts:44` の
`this.name = this.constructor.name` に対して `--mangle` が class 名を
rename するので、`e.name` が `"StructError"` ではなく `"a"` になります。

terser も esbuild も既定で class 名を rename し（`keep_classnames: false`）、
`.name` を読む library 側が opt out する前提です。ここは逆側を取りました。
**read がソースに見えている**からです——見えているなら、bundle 全体で
正しさとバイトを交換する必要はなく、実際に観測されている名前だけ払えます。

`src/transform/observed_names.mbt`。receiver で 3 通りに分けます。

| receiver | 答え |
| --- | --- |
| `C.name` / `C["name"]` | `C` だけ reserve |
| `this.constructor.name`（class body 内）| その class と**その subclass 全部**を reserve |
| それ以外の `x.constructor.name` | `this` が制約されないので、callable 全部を reserve（fallback）|

#### narrowing を 3 段試して、階層だけが効いた

最初は `.constructor.name` を見たら top-level binding を全部 reserve
しました。corpus が値段を出しました: **typebox +70%、zod +40%、
superstruct +31%**。既定にできる数字ではありません。

次に「class と function だけ」に絞りました。**1 byte も変わりませんでした**
——top-level callable で書かれた library では、それは同じ集合です。

効いたのは**型情報**です。`C` の method 内の `this.constructor` は
`C` かその subclass であって、無関係な class では絶対にありません。
これで superstruct は `StructError` 1 個だけの reserve になります。

| target | pass 前 | 全 top-level | class+function | 階層 |
| --- | --- | --- | --- | --- |
| superstruct | 10,677 (BROKEN) | 13,993 | 13,993 | **10,702 (+25 byte)** |
| typebox | 95,093 | 162,047 | 162,047 | 126,884 |
| zod | 180,260 | 251,868 | 251,868 | 200,335 |

#### 残るコストと、その理由

8 target のうち **6 つは 25 byte 以下**（hono / immer / neverthrow /
ts-pattern が 0、valibot が +15、superstruct が +25）。

残る 2 つは fallback を踏みます。実際に `this` 以外で読んでいます。

```ts
// zod
throw new core.$ZodEncodeError(inst.constructor.name);
fn.constructor.name === "AsyncFunction"
// typebox
globalThis.Object.getPrototypeOf(left).constructor.name
IsEqual(proto.constructor.name, 'Object')
```

zod +11%（180,335 → 200,335）、typebox +33%。

**まだ narrowing の余地があります**（未実装）。上の 4 例のうち 2 つは
結果を**組み込みの名前**（`"AsyncFunction"`、`'Object'`）と比較して
いるだけで、bundle 内の class 名は無関係です。string literal との比較に
しか使われていない `.constructor.name` は、どの bundle 名も観測しません。
もう一段は parameter の型注釈を読むことです（`inst: $ZodType` なら
候補はその型の実装 class に限られる）。

#### 穴（明記）

`foo().name`（`foo` が class を返す）と `bag.ctor.name` は捕まえられません。
任意の式の評価結果を知る必要があるからです。`.name` read をすべて危険と
みなす選択肢はありません——`err.name`、`req.name`、`{name:…}.name` は
どこにでもあり、ほぼ全 bundle の top-level を reserve することになります。
**class 名を無条件に rename するより厳密で、証明ではありません。**

## 残っている既知の未修正

| 件 | 症状 |
| --- | --- |
| alias 付き re-export | `export { X as Y }`（別 module 由来の X）が両方の綴りごと落ちる。ts-pattern の `P` |
| top-level の TDZ | typebox の bundle が `Cannot access 'IntegerKey' before initialization`。`const` の宣言が使用より後に並ぶ |
| module 跨ぎの `const enum` | immer の bundle が `ArchType is not defined` で load 失敗 |
| remeda の parse error | `setPath.ts`: `Expected Semicolon, got Extends` |
| property mangler が実 library で不発 | fail-closed な callee-provenance scan が全部 reserve する |

### 直したもの 4: namespace object に型専用 export が入る

`export * as ns from './m'` は対象の export 1 つごとに property を並べますが、
型専用の export には指す先がありません。`{OnlyType: OnlyType, …}` を emit して
load 時に `ReferenceError` になっていました。typebox の `TTypeArray` と
zod の `JSONType` は同一原因です。2 file で再現します。

```ts
// m.ts
export type OnlyType = { a: number };
export const value = 1;
// index.ts
export * as ns from "./m.js";
```

enumeration site で filter する方針が**収束しませんでした**。site は 3 つ
（namespace 自身の `export_specs`、`import * as` 経路、
`enumerate_wildcard_reexports`）あり、zod が到達経路ごとに順番に
見つけてきました——`$constructor`、`$ZodBranded`、`$RefinementCtx`。
corpus が文句を言うたびに次の site を patch するのは間違ったループで、
2 個目で気づくべきでした。

filter は残しつつ（正確で安く、object を小さく保つ）、効く checkを
**object を組み立てる 1 箇所**に移しました。`synthesize_namespace_bindings_for`
が、値が bundle のどの binding も指していない entry を落とします——
どの経路で入ったかに関係なく。enumeration ではなく構成上 fail-closed です。

判定に使う `runtime_bindings` は linker の rename phase 後に 1 回だけ
計算します（名前が最終形になっている）: 各 module の top-level 宣言を
その module の rename を通したもの、加えてこの pass 自身が synthesize する
namespace object（namespace は namespace を持てる）。

test は型 filter が**原理的に**覆えない経路を使っています——
`import { T } from "./types"; export { T }`（両端に `type` なし）で、
module は `T` を何も宣言しないので keying する型宣言が存在しません。
backstop を無効化すると `Ghost: Ghost, real: real` が出て test が落ちます。

副作用として、declaration merging（`export interface $constructor` と
`export function $constructor` が同居）で値を落とす bug も出ました。
名前だけを見る filter では両方消えます。型宣言があること **かつ**
同名の runtime binding が無いこと、の両方を要求するようにしました。
