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

型情報の寄与は target によって符号が変わります。最新の数字は
`fixtures/type-aware-corpus/expected.json` にあります。現時点:

| target | files | unopt | aware | blind | delta | 判定 |
| --- | --- | --- | --- | --- | --- | --- |
| hono | 188 | 63,192 | 22,349 | 22,355 | +6 | NEUTRAL |
| valibot | 828 | 228,307 | 88,768 | 88,768 | 0 | NEUTRAL |
| typebox | 692 | 380,972 | 123,124 | 119,460 | −3,664 | LOSS |
| immer | 17 | 49,809 | 20,826 | 20,826 | 0 | NEUTRAL |
| neverthrow | 5 | 9,991 | 5,166 | 5,166 | 0 | NEUTRAL |
| ts-pattern | 18 | 20,365 | 5,795 | 5,795 | 0 | NEUTRAL |
| superstruct | 8 | 20,785 | 10,690 | 10,552 | −138 | LOSS |
| zod | 133 | 648,647 | 200,320 | 200,141 | −179 | NEUTRAL |
| excalidraw | 95 | 788,070 | 280,297 | 279,994 | −303 | LOSS |

**WIN が 0 件です。** 一つ前の記録では hono が +500、zod が +788 の WIN
でした。両方消えたのは測り方を変えたからではなく、**その WIN の一部が
不健全な解析の産物だった**からです。理由は下の `TypeArgs` の節にあります。
要約すると、`f<T>(x)` は `TypeArgs` wrapper として parse され、
19 個の pass がこの wrapper を剥がしていなかったので、その中にある参照は
**liveness から見えていませんでした**。見えない参照は死んだ参照なので、
`aware` leg は生きているコードを削っていました。そして
`TypeArgs` は型を消した JS には**存在しない**ので、この不健全さは
type-aware 経路だけのものでした。直すと aware leg が hono で +494 byte
太り、WIN が消えました。

## corpus に入れられなかったもの

10 個試して測れるようになったのは 9 個です（うち 2 個は bundle が
動かないので `size-only`）。残り 1 個は表に `BLOCKED` として残してあります——理由が finding であり、理由が消えた日に
そのまま measurement になるからです。

| target | 状態 | 理由 |
| --- | --- | --- |
| hono | measured | — |
| valibot | measured | — |
| neverthrow | measured | 元 BLOCKED。export-surface の memo で 420s 未完 → 1 秒未満 |
| ts-pattern | measured | 元 BLOCKED。同上。ただし `P` が bundle に無い（下記）|
| zod | measured | 元 BLOCKED。4 件の修正を経て挙動検証まで到達 |
| excalidraw | measured | corpus 唯一の UI アプリかつ唯一の monorepo。bundle できるまでに 5 件、実行できるまでに 3 件（下記）|
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

| target | pass 前 | 全 top-level | class+function | 階層 | 階層 + constructor 限定 |
| --- | --- | --- | --- | --- | --- |
| superstruct | 10,677 (BROKEN) | 13,993 | 13,993 | 10,702 | **10,690 (+13 byte)** |
| typebox | 95,093 | 162,047 | 162,047 | 126,884 | 123,172 |
| zod | 180,260 | 251,868 | 251,868 | 200,335 | 200,325 |

#### 「精密な側は無料」は間違いでした

corpus の 8 target だけを見て、`C.name` → `C` を reserve する側は
ほぼ無料だと報告しました。**間違いです。9 MB の typescript.js で
282 KB（7.9%）かかりました。**

原因はコメントに書いて自分で正当化した判断です。`.name` の左にある
識別子を、**それが constructor かどうか確かめずに** reserve していて、
「plain object の `.name` なら数バイトの損」と書いていました。
typescript.js には `constructor.name` が**1 つもありません**。あるのは
`node.name` / `symbol.name` / `declaration.name` が数千回で、
`node` / `symbol` / `declaration` を reserve するとコンパイラで最も
頻出する局所名が丸ごと mangle されなくなります。

反対側の branch 用に既に集めていた constructor 宣言と intersect して
修正しました。typescript.js は 3,588,243 byte——pass 導入前と**同一**に
戻りました。

corpus の 8 target はこの種のコストを 1 つも露出させませんでした。
real-world の 9 MB target が一発で出しました。

#### 残るコストと、その理由

8 target のうち **6 つは 25 byte 以下**（hono / valibot / immer /
neverthrow / ts-pattern が 0、superstruct が +13）。

残る 2 つは fallback を踏みます。実際に `this` 以外で読んでいます。

```ts
// zod
throw new core.$ZodEncodeError(inst.constructor.name);
fn.constructor.name === "AsyncFunction"
// typebox
globalThis.Object.getPrototypeOf(left).constructor.name
IsEqual(proto.constructor.name, 'Object')
```

zod +11%（180,260 → 200,325）、typebox +30%（95,093 → 123,172）。

**まだ narrowing の余地があります**（未実装）。上の 4 例のうち 2 つは
結果を**組み込みの名前**（`"AsyncFunction"`、`'Object'`）と比較して
いるだけで、bundle 内の class 名は無関係です。string literal との比較に
しか使われていない `.constructor.name` は、どの bundle 名も観測しません。
もう一段は parameter の型注釈を読むことです（`inst: $ZodType` なら
候補はその型の実装 class に限られる）。

#### 穴（明記）

`foo().name`（`foo` が class を返す）と `bag.ctor.name` は捕まえられません。
任意の式の評価結果を知る必要があるからです。top-level ではなく
関数本体の中で宣言された class の `C.name` も同様です（caller が持つ
constructor 表が top-level + nested block までなので）。
`.name` read をすべて危険と
みなす選択肢はありません——`err.name`、`req.name`、`{name:…}.name` は
どこにでもあり、typescript.js が示した通り 282 KB の代償になります。
**class 名を無条件に rename するより厳密で、証明ではありません。**

## Excalidraw: library ではないものを入れて分かったこと

ここまでの 9 target は全部 library でした。UI アプリケーションを
1 つ入れると、library では一度も踏まなかった穴が並んで出てきました。
対象は `packages/element`（52 file / 1 MB の TS）ですが、
import は tsconfig の `paths` 経由で 5 つの sibling package に届き、
bundle は**6 package / 95 module / 788 KB** になります。

見つかったものの内訳: bundle できるまでに 5 件、Node で実行できるまでに
3 件（2 件は Node 側の事情、1 件は harness 自身の bug）、そして
**pass の bug が 3 件** —— `TypeArgs` wrapper（19 file、うち 2 つが
不健全）、export-surface の返り値引数、そして
class-method DCE の scope。最後の 1 件は最適化 flag を 1 つも
付けない path にあり、**基準 leg を壊していました**。

### bundle できるまでに 5 件

| # | 症状 | 原因 |
| --- | --- | --- |
| 1 | `Expected Semicolon, got Colon` | `import percentages from "./locales/percentages.json"` を TypeScript として parse していた |
| 2 | `Expected type, got Star` | `import "./ContextMenu.scss"` を TypeScript として parse していた（`*` selector） |
| 3 | `utf8.Malformed` | asset の判定が**read の後**にあり、`.woff2` を UTF-8 として decode していた |
| 4 | 5 package が external のまま | tsconfig の `paths` が `"extends"` 先の config にあり、追っていなかった |
| 5 | `ERR_UNSUPPORTED_DIR_IMPORT` | `from "."` が relative と判定されていなかった |

1 と 2 は wrapping で解けます。JSON は式の文法の部分集合なので
`export default <document>;` に包めば既存の parser がそのまま読み、
asset は `export default {};` を合成すれば side-effect import は
何も寄与しません（`import styles from "./x.module.css"` に `{}` を
渡すのは CSS-modules の class 名 map ではないので、そこは
**限界であって修正ではありません**）。

3 は順序の問題でした。binary を読んでから「これは asset だ」と気づいても
遅い。path で決めれば font や画像の megabyte をそもそも読みません。

4 は 2 case の probe で切り分けました——`paths` を inline に書けば
INLINED、`extends` 経由なら external。`resolve_tsconfig_specifier_in`
が `"extends"` を深さ 8 まで辿ります（path は宣言した config の
directory 基準）。ここで bundle が 52 module から 95 module に増えました。

5 は `spec.has_prefix("./")` が `"."` に対して false という一行の話です。
`"."` と `".."` は relative specifier であり、package の module が
自分の barrel を指す綴りです。loader はこれを 4 箇所で判定していて
（import / re-export × type-only guard / resolve 分岐）、
2 つの loop は互いの鏡像です——このセッションで何度も刺された形なので、
`@transform.is_relative_specifier` という**述語 1 つ**にしました。
bundler 側（`resolve_relative`）と checker 側
（`is_local_module_specifier`）にも同じ穴がありました。

### 実行できるまでに 3 件（うち 2 件は Node 側の事情）

`roughjs` は `bin/` 以下を**拡張子なし ESM**で publish していて
`exports` map も無いので、`roughjs/bin/rough` は Node では
どう置いても load できません（`bin/rough.js` 自身が `./canvas` を
import している）。vite の resolver が埋めている部分です。
`fixtures/type-aware-corpus/excalidraw.shims/` が 3 つの specifier を
埋め、いずれも**本物の** roughjs を返します——roughjs が `module` として
publish している rollup build 経由です。`import.meta.env` も vite の
build-time 置換なので、driver が立てる global に書き換えます。

どちらも**実行する copy にだけ**適用し、3 leg に同一に適用します。
測った byte 数は無改変の leg 出力から取っています。

3 件目は harness 自身の bug でした。dependency を leg directory に
`npm install` したところ、そこは checkout の**親**であり、
mtsc は bare specifier を importing file から上に辿って解決するので、
`es6-promise-pool` を external ではなく **inline** し始めました。
bundle は 88 KB 太り、UMD の factory が ESM に存在しない `root` に
代入して `Cannot set properties of undefined (setting 'PromisePool')`
で落ちました。`exec/` subdirectory に移して解決——checkout の
祖先ではないので mtsc からは見えません。

### そして本題: `TypeArgs` wrapper が 19 個の pass から見えていなかった

3 leg が動くようになって最初に出た差がこれです。
`aware` leg が load 時に `ReferenceError: CODES is not defined`。
出所は Excalidraw の `packages/common/src/keys.ts`:

```ts
export const CODES = { Z: "KeyZ", Y: "KeyY" } as const;
export const KeyCodeMap = new Map<ValueOf<typeof KEYS>, ValueOf<typeof CODES>>([
  [KEYS.Z, CODES.Z],
  [KEYS.Y, CODES.Y],
]);
```

`CODES` の宣言が消え、参照 2 個が残っていました。**flag 1 つで再現します**
（`--treeshake` だけ）。最小形は 3 行で、効いているのは
`new Map<string, string>(…)` の**明示 type argument** です。これを外すと
起きません。

`f<T>(x)` / `new C<T>(x)` / `o.m<T>(x)` は
`TypeArgs([T], <the call>)` として parse されます。この wrapper は
「`Call` / `New` / `MethodCall` を見ている無数の match site を変えずに
済ませる」ために入っています。その代償が正確にこれでした:
**catch-all を持つ walker は内側の call に fall through しません。
何も見えません。** liveness から見えない参照は死んだ参照なので、
treeshake は宣言を削り、参照を残しました。

`As` / `NonNull` を剥がしていて `TypeArgs` を剥がしていない file が
**19 個**ありました。うち不健全だったもの:

| file | 症状 |
| --- | --- |
| `treeshake.mbt` | 生きている binding の宣言を削除（上記） |
| `dead_props.mbt` | property read が見えず、key が削除されて call が `undefined` を受ける |
| `flow_analysis.mbt` / `sink_catalog.mbt` / `symbol_graph.mbt` | escape / sink 解析の取りこぼし = fail-**open** |
| `class_method_dce.mbt` | reflection gate と static の liveness |
| `inline.mbt` | **use counter**。2 回使われている binding が 1 回に見えれば single-use inline が発火する。しかも substitute 側も降りていなかったので、両方直さないと片方だけ壊れる |
| `bundle_link.mbt` | module 跨ぎの rename。1 箇所だけ rename されない参照が残る |

残りは「最適化の取りこぼし」（安全）でしたが、collector と rewriter が
**片方だけ**降りていると不整合になるので、全部に arm を足しました。

7 つの probe で確認しています（宣言の liveness、property read、
外部 sink への literal、class の型引数、method call、side effect）。
修正前は 5 つが FAIL、修正後は 7 つとも一致します。

**構造的な保証は付けられませんでした。** wrapper を pipeline の
入口で 1 回剥がす案（そうすれば未 audit の pass も安全）は、
剥がす側が全 node を網羅する rewriter になり、そこで 1 arm 落とせば
同じ穴が同じ形で残るので、見送りました。代わりに
`src/ast/types.mbt` の `TypeArgs` 宣言に**この事故そのものを書いて**、
`fixtures/mangle-safety/case40-type-arguments` を追加しました——
6 つの形（binding の唯一の参照、唯一の property read、外部へ escape する
literal、type argument 付き method call、side effect）を
end-to-end で走らせます。**誰も audit していない pass を検査できるのは
これだけです。**

### そのついでに、`case08-typeargs` が偶然通っていたことが分かった

corpus には `case08-typeargs`（packelyze 由来）が最初からありました。

```ts
function identify<T>(v: T): T { return v; }
export const v = identify<X>({ type: "X", payload: { x: "D" } });
```

`TypeArgs` を直したら**これが落ちました**。`payload` と `x` が
削除されるからです。そして型引数を外しても落ちます——つまり
**元から壊れていて**、key を削る pass が wrapper の中に降りていなかった
おかげで生き延びていただけでした。

穴は export-surface 側です。call の結果が escape するとき、walk は
callee の return を escape させますが、`return v` の `v` は
**parameter** なので top-level binding に解決されず、そこで止まります。
引数は callback のときだけ escape させていました。
`surface_escape_returned_args` が、return 式が parameter に
言及している場合にその位置の引数を escape させます
（`return { wrapped: v }` や `return v.rows` も「一部が出ていく」ので
同じ扱いにしています。どの一部かを決めるにはこの pass が計算中の
shape が必要になります）。hono と zod では byte 数が 1 も動きませんでした。

### LOSS の原因を追ったら、基準 leg が壊れていた

最初の測定は aware 280,297 / blind 275,409 で **−4,888 byte（−1.74%）**
でした。「なぜ型を読んでいる方が大きいのか」を追ったのがこの節です。

まず切り分けの 1 段目。tag 比較の出現数（`.type==="arrow"` など）は
**両 leg で完全に同じ**なので、`predicate-inline` が call site に
述語本体を撒いて太らせている、という一番ありそうな筋ではありません。
aware leg は function が 13 個、string literal が 4.4 KB 多い——
つまり**残っているコードが多い**。

そこで `--mangle` を外した 2 leg（名前が保存される）を作って
top-level 宣言の集合を diff しました。aware にだけあるものが 13 個、
blind にだけあるものは 0 個:

```
FRAME_STYLE add clamp$0 distancePointToSegment douglasPeucker mag
norm normAngle plerp rot runLength smul sub
```

`add` / `sub` / `norm` / `rot` / `plerp` / `runLength` /
`douglasPeucker` は全部 `packages/laser-pointer` の内部関数で、
`LaserPointer` の method からしか呼ばれていません。そして blind leg の
`LaserPointer` は `addPoint` / `close` / `getStrokeOutline` を**持って
いませんでした**。call site は残っているので、blind bundle は

```js
element.points.map(([x, y]) => laserPointer.addPoint([x, y, 1]));
return laserPointer.getStrokeOutline().map(…);
```

を method の無いオブジェクトに対して実行します。しかもこの経路は
export された `getFreedrawOutlinePoints` から
`strokeOptions.variability === "constant"` のときに到達します。

さらに悪いことに、これは blind leg の最適化のせいではありませんでした。
**`unopt.mjs` の時点で既に消えていました**——つまり
`mtsc entry.ts --bundle`、最適化 flag 無しの一番素の path です。
5 行 1 flag で再現します:

```ts
// E.ts
export class C { m0() { return 0; } m1() { return 1; } }
// entry.ts
import { C } from "./E";
console.log(Object.getOwnPropertyNames(C.prototype).join(","));
```

`--bundle` → `constructor` だけ。`--bundle --treeshake` →
`constructor,m0,m1`。**最適化を頼んでいない方が消える**という逆転です。

原因は `class_method_dce_block` の contract 違反でした。この pass の
質問は全部 bundle 全体についてのものです——「bundle 内のどこかが
computed key で member を読んでいるか」「どの member 名がどこかで
access されているか」。ところが per-module emit path（opt flag が
1 つも無いときに走る path）は**module を 1 つずつ**渡していたので、
"bundle" が "この module" に読み替わっていました。`state.ts` の中では
`addPoint` を誰も名前で触らないので全 method が消え、gate になるはずの
computed-key sink は全部他の module にありました。

修正は `scope` parameter です。`block` は**書き換える対象**、
`scope` は**解析する対象**。per-module path は graph 全体を lift した
ものを `scope` に渡します。`bundle_wbtest.mbt` の
「a method called from ANOTHER module survives」が 2 file で pin して
います（同時に、どこからも呼ばれない method は今も消えることも
assert しています——解析を広げたのであって pass を止めたのではない）。

直した後の excalidraw は unopt 788,070 / aware 280,297 /
blind 279,994 で **−303 byte（−0.11%）**。**−1.74% の LOSS の
ほぼ全部が、壊れた基準 leg でした。** blind は 8 KB の method が
既に抜けた bundle を最適化していて、その小ささを型情報の差として
計上されていたわけです。

### 「3 leg が一致」は「正しい」ではない

これがこの節で一番残しておきたいことです。壊れた `unopt` は
**reference leg** でした。3 leg すべてが同じ観測を出していたのは、
3 つが同じ bug を共有していたからです。driver が
`strokeOptions.variability === "constant"` を通していなかったので、
消えた method に誰も触らなかった。

corpus の信用条件は「leg 間の一致」であって「正しさ」ではありません。
一致は**同じ入力から作った 3 つの出力が互換であること**しか言わない。
driver に constant-width の line を足したので、この経路は今後
observation で守られます（`fixtures/type-aware-corpus/README.md` に
driver の書き方として明記）。

### 残る LOSS

型を消した方が小さくなる target は typebox（−2.98%、size-only）と
superstruct（−138 byte）と excalidraw（−303 byte）。WIN は 0 個。
`--mangle-properties` が実 library で不発だったのと同じ種類の、
知っておく価値のある不都合な事実です。

## 残っている既知の未修正

| 件 | 症状 |
| --- | --- |
| alias 付き re-export | `export { X as Y }`（別 module 由来の X）が両方の綴りごと落ちる。ts-pattern の `P` |
| top-level の TDZ | typebox の bundle が `Cannot access 'IntegerKey' before initialization`。`const` の宣言が使用より後に並ぶ |
| module 跨ぎの `const enum` | immer の bundle が `ArchType is not defined` で load 失敗 |
| remeda の parse error | `setPath.ts`: `Expected Semicolon, got Extends` |
| property mangler が実 library で不発 | fail-closed な callee-provenance scan が全部 reserve する |
| excalidraw が僅差で LOSS | −303 byte（−0.11%）。noise floor が 280 byte なのでぎりぎり判定に乗っている。残りの機構は未特定 |
| CSS modules の値 | `import styles from "./x.module.css"` に `{}` を渡す。class 名 map ではないので `styles.foo` は `undefined` |
| `TypeArgs` の構造的保証 | 19 file に arm を足したが、次に walker を書く人が落とすのを止める仕組みは無い。`case40` が唯一の網 |

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
