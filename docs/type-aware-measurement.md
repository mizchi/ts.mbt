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
| hono | 188 | 63,192 | 20,242 | 20,248 | +6 | NEUTRAL |
| valibot | 828 | 228,307 | 88,768 | 88,768 | 0 | NEUTRAL |
| typebox | 692 | 380,453 | 119,453 | 119,700 | **+247** | **WIN** |
| immer | 17 | 49,349 | 20,399 | 20,399 | 0 | NEUTRAL |
| neverthrow | 5 | 9,991 | 5,030 | 5,030 | 0 | NEUTRAL |
| ts-pattern | 18 | 20,772 | 8,567 | 8,567 | 0 | NEUTRAL |
| superstruct | 8 | 20,785 | 10,523 | 10,552 | +29 | NEUTRAL |
| zod | 133 | 653,992 | 200,119 | 200,101 | −18 | NEUTRAL |
| excalidraw | 95 | 788,214 | 280,591 | 280,295 | −296 | LOSS |
| remeda | 349 | 80,902 | 28,594 | 28,620 | +26 | NEUTRAL |

10 measured: 1 win, 8 neutral, 1 loss。**WIN は typebox の 1 件だけ**で、
それは長らく LOSS だったものです（`predicate-inline` の `removable` が
間違った質問に答えていた——下の節）。残る LOSS は excalidraw の −296 で、
どの phase にも帰属せず、leg 構成の artifact です。

WIN が長く 0 件だったこと自体に理由があります。一つ前の記録では
hono が +500、zod が +788 の WIN
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
| ts-pattern | measured | 元 BLOCKED。`P` / `Pattern` が落ちていたのも修正（下記）|
| zod | measured | 元 BLOCKED。4 件の修正を経て挙動検証まで到達 |
| excalidraw | measured | corpus 唯一の UI アプリかつ唯一の monorepo。bundle できるまでに 5 件、実行できるまでに 3 件（下記）|
| superstruct | measured | 元 BLOCKED → 15ms、さらに元 BROKEN → 挙動一致（下記の `.name` reserve）|
| typebox | measured | 元 size-only。`Array.from` の rewrite と module 順序の 2 件を直して挙動検証まで到達（下記）|
| immer | measured | 元 size-only。module 跨ぎの `const enum ArchType` を inline するようにして挙動検証まで到達（下記）|
| remeda | measured | 元 BLOCKED。parser の穴（先頭 `|` が conditional tail を落とす）と fold の穴（spread を 1 要素として数える）を直して到達（下記）|

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

## typebox の −2.98% を追う: predicate-inline に cost model が無かった

excalidraw と同じ手を typebox（残っていた最大の LOSS）に当てました。
`--mangle` 無しの 2 leg で宣言の集合を diff——今回は
**aware だけにある宣言は 0 個**。宣言は同じで、**同じ宣言が大きい**。
1 宣言あたりの byte 差を取ると 136 個が違い、net +5,857。最大のもの:

```
+374 EncodeBuilder   +362 IsExtendsTrueLike   +287 ExtendsUnion$85
+279 ExtendsTupleToArray   +273 ElementsLeft   +180 IsRefine
```

中身:

```js
// blind
function IsExtendsTrueLike(value) {
  return IsExtendsUnion(value) || IsExtendsTrue(value);
}
// aware
function IsExtendsTrueLike(value) {
  return Guard$35.IsObject(value) && Guard$35.HasPropertyKey(value, "~kind") &&
    Guard$35.HasPropertyKey(value, "inferred") &&
    Guard$35.IsEqual(value["~kind"], "ExtendsUnion") &&
    Guard$35.IsObject(value.inferred) || /* IsExtendsTrue の本体も同様 */;
}
```

`predicate-inline` が型述語の本体を call site に撒いていました。
46 byte が 374 byte になり、`IsExtendsUnion` / `IsExtendsTrue` の宣言は
（他の caller が残っているので）**そのまま残る**。bundle 全体で +5.9 KB
——typebox の −2.98% はこれが全部でした。

pass 自身の冒頭コメントはこう書いてありました:「関数呼び出しを数バイトの
式と交換する。inline 後に使われなくなった述語の宣言は treeshake で落ちる」。
**両方とも caller が 1 つのときだけ真**です。

### 先にもっと悪いものが出た: 引数が複製される

cost の前に soundness でした。substitution は**parameter の出現ごとに
引数をコピー**し、それが安全かどうかを誰も見ていませんでした。

```ts
let calls = 0;
function bump(): number { calls = calls + 1; return 1; }
function isOne(x: number): x is 1 { return x === 1 && x !== 2 && x > 0; }
console.log(isOne(bump()), calls);
```

| | 出力 |
| --- | --- |
| `--bundle` | `[true,1]` |
| `--bundle --treeshake --fold` | `[true,3]` |

emit は `bump() === 1 && bump() !== 2 && bump() > 0`。call でも
assignment でも `++` でも `await` でも同じで、**普通の property read も
安全ではありません**（getter が read ごとに走る）。
`arg_is_duplicable` の許可リストは「2 回観測しても何も起きないもの」——
識別子（`this` も `Var("this")` なのでここ）と literal だけです。
それ以外は、本体が parameter を 2 回以上読むなら inline しません。

`fixtures/mangle-safety/case41-predicate-argument` が 4 形を実行で
検査します。3 番目は**対照**で、識別子の引数は複製して良いので
inline されてなお同じ答えを出さなければならない——「inline をやめる」で
逃げられないようにしてあります。

### cost model は測って決めた

budget（本体の node 数）を振って corpus で測りました。

| budget | typebox aware | delta | 判定 |
| --- | --- | --- | --- |
| 制限なし（元） | 123,124 | −3,664 | −2.98% |
| 8 | 121,860 | −2,400 | −1.97% |
| 6 | 121,427 | −1,967 | −1.62% |
| 4 | 121,382 | −1,922 | −1.58% |
| 2 | 119,721 | **−261** | −0.22% |
| 0 | 119,721 | −261 | −0.22% |

hono / valibot / zod / neverthrow / ts-pattern はどの budget でも
1 byte も動きません。**superstruct は −138 の LOSS から +29 の NEUTRAL に
反転**しました。0 と 2 が同じ数字なので、`return x` / `return x.flag`
のように本当に払える形だけを残す 2 を採用しています。

もう 1 つ gate が必要でした。budget 8 の時点で `IsExtendsUnion` は
**caller が 1 つ**だったので「宣言が死ぬから常に得」の例外を通って
いました。ところが typebox は guard を export しているので宣言は死にません。
`removable`（bundle が export していない）を条件に加えています。

読み取れることは、pass 自体にとって不都合です。**述語の inline は
それ自体では byte を減らしません。** `x === "a"` に置き換えるだけでも
`f(x)` より長い。得になるのは後段（`type-fold` / `fold` /
`tag-rewrite`）が畳めたときだけで、畳めるかどうかは inline を決める
時点では分かりません。corpus の WIN が 0 なのはそれと整合しています。

### 残る LOSS

型を消した方が小さくなる target は typebox（−261 byte、size-only）と
excalidraw（−303 byte）の 2 つで、どちらも noise floor
（280 byte 前後）のすぐ上。WIN は 0 個。
`--mangle-properties` が実 library で不発だったのと同じ種類の、
知っておく価値のある不都合な事実です。

## immer: module 跨ぎの `const enum` が消えていた

immer は長いあいだ `size-only` でした。理由は
`export const enum ArchType` — immer が draft をどの proxy
実装に回すか決めるための enum で、`utils/common.ts` で宣言され、
`core/` の複数 module から読まれます。

`const enum` は **runtime binding を一切出しません**。使用側の
`E.Member` を literal に置き換えるのが仕様で、宣言そのものは消えます。
mtsc はそれを module 単位でやっていました。つまり
`load_module_graph` の中で、その module 自身が宣言した enum について
だけ inline していた。

これは bundle 全体の契約（「`E.Member` の参照は 1 つも残らない」）を
1 module の宣言集合に対して検査していた、という形です。
module を跨いだ参照には linker が指す先も無く（binding が無いので）、
inline も走らない。素通りして bundle に残り、load 時に
`ArchType is not defined` で throw していました。
今回で 3 回目の「暗黙の universe」で、class-method DCE が bundle
全体を見るはずが 1 module しか渡されていなかった件と同じ種類です。

修正は `imported_const_enum_table`: graph を読み終えた時点で、各
module が **import 経由で読む** const enum の置換表を作り、linker の
前に inline します。linker が動く時点で `ArchType.Array` は既に `1`
であるべきで、解決すべき `ArchType` は残っていないべき、という順序。

4 つの形を通します。

| 形 | 扱い |
| --- | --- |
| `import { E }` | dep の const enum を local 名で引く |
| `import { E as F }` | decl を `F` に rename して表を作る（`F.M` も置換される）|
| `export { E } from "./x"` / `export * from "./x"` | re-export chain を辿る。cycle は `seen` で切る |
| `import * as K` | `K.E.M` の 2 段 access。path 全体を key にして専用の arm で照合 |

`import * as K` を別扱いにしたのは、synthesize される namespace object
がその module の **runtime export** を集めたものだからです。const enum
には runtime export が無いので、通常の namespace member を平坦化する
pass に任せると落ちます。

`declare const enum` は意図的に置換しません。host が供給するものを
記述しているだけで、書かれている値が実際に効いている値とは限らない。
参照は残り、verifier が報告します — 宣言から推測した値を置くよりは、
そちらが正直な結果です。

driver は 4 つの `ArchType` 経路すべてを踏みます。これは形式的な
網羅ではなく必要でした: `ArchType` は dispatch そのものなので、
**間違った literal を置いても bundle は問題なく load します** —
Array が object 経路に回るだけで。値を観測しないと差が出ません。

結果は `measured` / NEUTRAL / delta 0。size は 20,826 → 20,370 byte
（両 leg とも）。WIN は増えていません。増えたのは「この行の数字が
実行された bundle のものだ」という保証だけで、それが元々足りて
いなかったものです。

## typebox: rewrite の抜けと module 順序で 2 段に壊れていた

typebox も長く `size-only` で、原因は 2 つ、どちらも型とは無関係でした。

### 1. `Array.from(x)` -> `[...x]` に受け側の証明が無かった

`system/hashing/hash.ts` の

```ts
const Bytes = Array.from({ length: 256 }).map((_, i) => BigInt(i))
```

が `[...{ length: 256 }].map(…)` になり、load 時に
`{(intermediate value)} is not iterable` で死んでいました。
`Array.from` は **array-LIKE**（`length` と index property を持つ
object）を受けますが、spread は **ITERABLE** を要求します。

同じ理由で `Array.prototype.slice.call(x)` -> `[...x]` は
**すでに削除済みで、3 行下にその理由がコメントで書いてありました**。
知識は隣にあって、それでも rule は出荷されていた。理由は構造的です:
`verify_rule_equivalence.mjs` は「誰かが case を書いた rule」だけを
検査し、**case が無い rule を報告する仕組みが無い**。peephole と fold
には合わせて ~235 個の rewrite があり、harness の case は 38 個でした。

そこで **受け側の型に妥当性が依存する rewrite を全部** 表に載せました。
6 件が unsound と判定されました。

| rule | 反例 | 対処 |
| --- | --- | --- |
| `Array.from(x)` -> `[...x]` | `Array.from({length:0})` は `[]`、spread は throw | `is_definitely_iterable` で gate |
| `Array.prototype.M.call(x, …)` -> `x.M(…)` | string / `arguments` / array-like に method が無い。逆に receiver が同名 method を持つ場合は built-in ではなくそれを呼ぶ | 削除（`slice` だけ除外していたのは、誰かが踏んだ 1 例だっただけ）|
| `x.slice(0)` -> `[...x]` | `"ab".slice(0)` は `"ab"`、`[..."ab"]` は `["a","b"]` | 削除 |
| `[].concat(a)` -> `[...a]` | `concat` は非 array を **1 要素として append**。`[].concat(1)` は `[1]`、`[...1]` は throw | 引数が全部 array literal のときだけ |
| `Math.pow(a,b)` -> `a**b` | `Math.pow(10n,10n)` は throw、`10n ** 10n` は計算する | 片方が BigInt でないと証明できれば可（`Math.pow(x, 2)` は通る）|
| `f.apply(null, a)` -> `f(...a)` | `apply` は array-like も、`null`/`undefined`（引数なし）も受ける | `is_definitely_iterable` で gate |

証明は**構文的**で、意図的に狭くしています。`Var` は文脈でどれだけ
array に見えても証明にはなりません。型を読めば広げられる（peephole は
今 `PeepCtx` に型表を持っていない）ので、これは E7 の候補です。

サイズは払いました: 9 target のうち 4 つで合計 ~700 byte 増えています。
壊れない側に寄せた分の値段で、記録しておく価値のある数字です。

### 2. module 順序が ESM と違っていた

`Array.from` を直すと、記録されていた TDZ が出てきました:
`Cannot access 'IntegerKey' before initialization`。

`indexed/from_object.ts` は top-level で
`const NumericKeyPattern = new RegExp(IntegerKey)` を実行し、
`IntegerKey` は `types/record.ts` にあります。両者は 23 hop の
**循環**の中にいるので、どちらが先に初期化されるかは
ESM の評価順（entry からの depth-first post-order）だけが決めます。

mtsc の `topological_order` は module の依存を
`resolved_imports`（Map）で辿っていました。これを import 宣言の順に
直しても**出力は 1 byte も変わりませんでした** — MoonBit の Map が
挿入順だったからです。実際の原因はその 1 段上でした:

**`import_decls` を全部、その後 `reexport_specs` を全部**、という
順序は、2 つを混ぜている file では source 順と違います。そして
barrel はまさにそういう file です。typebox の `src/index.ts`:

```ts
export * from './type/action/index.ts'
export * from './type/engine/index.ts'
export * from './type/extends/index.ts'
export * from './type/script/index.ts'
export * from './type/types/index.ts'   // ← record.ts はこの下
export * as Type from './typebox.ts'
import * as Type from './typebox.ts'    // ← これを先に辿っていた
```

`./typebox.ts` の subtree に先に降りたので `record.ts` が遅れ、
372 module のうち 6 番目から order が分岐していました。

`TsModuleBlock.module_request_order` を追加し、parser が
import 宣言と re-export 宣言を**パースした順に 1 本の列**へ積むように
しました。2 つの配列では表現できない情報なので、field が必要でした。
`import type` は消去後に module request が存在しないので入れません。

修正後、mtsc の順序は 372 module すべてで ESM の DFS post-order と
一致します。

typebox は `size-only` -> `measured`。driver は
`Record(Integer(), …)` が出す `patternProperties` を読み返します:
`IntegerKey` は文字列なので、**throw せずに違う値になった順序でも
schema は組み上がってしまう** — 組み上がるが、正しくない。

これで corpus の `size-only` は 0 になりました。9 target 全部が
挙動検証付きです。WIN は 0 のままで、増えたのは「表の数字が実行された
bundle のものだ」という保証だけです。

## remeda: BLOCKED の原因は pass ではなく parser だった

remeda は「pipeline が食えない」ではなく、**1 file がパースできない**
ために丸ごと BLOCKED でした。`setPath.ts`:

```ts
type Paths<T, Prefix extends readonly unknown[] = []> =
  | Prefix
  | (T extends object ? … : …) extends infer Path
  ? Readonly<Path>
  : never;
```

TS は union に先頭 `|` を許します（1 行 1 member で書けるように）。
`parse_type` はその装飾に**専用の分岐**を持っていて、union を組んで
**return** していました——下にある `extends` tail を通らずに。
結果、check type をその書き方で書いた conditional type は条件を失い、
`extends` で parse error になる。

装飾なしの `T | string extends …` は通っていました。だから気づかれ
なかった: **バグに必要なのは union ではなく装飾**でした。
先頭 `&` にも同じ早期 return がありました。

修正は分岐を消して、装飾を消費してから**同じ path を通す**こと。
`&` は `parse_intersection_type`（本来の居場所）に移しました。

### そして corpus に入れたら実挙動の差が出た

`reverse([1,2,3])` が `[1,2,3]` を返しました。原因は
`[...array].reverse()` の fold で、spread を 1 要素として数えていた。
詳細は [`rule-equivalence.md`](./rule-equivalence.md) に。

corpus に target を足す価値がここに出ています: remeda は
**BLOCKED → 実挙動の差 → measured** と 2 段で発見をもたらしました。
1 段目は parser、2 段目は fold で、どちらも他の 9 target では
出ていなかった形です。

remeda を選んだ理由も残しておきます: ほぼ全 function が data-first /
data-last の 2 形を持ち、`purry` が `arguments.length` で runtime
dispatch します。**共有 helper 経由の arity 依存の間接呼び出し**で、
unused-parameter pass や single-use inliner が「何も変に見えないまま」
壊せる形です。driver は lazy な `take` の上流呼び出し回数も数えるので、
評価順を変える fold は答えの誤りではなく回数として出ます。

結果は NEUTRAL、delta +26 byte(0.09%)、noise floor 以下。
これで corpus は **10 target 全部 measured、BLOCKED も size-only も 0**
になりました。

## ts-pattern: 公開 API の大半が落ちていて、row は NEUTRAL だった

ts-pattern の entry は

```ts
import * as Pattern from './patterns';
export { Pattern, Pattern as P };
```

で、**両方の綴りが bundle から消えていました**。`P` は ts-pattern を
使う人がまず import するものなので、公開 surface のほぼ全部です。

原因は 2 段でした。

### 1. export specifier は block reference ではない

namespace object（`const Pattern = {...}`）は namespace が **escape**
するときだけ合成されます。これは正しい設計で、無条件に出すと循環 import
で TDZ を壊すからです（zod の `iso.js` <-> `schemas.js`）。

しかし escape 判定は module の **block** 内の参照を探します。
`export { Pattern }` は module のメタデータで、block の中の参照では
ありません。だから合成されず、`Pattern` は解決先を失い、export list
からも消える。

`export * as ns from "…"` は既に forced escape 扱いでした。
by-name の形は同じ事実の別の言い方です。

### 2. `export type { X }` が namespace object に入っていた

1 を直したら `let ns = { Pattern: ns, … }` という**自己参照**が生まれ、
`Cannot access 'aE' before initialization` になりました。

`patterns.ts` に `export type { Pattern }` があります。これは
**別 module から import した型の再 export** で、linker の
type-only 判定は module 自身の `type_aliases` / `interfaces` から
導出していたので、これが見えていませんでした。

`TsExportSpec` に flag を足すのが素直ですが、この struct は 85 箇所で
構築されています。代わりに `TsModuleBlock.type_only_exports` として
**parser が「module がそう言った」ことを記録**するようにしました。
`TsReExportSpec` は既に `type_only` を持っているので、対称になります。

### driver をバグの周りに書いていた

一番の教訓はこれです。ts-pattern の driver には
「`P` は bundle に無いので import しない」というコメントが付いていて、
row は **NEUTRAL** と報告し続けていました。**driver をバグの周りに
書くと、そのバグを承認してしまう**。

driver は `P` の 13 の使い方（`union` / `array().select()` / `when` /
`instanceOf` / `optional` / `_` / nested select …）と
`P === Pattern` を観測するようにしました。

サイズは 5,795 → 8,567 byte に増えています。**以前は公開 API の
大半を黙って落として小さくなっていた**だけです。

## CSS modules: 直さないと決めた（そして警告にした）

`import styles from "./x.module.css"` に `{}` を渡しているので
`styles.foo` は `undefined` です。当然の対処は stylesheet を走査して
identity map（`{ foo: "foo" }`）を返すことですが、**やめました**。

理由は 2 つあります。

1. **loud な失敗を silent な失敗に交換してしまう**。`undefined` は
   `undefined.length` で throw し、`${styles.foo}` は "undefined" と
   描画されます。identity map はもっともらしい class 名を返しますが、
   mtsc は CSS 自体を出さないのでどの rule にも一致しません。
   **スタイルが当たらないのにエラーも出ない**方が悪い。

2. **効く証拠が無い**。excalidraw の stylesheet import は
   **76 件すべて side-effect 形**で、これは正しく処理されています。
   corpus に value 形の CSS import は 1 件もありません。

代わりに value 形を **警告** するようにしました。import 宣言が
見える enqueue 側で判定するので、side-effect 形は静かなままです
（そうでなければ 76 件の noise になる）。

これは今日の他の修正と同じ姿勢です: **できないことを言う**。
推測は CSS pipeline を実際に持っている呼び出し側に残します。

## property mangler の不発は「fail-closed」ではなく arrow だった

`--mangle-properties` は測定した全 library で **1 byte も動かない**
状態が続いていました。原因は「解析が fail-closed だから」と記録して
いましたが、それは粗すぎました。

`--explain-mangle` が答えを持っていました。全 target で原因は 1 種類:

```
binding `createNeverThrowError` crosses the bundle boundary and
carries no closed type annotation, so every name on it is assumed
reachable
```

neverthrow は **これ 1 件だけ**で全体が suppress されていました。
`createNeverThrowError` は `throw` される値を返す関数で、body は
bundle の中にあります。

### 切り分け

4 変種で試したら、generic かどうかでも export かどうかでもなく、
**arrow 形かどうか**でした。

| 形 | wildcard |
| --- | --- |
| `export function make(): W {…}` | 出ない |
| `export const make = (): W => …` | **出る** |

`symbol_graph.mbt` の arrow arm にはこう書いてありました:

```
// Arrow has no own SymbolId for the function value itself;
// returns / throws don't add func-return edges.
w.enclosing_func = None
```

`g.funcs` は「この関数の return 経路は全部見えている」を意味する表で、
そこに無い関数は `seed_from_expr` が **`External`** にします。
`External` は wildcard です。つまり **body が目の前にある関数を
不透明扱いして、bundle 全体の property mangling を止めていた**。

arrow に SymbolId が無いのは事実ですが、`const f = (…) => …` の
**宣言名が identity** です。`sg_visit_decl` は既に
`enclosing_def` を持っているので、初期化子が直接 arrow のときだけ
その id を渡します（初期化子の中にネストした arrow は誰の名前でもない）。

### 健全性は「完全な情報がある場所」で確認する

`g.funcs[fid].returns` を信用できるのは、その名前がまだ walk が見た
関数を保持している間だけです。`let f = () => a; f = external` なら
記録した returns は候補の 1 つに過ぎません。

再代入は宣言より後にも書けるので、**登録時ではなく消費時**に
`func_returns_are_complete`（= `!reassigned`）で確認します。
これは既存の named function の穴（再代入された `function f` を
無条件に信用していた）も同時に閉じます。

### 結果

| target | mangle のみ | + mangle-properties |
| --- | --- | --- |
| hono | 22,350 | **20,243（−2,107 / −9.4%）** |
| neverthrow | 5,167 | **5,031（−136 / −2.6%）** |
| typebox | 119,962 | **119,715（−247）** |
| zod | 200,127 | 200,120（−7）|
| valibot / immer / ts-pattern / superstruct / remeda | — | 変化なし |

`measure_type_aware.mjs` が `--mangle-properties` を除外していた理由
（「inert だから」）が消えたので flag set に入れました。副作用として
**typebox の LOSS が消えました**（−261 → −14 byte、LOSS → NEUTRAL）。

WIN は 0 のままです。property mangling は両 leg にほぼ同じだけ効くので、
delta は動きません。動いたのは絶対サイズです。

### fuzzer が 2 件の emitter バグを出した

解析を緩めたので fuzzer を 600 seed 回したら、**私の変更とは無関係な**
token 隣接バグが 2 件出ました。どちらも出力がパースできません。

1. `expr_leading_byte` が**負の数値リテラル**を `'0'` と答えていた。
   `--fold` が `UnaryOp(Neg, IntLit(3))` を `IntLit(-3)` にするので、
   `x - -3` が `x--3`（decrement）になる。seed 484。
2. 1 を直すとき `right_needs_token_separator` の AST 形の二重表を
   `expr_leading_byte` に集約したら、**`PreInc`/`PreDec` の行を落として**
   `c + ++a` が `c+++a` になった。seed 73。
   「2 つの copy を 1 つにする」のは、**残す側が完全なとき**だけ改善です。

800 seed（1600 program）で mismatch 0。

## LOSS の機構は pass ではなかった: leg の作り方だった

「excalidraw が僅差で LOSS、機構は未特定」が長く残っていました。
`--timing` は各 phase の**時間**を言いますが、各 phase が何 byte の
責任を持つかは誰も言えませんでした。20 pass の pipeline で当てずっぽうは
根拠になりません。

そこで `--disable-phase <name>` を追加しました。名前は `timer.phase`
が使っているものと同じなので、`--timing` の出力がそのまま
「何を切れるか」の一覧になります。

### corpus 全体の帰属（`--phases`、正の値 = その phase が節約した byte）

| target | predicate-inline | switch-fold | as-const-inline | tag-rewrite | class-method-dce | type-fold |
| --- | --- | --- | --- | --- | --- | --- |
| typebox | **−261** → 0（修正後） | 0 | 0 | 0 | 0 | 0 |
| immer | 0 | 0 | 0 | 0 | 0 | 0 |
| neverthrow | 0 | 0 | 0 | 0 | 0 | 0 |
| ts-pattern | 0 | 0 | 0 | 0 | 0 | 0 |
| superstruct | +29 | 0 | 0 | 0 | 0 | 0 |
| zod | 0 | 0 | 0 | 0 | 0 | 0 |
| excalidraw | 0 | 0 | **+920** | 0 | 0 | 0 |
| remeda | +26 | 0 | 0 | 0 | 0 | 0 |

読み取れることが 3 つあります。

**1. 動くのは実質 2 phase だけ。** `switch-fold` / `tag-rewrite` /
`class-method-dce` / `type-fold` は **corpus 全体で 1 byte も動かして
いません**。4/6 が完全に不発です。

**2. leg delta = `predicate-inline` の値**、3 target で完全一致:

| target | leg delta | predicate-inline |
| --- | --- | --- |
| typebox | −261 | −261 |
| superstruct | +29 | +29 |
| remeda | +26 | +26 |

つまり「typebox が僅差で LOSS、機構未特定」の答えは
**`predicate-inline` が 261 byte 損している**でした。
`PREDICATE_INLINE_MAX_COST` を 8 → 2 まで絞った後の残りです。
**そしてその 261 byte は budget の問題ではありませんでした** — 次節。

**3. 唯一の実質的な勝ちは `as-const-inline` の excalidraw +920。**
そして excalidraw の leg delta は −296 で、どの phase にも帰属しません。
zod の −18 も同じです。**これらの残差が leg 構成の artifact** です。

### 261 byte の正体: `removable` が別の質問に答えていた

帰属できた次は「なぜ損なのか」です。最初の仮説は **budget が緩い**
——N 箇所に copy するコストは N×body、得は宣言 1 個分なので、
break-even は N の関数であって body の大きさだけでは決まらない、という
話です。そこで multi-call-site の側に `entry.removable` を要求してみた
ところ、**typebox の数字は 1 byte も動きませんでした**（−261 のまま）。

仮説が外れたので、モデルを足す前に出力を見ました。mangle を切って
`--disable-phase predicate-inline` の有無で bundle を 2 本出し、
`function NAME(` を数えます:

```
funcs on: 836  off: 836
gone when ON (inlined+removed): (none)
```

**宣言が 1 つも消えていません。** phase の唯一の得が発生していない、
つまり全部が純粋なコストです。ON 側が 363 byte 大きく、これは pass の
comment に前から書いてあった「362 byte written twice」とほぼ一致します。
数字は既に書かれていて、意味が回収されていなかっただけでした。

`removable` の定義はこうなっていました:

```moonbit
removable: not(exported.contains(name))
```

`exported` は entry の named export 一覧です。typebox の guard は
**そこに載りません** — linker が合成する namespace object 経由で外に
出るので、named export ではないのです。だから全部が removable に見え、
`call_sites <= 1 && removable` の免除路が開き、body が copy され、
宣言は namespace object から参照されているので当然生き残ります。

field 名は「消せるか」ですが、実際に答えていたのは「entry が名前で
export しているか」でした。後者は前者の**必要条件の一つ**でしかありません。

正しい不変条件は call 数では見えません: inline が書き換えられるのは
**call だけ**なので、宣言が死ぬのは「call 以外の言及が 0」のときだけ
です。namespace object literal、re-export、値としての受け渡し —
どれ一つでも残っていれば、何箇所 rewrite しても宣言は残ります。

そこで counter を calls / other-refs の 2 本立てにしました。`Var(n)` の
目撃数から `CallExpr(Var(n))` の callee 分を引いたものが other-refs
です（walker は callee も訪問するので、引かないと呼ばれた述語が全部
「永久に参照されている」ことになります）。

結果:

| | 修正前 | 修正後 |
| --- | --- | --- |
| typebox `predicate-inline` | −261 | **0** |
| typebox leg delta | −14 | **+247** |
| typebox 判定 | NEUTRAL | **WIN (0.21%)** |
| superstruct / remeda | +29 / +26 | +29 / +26（不変） |

corpus 初の WIN です。そして得ている 2 target が変わっていないことが
重要で、gate は pass を止めたのではなく**払えない取引だけを止めた**
ことになります。

教訓は既知の family でした: **「必要条件を十分条件として使った」**
（`exported` に無い = 消せる）。`export_surface.mbt` を持っている repo で
「export されているか」を named export 一覧だけで判定したのが誤りで、
bundle は他にも名前を外に出す経路を持っています。

### `blind` は「型を消した同じコード」ではない

`blind` の入力は `unopt.mjs` — **mtsc 自身の emitter を一度通した**
コードです。その round-trip 自体が最適化になっています
（`as` が消え、class が lower され、宣言が merge され…）。
`aware` はそれを受け取りません。

`aware2` leg はこれを price するために作られましたが、測っているのは
**「すでに最適化された出力に 2 回目を掛けたら何 byte か」**で、
別のものです。excalidraw では **負の値（2 回目で 843 byte 増える）**
になり、引くと gap が縮むどころか広がります。

### だから信用すべき数字は per-phase 表

`--phases` を足しました。aware leg を phase ごとに 1 回ずつ落として
コンパイルし、差を報告します。**control が要りません** — 同じ入力、
同じ flag、問題の phase だけが違う。

leg delta は「published `.js` を相手にしたら何が起きるか」の答えとして
残す価値があります（それが元々の問いです）。しかし
**「型を知っていることは何 byte の価値があるか」への答えは per-phase 表**
です。

## 残っている既知の未修正

| 件 | 症状 |
| --- | --- |
| 述語 inline の得は後段次第 | inline それ自体は byte を増やす。畳めるかどうかは inline を決める時点で分からないので、budget 2 は「本当に払える形だけ」の近似 |
| CSS modules の値 | `import styles from "./x.module.css"` に `{}` を渡す。class 名 map ではないので `styles.foo` は `undefined`。**修正しないと決めた**（下記）。value 形は警告するようにした |
| `TypeArgs` の構造的保証 | 19 file に arm を足したが、次に walker を書く人が落とすのを止める仕組みは無い。`case40` が唯一の網 |
| ~~`predicate-inline` が typebox で 261 byte 損~~ | **修正済み**。`removable` が「entry の named export に無いか」しか見ておらず、namespace object 経由で外に出る typebox の guard を全部 removable と判定していた。call 以外の言及を数えるようにして 0 に。typebox は corpus 初の WIN (+247) |
| 述語 inline の得は mangle 後の呼び出しと比べていない | 判定は mangle 前なので、`isExtendsUnion(v)` を基準に価格付けしていて、実際に ship されるのは `a(v)`。body 2 node は既にそれより大きい。`removable` を直した後は corpus 上で損が出ていないので、model を足す根拠が今は無い |
| 型読み 6 phase のうち 4 つが corpus 全体で不発 | `switch-fold` / `tag-rewrite` / `class-method-dce` / `type-fold` が 1 byte も動かさない。対象の形が corpus に無いのか、gate が閉じすぎなのかは未切り分け |

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
