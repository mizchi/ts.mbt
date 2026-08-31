# 型追跡による安全な property mangling

`mtsc --mangle-properties` は property 名を rename します。これが実用に
なるのは、rename した名前が bundle の外から絶対に観測されないことを
*証明* できる場合だけです。この文書はその証明モデルと、
[packelyze](https://github.com/mizchi/packelyze) の test case を corpus と
した検証結果、そして残っているギャップをまとめます。

packelyze は `lib/index.d.ts` を解析して terser の
`mangle.properties.reserved` を生成する実験でした。ts.mbt はそれを
「宣言だけでなく値も追跡する」方向に延長し、判定を自前の checker /
transform に持っています。

## 観測される名前は 2 つの door から漏れる

property 名が bundle の外に出る経路は 2 つだけです。

**Door 1 — export surface.** entry module が export した値から到達できる
property 名は、すべて package の ABI です。`interface` に書かれている
必要はありません。

```ts
export function run() {
  const internal = { name: "John", age: 30 };
  const { name, age } = internal;
  return { first: 1, rest: [], name, age };  // ← 4 つとも ABI
}
```

`src/transform/export_surface.mbt` が entry の export された binding から
値を辿ります。予約するのは:

- export に到達する object literal の key（`x.a.b` を読めるので再帰的に）
- export された関数の *parameter* に対して読まれた property 名
  （caller がその shape を組み立てるので名前が signature の一部）
- export された class の member（`private` / `#x` は除く）
- export された関数の return 値、および結果が escape する call に渡された
  callback の return 値（`[…].map(x => ({ www: … }))`）

値の出自が解決できないとき（未知の callee の戻り値、不透明な object への
property read）は「その object が持つものは全部漏れる」側に倒します。
rename できたはずの名前を予約するコストは数 byte、漏れる名前を rename する
コストは consumer の破壊です。

**Door 2 — side-effect sink.** `fetch` / `console.*` / `JSON.stringify` /
external package の関数呼び出しに値が届くと、その property 名も値ごと外に
出ます。

```ts
export function run() {
  const body: MyBody = { body: 1 };          // 型は module 内部だが
  fetch("…", { body: JSON.stringify(body) }); // body という名前は外に出る
}
```

`src/transform/mangle_safety.mbt` が sink を集め、
`src/transform/flow_analysis.mbt` の observability lattice
（`Hidden < ViaStringify < DirectProps < RecursiveProps < External`）を
sink から後ろ向きに伝播させます。sink に届く値が literal
（`send({ rrr: 1 })`）の場合は free variable が無く flow 解析の種にならない
ので、literal の key を直接（入れ子込みで）予約します。

どちらの door からも到達できない property だけが rename 対象です。到達
可能性を証明できない場合（`obj[runtimeKey]` のような完全に動的な access）
は wildcard になり、property mangling 自体が抑止されます。

### sink の列挙ではなく callee の provenance で決める

Door 2 の判定は当初「危険な呼び出しの列挙」でした。`fetch`、`console.*`、
`JSON.stringify`、import された binding —— 知っている sink に当たったら
引数を escape させ、それ以外は素通り。この形は原理的に完成しません。
`postMessage`、`structuredClone`、`Response.json`、IndexedDB、次に増える
Web API —— 誰も列挙しなかった名前はすべて「rename したが consumer は
古い名前で読む」という silent hole になります。

そこで規則を反転させました（`src/transform/callee_provenance.mbt`）。

> **callee が bundle 内部だと *証明* できない呼び出しは、引数が escape する。**

証明できる例外は 2 つだけです。

1. callee が bundle の宣言する binding に解決される（= 本体が解析対象
   なので、flow 解析の `FuncArg` / `FuncReturn` edge が面倒を見る）。
2. callee が `src/transform/pure_builtins.mbt` の allowlist に載っている。

allowlist には性質の違う 2 種類が入ります。**name-blind** な built-in
（`Math.max(a, b)` は数値しか見ない、`parseInt(s)` は文字列しか見ない、
`new Map(pairs)` は index で読む）と、**すでに精密に model 済み**の
built-in（`Object.keys(x)` は `DirectKeys` sink、`JSON.stringify(x)` /
`console.log(x)` は `Recursive` sink）です。後者を一般規則にも通すと、
正確な予約が wildcard に置き換わって bundle 全体の property mangling が
止まります。

この allowlist は飾りではなく荷重を受けています。`Math` を allowlist から
外すと、下の case30 の `runningSum` / `largest` は rename されなくなります
（実測）。

provenance は値についても同じ向きに定義されます。`value_is_host_shaped(e)`
は「`e` の値を host が所有しているか」を答え、`classify_callee` と相互再帰
します —— foreign call の戻り値は host-shaped で、host-shaped な値を呼ぶのは
foreign call です。`host_provenance_names` が block 全体でこの連立を不動点
まで解いてから symbol graph の walk が始まるので、walk 時点では各 call site
の callee の出自が既知です。伝播するのは:

- `const cfg = JSON.parse(text)` —— 引数は escape しないが、結果の key は
  runtime の文字列由来なので host のもの
- `const client = createClient(); client.transmit(payload)` —— `client` は
  local binding だが値は foreign factory 由来
- `function load() { return remote.read(); }` —— 薄い wrapper は出自を
  洗浄しない
- `rows.map(row => row.id)` —— foreign call に渡した callback の parameter は
  host が埋めるので、そこから読む名前は host のもの

入ってくる値と出ていく値で予約の形が違う点は意識して分けています。入って
くる host-shaped な値については、**自分の code が読み書きする名前だけ**を
予約すれば十分です（読まない名前は rename しようがない）。wildcard が必要
なのは逆向き —— 解析できない本体に値を渡す側だけです。

### 型注釈が wildcard を狭める（そして注釈が名前でも効く）

出ていく値の wildcard は「解析できない本体が何を読むか分からない」から
来ています。ここには型による逃げ道があります。値に閉じた key 集合を持つ
型が付いていれば、consumer はその名前しか**合法に**読めません —— それ以上を
読むのは consumer 側の型エラーです。なので wildcard の代わりにその key
集合だけを予約できます。

問題はどう書いた注釈が効くかでした。inline の object type は効くのに、
実際の codebase が書く `interface` / `type` の名前は効かない —— `Named("Cfg")`
を解決する手段が transform 層に無く、opaque な named type として `None` に
落ちていたためです。これは「注釈を付けろ」という助言が黙って無効になる形
なので、`build_type_env`（`flow_analysis.mbt`）で bundle が parse した
declaration を name → shape の表にして解決するようにしました。
`TsModuleBlock.interfaces` はそのために追加した経路です（type alias は
既に同じ理由で通っていました）。

解決の向きは安全側に倒しています。

- **type 引数は key 集合を変えない。** `Box<string>` と `Box<number>` の
  key は同じなので `Applied(n, _)` も名前で解決します。key を計算する型
  （mapped type、`keyof`）には arm が無く `None` に落ちます。
- **`extends` は intersection として解く。** `interface Cfg extends Host`
  は `Struct(Cfg fields) & Named("Host")` になるので、`Host` が見えない
  なら intersection 全体が `None` —— base の名前を落としたまま Cfg の key
  だけ予約する、という間違いが起きません。
- **index signature は key 集合を閉じない。** `[k: string]: number` を
  持つ interface は `Object([(String_, Any)])` として model し、wildcard の
  ままにします。
- **自己参照は止まる。** `interface Node { next: Node }` は型としては再帰
  しますが key 集合は再帰しないので、訪問済み名を持って打ち切ります。

なお注釈で狭まるのは**その binding 自身の key 集合**だけで、入れ子の名前は
別経路（External を root とする value tree の walk）が予約します。注釈を
「深い」保証として使っているわけではありません。

固定しているのは `case36-annotated-boundary` で、`Envelope` の
`topic` / `body` が残り、同じ file の内部 ledger が rename されることを
実行して確認しています。

## 検証: `fixtures/mangle-safety`

モデルが正しいと主張するには、実際に壊れないことを示す必要があります。
`scripts/verify_mangle_safety.mjs` は corpus の各 case について:

1. entry を 2 回 compile する — 素の `--bundle` と、
   `--bundle --mangle-properties --reserve-entry-exports`。
2. `case.json` の `exports` が両方の bundle から export されているか
   確認する。`export … from` が落ちるのは、両方で落ちていても bug です。
3. 両方の bundle を Node で import し、`fetch` / `console.*` を記録しながら
   case の `driver.mjs` で public API を叩き、観測結果を diff する。

**2 つの bundle の間に観測可能な差があれば、それは mangler の安全性違反
そのものです。** 返る object の key が変わった、request body が変わった、
`ReferenceError` になった — すべてこの diff に出ます。

```bash
just verify-mangle-safety
just verify-mangle-safety --case case04-internal
```

corpus の 25 件は packelyze の `packages/transformer/fixtures`
（`case00`〜`case25`、重複の `case07-missing` を除く）を TypeScript source
ごと移植したものです。`_expected.js` は持ち込まず、期待値は「特定の
mangler の出力」ではなく「振る舞い」として `case.json` に書いています。
`case26` 以降は ts.mbt 側で追加した手書き case で、sink 規則の反転で塞いだ
穴、allowlist の効き、DCE 系 pass の証明義務、型注釈による wildcard の
狭まりを固定しています。`generated/` はモデルから払い出した 112 件で、
軸と生成規則は [`docs/minify-patterns.md`](./minify-patterns.md) にあります。

### 現在の結果

148 件（手書き 36 + 生成 112）中 **148 件 pass**、安全性違反 0 件。

初回実行では 12 件が fail、7 件が checker / emit のギャップで compile
できませんでした。内訳と対処:

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| exported const / function が返す object の key が **削除** される（case18/22/23/24） | reserved set が entry module の *宣言された* 型からしか作られていなかった。他 module の型で注釈された値も、推論された return shape も誰も読まないと判定され dead-property pass が消していた | `export_surface.mbt` を追加 |
| exported 関数の推論 return shape の key が rename される（case16） | 同上 | 同上 |
| external module の呼び出しに渡した literal の key が削除される（case15） | object literal は free variable を持たないので flow 解析の種にならなかった | sink literal の key を直接予約 |
| entry が `export { x } from "./sub"` だけのとき bundle に export が 1 つも出ない（case01/17/18/25） | `emit_entry_exports` が entry 自身の `export` spec しか見ていなかった | re-export を linker 経由で解決して emit（`export *`・bare specifier passthrough 含む） |
| `export type { T }` が値 export として emit され bundle が load 不能（case18） | `TsExportSpec` に type-only の区別がない | runtime binding を持たない export 名を落とす |
| `foo<T>(x)` の callee が rename されず `ReferenceError`（case08） | `TypeArgs` wrapper が両 renamer の catch-all に落ちていた | `TypeArgs` arm を追加 |
| exported class の public method が **削除** される（case02） | class-method DCE の「使われている」判定が bundle 内の access だけを見ていた。consumer だけが呼ぶ method は dead に見える | export surface を `keep` set として渡す |
| `namespace N { … }` の body が消え、`N.member` 参照だけが残る（case09/10） | statement parser が namespace body を skip する | IIFE への lowering を実装（下記） |
| ambient global（`declare const MyGlobal`）が解決できない（case03） | entry の隣の `.d.ts` を program に含めていなかった | sibling `.d.ts` を ambient script として読み込む |
| import された型が解決できず、同一 shape が mismatch になる（case19/20） | file ごとに checker を走らせていた | module graph 全体を検査する `collect_module_graph_issues` に接続 |
| mapped type への indexed access が解決しない（case11） | `simplify_indexed_access` は resolver を持たず、`Named` base で `Any` を返す | base を先に resolve してから simplify |
| constructor の default parameter が arity に反映されない（case02） | `lookup_constructor_sig` が `constructor_param_defaults` を捨てていた | default を signature に通す |
| `{ a, ...spread }` の spread member が推論 shape から落ちる（case20） | `infer_block_return` が block の local binding を見ていなかった | return を推論する前に local を bind |

### 反転で塞いだ穴（case26〜case30）

sink 列挙から callee provenance への反転で塞がった穴は、反転前の binary で
実際に fail することを確認してから corpus に固定しました。

| case | 形 | 反転前の挙動 |
| --- | --- | --- |
| case26-host-chain | `HostBridge.channel.post(record)` | receiver が bare identifier でないので sink として認識されず、`record` の key が **削除** された（`const b = {}`） |
| case27-foreign-factory | `const client = createClient(); client.transmit({…})` | `client` は local binding なので内部呼び出しに見え、引数の key が rename された |
| case29-callback-shape | `HostList.each(row => … row.rowCaption …)` | callback parameter から読む名前は誰も予約しておらず rename された |

3 件はいずれも「観測可能な振る舞いが変わった」として検出されます
（`"first:1"` → `"undefined:undefined"` など）。残る 2 件は逆向きの
regression guard です。

| case | 何を固定するか |
| --- | --- |
| case28-json-shape | `JSON.parse` は allowlist に載るが、その **結果** は host-shaped —— allowlist が出自を洗浄しないこと |
| case30-pure-builtins | `Math.max` / `new Map` / `Map#set` を通る内部 accumulator が rename され続けること（allowlist が荷重を受けていること） |

case30 は checker の穴も 1 つ露出させました。`Math.max` / `Math.min` /
`Math.hypot` / `Object.assign` / `String.fromCharCode` / `String.fromCodePoint`
/ `Array.of` / `Date.UTC` は可変長ですが、`global_namespace_method` が
固定 arity で model していたため `Math.max(a, b)` が TS2554 になっていました
（`Math.imul` は逆に 2 引数を 1 引数として model していました）。parser が
rest parameter に使うのと同じ `Rest(Array(T))` 形に直しています。conformance
の計測値は変わりません（FP 0 / TP 2,339 / TN 1,750）。

### 検証の副産物: `--treeshake` が export を落としていた

corpus とは別に、export emit を直した際に見つかった件です。

```ts
export function pub() { return 2; }
const unused = 3;
```

`treeshake_block` の root は「副作用を持つ statement」だけでした。export
された binding を bundle の内側から参照する必要は無いので、`pub` は dead
と判定されて消え、export 節だけが残る（あるいは export ごと静かに失われる）
状態でした。`treeshake_block(block, roots~)` に entry の export 名を渡す
ようにしました。

## 実装したもの（旧「残っているギャップ」）

corpus の 7 件を blocked にしていたギャップはすべて塞ぎました。要点だけ:

### runtime namespace の lowering（case09, case10）

```ts
namespace N {
  const secret = 1;
  export function f() { return secret; }
}
```

statement parser は namespace body を skip していたので、`N.f()` だけが
残り `N` を宣言する code の無い JS が無診断で出ていました。
`src/parser/parser_namespace_lower.mbt` が TypeScript と同じ形へ lowering
します。

```js
var N = N || {};
(function (N) {
  const secret = 1;
  function f() { return secret; }
  N.f = f;
})(N);
```

`let`（`var`）ではなく `var` + `N || {}` なのは declaration merging の
ため — 2 つ目の `namespace N { … }` が同じ object を再利用します。
`export let` は再代入されうるので snapshot ではなく
`Object.defineProperty` の getter で公開し、読み取りが live であることを
保ちます（外から `N.x = v` と書いた場合は local に伝播しません。TS は
参照側を書き換えることでこれを実現しており、そこまではやっていません）。

lowering できない形（`module "foo" { … }` のような quoted name、
`namespace A.B { … }` の dotted path、`declare global`）は従来どおり
skip します。ambient（`declare namespace` など）は正当に erase される
ので対象外です。

namespace の member は IIFE の中で `N.f = f` として付けられるため、
export surface 解析にも「escape する object へ代入された property 名は
公開されている」という規則を追加しました。

### property descriptor の key は runtime が名前で読む

`Object.defineProperty(o, "p", { … })` は runtime に**名前で読まれる
object** を渡します。descriptor の key はすべて他人の ABI で、この
list に入るべき最も明白な例なのに、**6 個のうち 3 個が入っていません
でした**。

`get` / `set` / `value` は既にありましたが**偶然**です——`get`/`set` は
Map/Set の、`value` は iterator protocol の項目として。descriptor を
名指した箇所が無かったので、他で必要とされない 3 つの flag だけが
抜けていました。

そして壊していたのは mangler の rename ではなく **dead-property pass**
です。`{ value: 1, enumerable: true }` が `{ value: 1 }` になる。
`Object.defineProperty` の default は**全部 `false`** なので、`true` の
flag を落とすと**反転**します:

| flag | 落とすと |
| --- | --- |
| `enumerable: true` | `Object.keys` が property を見なくなる（**静かに**） |
| `writable: true` | 後の代入が strict mode で **throw** |
| `configurable: true` | `delete` が **throw** |

`false` の flag を落とすのは default と一致するので無害で、最初に
試した 3 つのうち 2 つが通ってしまったのはそれが理由です
(`writable: false` / `configurable: false` で試していた)。

`// Property descriptor` group を追加し、list membership を unit test で、
挙動を `fixtures/mangle-safety/case48-property-descriptor` で Node 上で
固定しました。case には `false` flag と、落ちるべき通常の dead key も
対にして入れてあります。

`Object.defineProperties` と `Object.create(proto, descriptors)` は
最初から通っていました。`get` / `set` の accessor pair も同様です。

### 名前ではなく値が bundle 境界を越える: `tag-rewrite`

この文書の他の pass はすべて property の**名前**を扱いますが、
`tag-rewrite` は**値**を書き換えます——discriminated union の string tag
を小さい整数に。そして export を一切見ていませんでした
(`grep -n export src/transform/tag_rewrite.mbt` が空)。

```ts
// mtsc entry.ts --bundle --fold
export const c: Shape = { kind: "circle", r: 3 };
```

が `{ kind: 0, r: 3 }` になり、consumer の `c.kind === "circle"` が
`false` を返します。別 module の consumer から再現済みで、
最適化 flag は `--fold` 1 つで足ります。bundle 内の escape-sink scan では
原理的に見えません——比較は bundle の外です。逆向きも同じで、
`export function area(s: Shape)` だけが渡っていれば値を作るのは
consumer、`0` と比べるのが bundle 側です。

gate に `exported_surface_props` を使うのは間違いです。あれは
「この名前を rename してよいか」の答えで、広いのが正しく、呼ばれた関数の
body まで辿るので `export const out = area(shapes[0])`（consumer が見るのは
number だけ）でも `kind` を予約します。実際それで正当な既存 test が
1 本落ちました。値の書き換えに必要なのは狭い事実——export された宣言
**自身の値**（関数は closure ではなく `return` 式）と、export signature に
出る**型名**（consumer が値を作る向きは式の walk では見えない）——で、
`class_method_dce` が `collect_externally_visible_props` に対して必要と
した切り分けと同じ形です。

import した callee への hand-off も sink に入れました。ただし
`external_import_bindings` ではなく新設の `imported_bindings` で、暗黙
global は混ぜません: 混ぜると `Math.max(s.r)` が「tagged object を
渡した」になり、この pass が自分で持っている global catalog より
精度が落ちます。

この 2 つは `TagRewriteBoundary?` という**必須 positional 引数**で渡します
——`class_method_dce_block` の `off_bundle` と同じ形で、`None` は
「caller が計算していない」の意味で pass が何もしません。label 付きの
default にすると**開く方向に失敗**します: `externals` が空なのは候補が
減ることではなく **sink が減ること**なので。wrapper node の fail-open
default はこの pipeline で既に 2 回 soundness bug を出しています
(`TypeArgs`、`PureCall`)。

`fixtures/mangle-safety/case49-tag-rewrite-export-boundary` が両方向を
Node で回します。**最初の版は検出力 0 でした**——観測が bundle 内の
`unitCircle.kind === "circle"` で、literal ごと書き換わる比較は
`=== 0` になって true のまま。さらに別の場所の素の `.kind` 読みが
prop-uses gate を閉じ、pass は無関係な理由で declined していました。
観測を全部「export された object そのもの」に変え、gate を落とした
build で `{"kind":0,"r":1}` vs baseline の `{"kind":"circle","r":1}` が
出ることを確認しています。「pass を切っただけ」にならない側の保証
（内部専用の union は今も整数化される）は挙動として観測できないので、
`bundle_wbtest.mbt` に置いてあります。

### 既知の不精度: chain の根に observation を付ける

`seed_from_expr` は property / index chain を**根まで遡って** seed します。

```ts
class C { liveField = 1; deadmark_field = 2; }
const c = new C();
console.log(c.liveField);      // 数値 1 が出るだけ
```

`c.liveField` は数値なので、`c` の property 名は 1 つも観測されません。
それでも `C` の field 2 つが escape set に入り、`--explain-mangle` は
`deadmark_field`: the name is in the escape set と言います。

理由は避けようがない形をしています: **`c.liveField` には symbol が無く、
`c` にしか無い**。observation を付ける先が根しかないので、根に付けて
深さを over-approximate しています。**健全**（上位集合を予約する）で
**不精確**（見えない名前を予約する）。

`Call` / `CallExpr` は既に精確です——callee 本体ではなく `returns` に
伝播します。`MethodCall` は receiver に伝播しますが、method が `this` を
返しうるので妥当です。残るのは `PropAccess` / `IndexAccess` です。

これが `verify-dce-coverage` の `unused-class-field` が MISS である
理由で、harness はその理由を各行に印字します。直すには
**access path に感度のある observability**（または `Observability`
lattice に深さ）が必要で、patch では済みません。reserved set を
緩める方向は静かに壊れる方向なので、corpus / fuzzer / type-aware
measurement を見ながらの独立した変更にすべきです。

現在の挙動は `mangle_wbtest.mbt` に固定してあります。精度が上がったら
その assertion は**削除せず反転**させる——変更が byte 数だけでなく
そこに現れるように。

### module graph 単位の型検査（case19, case20）

`mtsc` は file ごとに checker を走らせていたので、import された型は
すべて未解決でした。`@mtsc.collect_module_graph_issues` に接続し、
type-only の relative import も loader が読み込むようにしました
（bundle には出ませんが、型を宣言している module が必要です）。
import 解決の diagnostic は CLI では落としています — 型としてのみ使う
値形式 import（`import { LocalObj } from "./types"` で `LocalObj` が
type alias、TypeScript としては合法）と、本当に存在しない export を
この層では区別できないためです。

### ambient `.d.ts`（case03）

entry と同じ directory の `.d.ts` を program に含め、import / export を
持たない script 形式の宣言ファイルを ambient として全 module の scope に
入れます。`tsc` は tsconfig の `include` でこれを行いますが、mtsc は
tsconfig を読まないので `env.d.ts` / `globals.d.ts` 慣習に合わせました。

あわせて、**bundle が宣言していない名前は host のもの**という規則を
mangler に追加しました。ambient global の property surface は host の ABI
であり、`MyGlobal.f({ x: 1 })` の引数 key も `MyGlobal.f()` の戻り値から
読む key も rename できません。

### checker のギャップ 3 件

- mapped type への indexed access（`Info["dog"]`）: `simplify_indexed_access`
  は resolver を持たないので `Named` base で `Any` を返していました。
  resolver 側で base を先に解決してから simplify します。
- constructor の default parameter: `lookup_constructor_sig` が
  `constructor_param_defaults` を捨てていたため、`new C()` が TS2554 に
  なっていました。
- object spread の推論: `infer_block_return` が block の local binding を
  bind していなかったため、`const r = f(); return { a, ...r }` の spread
  member が推論 shape から落ちていました。
- namespace 内の `const v = 1` が `int` になり `number` に代入できない件は、
  assignability に `Int → Number` を追加しました（TypeScript の数値型は
  1 つで、`Int` はこの AST の整数マーカーです）。

## 既知の制約

- `export let x` を namespace 内部で再代入した場合、外から `N.x = v` と
  書いても local には伝播しません（読み取りは getter 経由で live）。
- `namespace A.B { … }`（dotted path）と `module "foo" { … }` は lowering
  対象外で、従来どおり erase されます。
- `mtsc` の import 解決 diagnostic は CLI では出しません（上記）。

provenance 解析については、名前を挙げられる範囲で次の 3 つが残っています。
いずれも「反転して塞いだ穴」より狭く、塞ぐには別の道具（expression 単位の
型伝播 / import 由来の binding 集合の追加配線）が必要です。

- **built-in namespace 名を shadow する import.** allowlist の判定は名前
  一致です。`import { Map } from "immutable"` のように built-in と同名の
  binding を import すると、built-in 側の答え（pure constructor）を返します。
  *宣言された* shadow（`const Math = …`）は symbol graph で検出して除外
  しますが、import header は symbol graph に binding を作らないので見え
  ません。
- **内部 object が保持する foreign 関数.** `const o = { cb: ext.f }; o.cb(x)`
  は receiver が内部なので内部呼び出しと判定します（反転前と同じ扱い）。
- **export された関数の callback parameter.** `export function run(cb) { cb(payload) }`
  の `cb` は consumer が渡すので foreign ですが、parameter の出自を
  「export surface から到達可能か」で判定する配線はまだありません。
- **provenance は名前単位.** `host_provenance_names` は symbol graph が
  できる前に走るので、ある scope で host-shaped と判定した `data` は
  bundle 全体の `data` を host-shaped にします。過剰予約側に倒れるので
  安全性は保たれますが、精度は落ちます。

## この検証で入った checker の変更

`Resolver::unwrap` は最外層の型しか展開しません。ほとんどの規則には
それで十分ですが、resolver を持たない `is_assignable_to` は
`Array` / `Tuple` / `Rest` の中で見つけた `Named` を解決できません。結果、

```ts
type I = { start: number; end: number };
const xs: I[] = [1].map((n) => ({ start: n, end: n }));  // 同一の shape で mismatch
```

が誤検出になっていました。`Resolver::unwrap_containers` が container 層の
中まで展開します。展開は all-or-nothing です — 再帰 alias
（`type A = [string, ...B]; type B = [string, ...A]`）は不動点に展開できず、
*部分的* な展開は展開しないより悪い（片側だけ 8 段展開されて `Named` の
尾が残り、等価な型が不等価に見える）ので、alias 名を辿り直した時点で
外層 `unwrap` のみの従来動作に戻します。element 位置では、`extends` も
index signature も type parameter も持たない「素の」interface だけを
構造型に展開します。それ以外は今の動作を維持します。

TypeScript 7 conformance corpus に対する計測: false positive 0 件（budget
どおり）、true positive 2,338 件（変化なし）、true negative 1,749 → 1,750。
精度が上がり、退行はありません。case14 と case21 がこの修正で unblock
されました。

変更後の計測（TypeScript 7 conformance corpus）: false positive 0 件
（budget どおり）、true positive 2,338 → 2,339、true negative 1,749 →
1,750。精度が上がり、退行はありません。

```bash
just verify-checker-soundness
```

なお `unwrap_containers` は union / intersection の member まで展開します
（`type Ext = Base & { to: string }` が同等の object literal と一致しな
かった）。展開の all-or-nothing 規則は同じです。

`infer_block_return` の local binding は、child env に copy するのでは
なく caller の env に足して抜けるときに外す形にしています。`full_snapshot`
は `vars` しか運ばないので copy すると `declared` slot が落ち、推論が悪化
して conformance に false positive が 1 件出ました。

## case52: 素の `--bundle` が間違った binding を返していた

corpus に 1 件足しました。mangle の bug ではありません——`mtsc --bundle`
が、最適化 flag 無しで**間違った関数を呼ぶ bundle** を出していました。

```ts
// barrel.ts
import * as Type from "./shapes";
export * from "./helpers";   // helpers.ts は top-level に `Type` を宣言している
export default Type;
// index.ts（consumer）
import Type from "./barrel";
Type.Number(7);              // TypeError: Type.Number is not a function
```

linker の phase 1 は衝突を解いて namespace object を `Type$N` に rename
し、その名前を `namespace_local_renames` に記録します。`resolve_export`
の fallback は `rename_per_module` **だけ**を読んでいました。そこに
namespace local の entry は存在しないので、source の綴り `Type` が
そのまま返り、`helpers.ts` の arrow に bind されます。

**free variable ではなく間違った binding** です。bundle は読み込めて、
違う関数を呼ぶ。だから `--verify` は検出しません——名前は全部解決する。
`export { NS }` / `export { NS as Alias }` も同じ fallback を通るので
同時に壊れていました（case は両方観測します）。

case が `mtscArgs` を持たないのはそのためです。baseline leg が
問題の path そのものです。fix を戻すと case は落ちます:

```
[REGR] case52-namespace-default-export        fail (expected pass)
       baseline: {"error":"TypeError: Type.Number is not a function"}
```

この bug は library の package entry では出ません——barrel 自身の
`export default` を誰も import しないからです。`measure-type-aware --app`
（application entry を測る）を入れて最初に出てきたのがこれでした。

## case53 / case54: `.name` 読み 1 箇所が bundle 全体の callable を予約していた

実バンドルの head-to-head（`just compare-terser-bundles`）で mtsc は
typebox で terser に **+51.6%** 負けていました。corpus 中で最悪です。
原因は 5,000 行中の **1 行**です。

```js
IsEqual(proto.constructor.name, "Object")
```

`observed_names.mbt` は `.name` 読みの receiver を class 階層に narrowing
できないとき、bundle 全体の callable 名を予約します。`proto.constructor`
は任意の constructor なので narrowing できず、fail-closed で wildcard。
その 1 行を消すと 119,933 → 90,042 byte（−24.9%）、top-level 関数 842 個が
フルスペルから 1〜2 文字になります。

修正は 2 段で、どちらも既存の信頼済み機構を再利用しました。

### 83a: `call_inline` の引数純粋性は body の質問だった

`try_inline_trivial_call` は**すべての引数が pure**であることを要求して
いました。この要求が防いでいるのは 3 つ——引数の効果を**複製**する、
**落とす**、**並べ替える**——で、3 つとも「body がどこで parameter を
読むか」の質問です。body が各 parameter を**引数順に、無条件に、正確に
1 回**読むなら、代入後の式は call と同じ操作を同じ順で行います。近似
ではなく同一です。

これが実務で効くのは、getter 修正以降 `is_pure_value` が**あらゆる
property 読みを impure と判定する**からです。1 行の `IsEqual` helper は
property を読む call site では一度も inline されていませんでした。
typebox はそれを 160 回呼びます。

`params_read_in_argument_order` は式の形の**allowlist** です。知らない
node は relaxation を断ります——順序規則で「見ていない形を安全と仮定
する」のが一番危ないので。

### 83b: 比較されたリテラルだけを予約する

`collect_read_property_names_expr` に `<expr>.constructor.name === "lit"`
の arm を足し、reserve-everything の sentinel の**代わりに**リテラルを
記録します。**信頼済み walker の中で認識する**ことが完全性を構成的に
保証します——他の位置の読みは generic path に落ちて今でも全 callable を
予約するので、**形を取り逃がすと byte を損するだけで正しさは損なわない**。
sentinel channel 自身とは逆向きの fail 方向です。

リテラルを予約すると 2 つの仕事が同時に片付きます。

- すでにその名前の class が rename されない（`Shape`）
- どの class もその名前に rename されない（`"a"`——mangler が最初に配る
  名前）。予約された名前は**生成 pool からも外れる**ので。

2 番目が素朴な実装が落とす方向で、`case53` は両方を観測します。片方だけ
の実装は mutation で `shapeIsShape` が true→false、もう片方だけなら
`shapeIsManglerName` が false→true になります。

`case53` の direction 2 は 1 文字空間**全部**（`a`..`h`）と比較します。
どの class がどの文字を貰うかは bundle 全体の参照数で決まるので、1 文字
だけ書いた case は mangler の順序が動いた瞬間に**黙って**検出を止めます。
空間を覆えば割り当てに依存しません。同時にコストも正直に出ます——1 文字
8 個の予約は高く、それが「constructor 名を `"a"` と比べる」コードの値段
です。実コードは `"Object"` と比べるので、コストは 0 です。

結果: typebox 119,933 → **90,056**、terser 比 **+51.3% → +13.8%**、
gzip も +27.1% → +17.4%。他 8 target は byte 完全一致（この形が無い）。

### そして case54 が本当のバグを掘り出した

`case54` は 83a を覆うために書いた case で、**修正済みのコンパイラで
落ちました**。下に別のバグがありました。

```js
const add = (a, b) => a + b;
let b = 3;
add(b, 1)
  a := b   ->  b + b
  b := 1   ->  1 + 1     // 2、答えは 4
```

`try_inline_trivial_call` は parameter を**逐次**代入していたので、後の
parameter の代入が、前の代入が持ち込んだ名前を書き換えていました。
**引数は両方 pure** なので 83a とは無関係に前から到達可能で、
`--bundle --minify --fold --treeshake --mangle` で **3 つの call site が
4/103/10 のところ 2/200/14** を返していました。crash も free variable も
出ないので `--verify` も検出しません。

**mangle が inline より前に走る**ことがこれを例外ではなく常態にします:
parameter は `a`,`b`,`c` で、引数が言及する top-level binding も
`a`,`b`,`c` です。この pass の "Scope narrowing" 節が別の理由で書いて
いるのと同じ罠です。

修正は同時代入で、既存の 1 名前置換を 2 段に使います: 各 parameter を
`@@inline-arg:<i>`（JS の識別子になり得ない）に改名してから、placeholder
を引数に置き換える。どちらの段も capture できません。

pin は **unit test** です。end-to-end の fixture (`case55`) を先に書いた
のですが、**修正を mutation で戻しても PASS しました**——衝突が起きるには
mangler が top-level binding と後続 parameter に同じ短名を配る必要があり、
その fixture では別の名前を配ったからです。バグがあるのに落ちない case は
coverage の形をしただけの何かなので、出荷せず削除しました。
`case54` は偶然この bug も捕まえますが（`tap` が mangle 後に衝突する）、
それは運であって coverage ではない、というのが unit test がある理由です。

## case55: inline した VALUE の自由変数が、着地先の scope で解決し直される

`case43` は「表の KEY が shadow される」側を押さえます。これは**もう半分**
で、長らく誰も聞いていませんでした。KEY が re-bind された entry を落として
も、**代入される VALUE が読む名前**については何も言っていません。そして
その名前は、値が splice された先で解決し直されます。

```ts
const base = Number(process.argv.length);   // 2
const f = () => base;
function g() { const other = 99; return f() + other * 0 }
console.log(g());
```

`--bundle --treeshake --fold --minify --mangle` で **mtsc は 99**、
答えは **2** です。

**mangler は inline phase より前に走り**、`base` と `other` に同じ短名 `a`
を配ります——mangle 時点で `g` の body は `base` を言及しないので、shadow
して構わないからです。その後 inliner が `f` の body（その `a` は**外側**）
を、`a` が 99 の scope に splice する。crash も free variable も出ないので
`--verify` は見えません。そして **mangler が仕事をするほど衝突は増えます**。

自由変数を持ち得る値を代入する表は 4 つあり、どれも確認していませんでした:

| pass | 代入する値 |
| --- | --- |
| `call_inline` | 関数 body の式 |
| `as_const_inline` | 配列 / object の要素（shapes と scalars の両方） |
| `predicate_inline` | 型 guard の body |
| `switch_fold` | 一致した arm の式 |

`const_enum_inline` と `type_fold` はリテラルを代入するので構造上安全です。

修正は**共有 helper 側**に置きました。1 つの規則が複数箇所に書かれて 1
箇所だけ直る、をこのパイプラインで 7 回やっているので。義務は
**trait (`SubstitutedValue`)** で表現しています——値型が答えられない表は
コンパイルが通りません。既定値付きの optional predicate にすると
「何も言及しない」で fail open し、次に追加される表が 5 つ目になります。

自由名の収集は `collect_var_refs_expr`、**mangler 自身の walker** を使い
ます。mangler の正しさがその網羅性に依存しているので、catch-all で fail
open する余地がない唯一の name walker です。

再現できたのは 2 つ（`call_inline` と、`switch_fold` が作る形——ただし
bisect すると代入しているのは `call_inline` 側）。`as_const_inline` と
`predicate_inline` は **mangler より前に走る**ので mangler が後始末をし、
witness は作れませんでした。修正は構造上この 2 つも覆いますが、
**「壊れている」とは書きません**——示していないので。その 2 つのために
pass 境界の unit test（`call_inline_wbtest.mbt`）を足しています。mangler
が何をするかに依存しない位置だからです。

`case55` は mutation self-check を通ります: 値側の判定を落とすと
`[REGR] case55 fail`。

**バイト代**: 9 MB の `typescript.js` は byte 完全一致。type-aware corpus
9 target の合計は **−76 bytes**（typebox +327、excalidraw +150 に対し
ts-pattern −345、immer −192、hono −16）。inline を減らすと後続の
single-use binding inliner と treeshake が別の形を見て、しばしば得をする
ためです。`inline` phase の時間も 397 → 351 ms で悪化していません。

## case57: alias された import の代入先が、参照地点で shadow されている

これが scope narrowing 族の **7 件目**で、最後まで聞かれていなかった場所
——**linker** です。

linker は `subs[local_alias] = resolved` を記録し、importing module の中で
`Var(local_alias)` を `Var(resolved)` に書き換えます。書き換え walker は
**置き換えられる側**の shadow を追跡します（内側 scope が alias を再束縛
すればそちらが勝つ）。**代入する側**は追跡できません——その名前は walker が
narrow する map に入っていないので。

`@sprawlens/viz` の `App.tsx`（1 つの component body の中）:

```ts
import { parentFileOf as contractParentFileOf } from "@sprawlens/schema";
const moduleOfId = (id) => currentModuleIdOf()(contractParentFileOf(id));
...
const parentFileOf = (id) => symbolMetaRef.current.get(id)?.fileId ?? …;
```

source は正しい——alias された import と局所 `const` は別名です。
ところが bundle には **`contractParentFileOf` が 0 回**しか出てこない。
全部 `parentFileOf` になり、その位置では局所 `const` に解決され、
arrow が render 中に走った時点でまだ TDZ:

```
ReferenceError: Cannot access 'parentFileOf' before initialization
```

**素の `mtsc --bundle --no-check`**、最適化 flag なし。265 file の preact
アプリが「bundle はできるが動かない」状態でした。

失敗の形は 2 つあり、見え方が全く違います:

| 形 | 症状 | `--verify` |
| --- | --- | --- |
| shadowing 宣言がまだ走っていない | `ReferenceError`（TDZ） | 見えない |
| もう走っている | **静かに違う値**（局所関数の答え） | 見えない |

どちらも名前は解決するので verifier には見えません。

### 修正: 書き換え地点で scope を歩くのではなく、代入する名前を mint する

phase 2 は `resolved != local_alias` を**既に計算しています**——それが
そのまま危険条件です。同名なら phase 3 は何も置換せず、importing module
の scope が source どおり決める。異なるなら、代入先を **`name$N`**（mint
名）に強制します。`name$N` は source が宣言する名前ではないので、
どの scope も shadow できず、それを知るための解析が要りません。
`taken` が top level の一意性を既に保証しています。

書き換え地点で scope を歩く案は**採りませんでした**。walker が binder の
形を全部モデルする必要があり、1 つ漏らしたときの代償がこのバグの静かな
再発だからです。mint 名なら構造的に安全です。

phase 1.5 として phase 1 の直後（`runtime_bindings` を組む前）に置きます。
触るのは「どこかで別 alias で import されている binding」だけで、
`--mangle` を付ければ名前はどうせ置き換わるので **corpus は byte 完全一致**。

`fixtures/mangle-safety/case57-aliased-import-shadowed-target` が 4 つ並べ
ます: TDZ 形、静かに違う値の形、**parameter** で shadow する形（block 宣言
ではないので block レベルの検査では見えない、`case43` と同じ罠）、そして
shadow されていない対照（「置換をやめる」修正では落ちる）。
mutation self-check を通ります。

そして実アプリが動くようになりました: `@sprawlens/viz`
**875,544 → 357,712 byte（59% 減）**、最適化前と最適化後で
**同一の DOM を render**（root 27 child、body 287 byte、digest 一致、
unhandled rejection 0）。

## case58: `#private` 名も rename する

property mangler は `#name` を全部飛ばしていました。skip の理由は 2 つ
書かれており、**本当だったのは 2 つ目だけ**です:

* 「`#private` は外から到達できないので**隠すものが無い**」——正しく、
  そして無関係です。これは **byte** の話で、hono の
  `#notFoundHandler` は 16 文字、`#a` は 2 文字。
* 「rename すると `#` が落ちて、private field が**ただの見える
  property に戻る**」——bare な mint については正しいので、mint 側で
  `#` を保つようにしました。

`#private` 名は **証明が一切要らない唯一の property クラス**です。言語
規則で class scope に閉じており、consumer も reflection も serialization
も computed access も名指しできない。だから candidate 判定を
**reserved set より前**に置きました——reserved set は「外から見えるか」に
答える集合で、`#` 名についてはescape 解析が何と言おうと答えは No です。
測定 10 target のうち 6 つが wildcard を予約するので、reserved の後ろに
置いたままだと**pass がもともと不活性な場所でこそ** private が残ります。

mint は `#` を保つので private namespace に落ちます: `#a` は予約済みの
public 名と等しくなり得ず、同じクラスの public `a` とも衝突しません
（JavaScript では別メンバー）。異なるクラスの `#path` が両方 `#a` に
なるのも正しい——それぞれ自分のクラス body で解決します。

### 効果

hono、shipping flag + `--mangle-properties`:

| | bytes |
| --- | --- |
| `--mangle` のみ | 20,951 |
| `+ --mangle-properties`（前） | 20,721 |
| `+ --mangle-properties`（後） | **18,845** |

**private 名の rename だけで −1,876 byte**、`--mangle-properties` 全体で
**−2,106 byte（−10.1%）**。他の 9 target は `#private` を持たないので
byte 完全一致です。

そして #78 の結論がこれで一段はっきりします: property mangler の
「全 library で candidate 0」は、**escape 解析を必要としない candidate
クラスが 1 つ存在する**という形で崩れました。

### case の検出力について

`case58` は **safety case で、最適化の pin ではありません**。rename を
mutation で戻しても pass します——private を rename しないこと自体は何も
壊さないので、それは正しい挙動です。検出するのは古い skip が名指しして
いた本当の hazard で、mint から `#` を落とすと **fail します**:
private がただの property になり、`Object.keys` / `JSON.stringify` /
spread / `for…in` の 4 つ全部が見えるようになるからです。

byte の側は上の hono の数字と `--explain-mangle` の census 行
（`kept N #private (class-scoped, no proof needed)`）が押さえます。

### 途中で見つかった checker の 2 つの穴（修正済み）

`case58` を書く過程で、fixture が compile できずに 2 回落ちました。
どちらも mangler とは無関係の checker 側の穴で、どちらも fixture を
**その穴を避ける形に書き換えれば消えます**——それが、この 2 つが
今まで生き延びた理由そのものです。corpus からこれらに当たる経路が
無いのは、当たる fixture を誰も書かなかったからで、pass が正しいから
ではありません。

#### 1. `#x in obj` が `cannot find name __private_brand__0__path`

ES2022 の ergonomic brand check、class の type guard の定型です:

```ts
static isRouter(v: unknown): boolean { return #path in (v as Router) }
```

parser は expression 位置の `#x` token を
`Var("__private_brand__N__x")` に lowering します。brand は class の
**member** を指す名前で、binding として宣言されるものではないので、
環境に entry は無く、探しても見つかりません。`check_undefined_name` が
brand prefix で早期 return します。prefix を条件にしたのは、それが
曖昧さの無い判定だからです——この綴りを作るのは
`mangle_private_name` だけで、しかも `#` 始まりの source token に
対してだけ作ります。

同じ形で **mangler 側にも穴**がありました。`in` の左辺は property
位置ではないので `rename_properties_in_expr` は素通ししていて、class
body の `this.#path` は rename され `in` の operand はされない——plain
`mtsc --bundle` が `__private_brand__0__path in v`、つまり何も指さない
参照を吐いて `ReferenceError`、`--mangle-properties` では宣言が `#a`
になって `in` 側に `#path` が残る。`case58` がこの両方を Node で
押さえます。

#### 2. array built-in の optional / rest 引数が全部「必須 1 個」

`arr.sort()` が `expected 1 argument(s), got 0` で落ちます。
`array_prototype_member` の table が、**optional 引数を必須として、
rest 引数を 1 slot として**宣言していました:

| 書き方 | 旧 table の判定 |
| --- | --- |
| `arr.sort()` | expected 1, got 0 |
| `arr.slice()` | expected 2, got 0 |
| `arr.join()` | expected 1, got 0 |
| `arr.push(a, b)` | expected 1, got 2 |
| `arr.flat(2)` | expected 0, got 1 |

表現する機構は最初からあって、table が使っていなかっただけです:
`required_arity_from_types` は「`undefined` を受ける型の引数は省略可能」
と読み（parser が `x?: T` を `T | undefined` に広げるので）、`Rest` に
対しては必須数を上げません。つまり修正は **table が意味を言うだけ**。

`fixtures/mangle-safety/case59-array-builtin-arity` が 18 の形を
mtsc でコンパイルし、同じ source を Node でも走らせます。mutation
self-check は検出します（`[REGR] case59 blocked-compile … expected
1 argument(s), got 0`）。

そして **この case の初稿は、自分がその場で入れたバグを通しました**。
`concat` の正しい signature は `(T | T[])[]` で、union の両側が
効いています——旧 table の `Func([arr_t], arr_t)` は `a.concat(9)` を
拒み、`rest(elem)` と書き直すと `a.concat([2, 3])`、つまり実コードが
ほぼ必ず使う形を拒みます。初稿には bare element の形しか無かったので、
反対方向に間違った signature を pass させました。union の片側しか
持たない case は、その 2 つを区別できません。

## case60: property 書き込みの 4 つの綴りのうち、index されていたのは 1 つ

これは #73（class-method-DCE の suppression を class 単位に狭める）の
**天井を測ろうとして**見つかったもので、harness が見つけたものでは
ありません。そして測った結果、#73 は**やる価値が無い**と分かり、
代わりに `--bundle` 素の path に入っている本物の不健全性が出てきました。

### まず天井: 10 target 中 8 つで 0

`--explain-mangle` の `unused class methods` 節は、suppress されたときに
「もし gate が開いていたら何個消えたか」を印字します。それが narrowing の
上限そのものです。10 target 全部に訊きました:

| target | class-method-dce の判定 | 天井 |
| --- | --- | --- |
| typebox / immer / neverthrow / ts-pattern / superstruct / valibot / sprawlens | `nothing to do — every declared method is read somewhere static or is on the export surface` | **0** |
| remeda | `nothing to do — the bundle declares no classes` | **0** |
| excalidraw | SUPPRESSED | 5 method |
| hono | SUPPRESSED | 18 宣言 = **distinct 9 個**、全部 `HonoRequest` |

8 target は suppression に到達すらしません（#88 で入れた early exit が
「消すものが無い」と言って抜けます）。CLAUDE.md には
「10 target すべてで SUPPRESSED」と書いてありましたが、**もう正しく
ありません**。gate を狭める作業の上限は、corpus 全体で
`5 + 9 = 14 method` です。

### そして hono の 9 個は headroom ではなく、隠れていたバグだった

distinct 9 個は `HonoRequest.param` / `parseBody` / `valid` / `queries` /
`blob` / `bytes` / `matchedRoutes` / `routePath` / `addValidatedData`
——hono を使うアプリが `c.req.param("id")` と書く、**その public API
そのもの**です。それが「到達不能」と判定されているのは最適化の機会では
なく、export surface の穴です。つまり #73 を実装して gate を開けたら、
**このバグを出荷していました**。suppression が唯一の防波堤でした。

### 4 つの穴

`index_prop_assigns` の doc comment は「`NAME.prop = value` を index する」
と書いてあり、実際に index していたのは**その 1 綴りだけ**でした。

```ts
class Req { param(k: string) { return k } }
export class Ctx {
  #req: Req | undefined;
  get req(): Req { this.#req ??= new Req("r"); return this.#req! }
}
```

`mtsc index.ts --bundle`（最適化 flag **無し**）が `Req.param` を削除し、
consumer 側は `TypeError: c.req.param is not a function`。Node に同じ
TypeScript を直接走らせると `r:k` を返します。

| 穴 | 綴り | 原因 |
| --- | --- | --- |
| H1 | `NAME.prop ??= v`（`\|\|=` / `&&=` も） | `CompoundAssignExpr` の arm が無い。**実コードが lazy member を書く綴り**で、hono の `#req` / `#matchResult` / `#path` がこれ |
| H2 | `NAME["prop"] = v` | `IndexAssign` / `IndexAssignExpr` の arm が無い。`NAME.prop = v` の別の書き方 |
| H3 | `return bag.prop` | `surface_lookup_member` が object literal の entry（`undefined`）で解決して**止まる**。literal の entry は `bag.prop` の必要条件であって十分条件ではない。`return bag` は最初から通っていて、それがこれを「動いているように」見せていた |
| H4 | `this.#priv = v` | `surface_escape_class` が値の escape を `is_internal_marker_prop` の filter の**内側**に置いていた。filter が答えるのは「この NAME を予約してよいか」（否——`__private_brand__0__req` は誰も綴れない）で、値については何も言っていない。**public field の同じ class は通る**のが tell |

H4 は「1 つの規則が 2 箇所に書かれ、1 箇所でしか適用されていない」の
**9 回目**です。top-level の `prop_assigns` loop（同じ file の 60 行上）は
escape を filter の外に置いていて、正しかった。

非 literal の computed key（`NAME[k] = v`）は名前が綴れないので予約
できませんが、値はオブジェクトの中に入って出ていきます。この file に
既にある `@@computed:` sentinel（`is_opaque_object_key`）に記録して、
名前の予約だけを外しました。

### H3 の修正が非終了を持ち込んだ（自作のバグ、既にあった memo を使わなかった）

「literal の entry で止めず、記録された write も辿る」を入れた直後、
corpus が**止まりました**。CPU 競合だと 20 分ほど誤解していましたが、
`ps` を見ると `case36-annotated-boundary` を処理中の mtsc が 3 本、
最長 25 分。5 行に最小化できます:

```ts
const ledger = { n: 0 };
export function bump() { ledger.n = ledger.n + 1; return ledger.n }
```

`ledger.n` を escape すると write `ledger.n + 1` を escape し、その左辺は
また `ledger.n`。`ledger.n = 1` なら 10 ms、`ledger.n + 1` なら永久。
`case36` はまさにこの increment を持っています。

止めるのは `(receiver, key)` を key にした memo で、**同じ file の
20 行先に既にあったもの**です——`surface_should_walk` の doc comment が
「これが無いと実コードで終わらない。neverthrow は 5 file 33 KB で
7 分たっても終わらなかった」と、この失敗モードそのものを説明しています。
それを使わなかったのが原因です。

memo の depth keying は保守側に効きます（浅い到達は再walk、深い到達
——cycle がそれ——は停止）。1 点だけ順序が要る: `resolved` は memo が
declineする**前に** entry 走査から立てます。さもないと 2 回目の到達が
下の widening に落ちて、cycle が hang ではなく**過剰予約**に化けます。

unit test を 2 つ入れました。2 つ目が本題で、**key だけを key にした
memo では捕まらない相互形**です（`a.toB = b; b.toA = a`——どちらの
write も自分の key を読んでいない）。

### case60 の設計をやり直した: external 経路は別の解析だった

初稿は 6 つの holder の内側のオブジェクトを **`--external` module** に
渡して、そこで `param` を呼んでいました。corpus で **fail** しました——
そしてそれは正しい失敗でした。external call に値を渡す経路は
**off-bundle reachability**（`class_members_reachable_off_bundle`）で、
export surface とは別の解析です。しかもそちらは escape する値を
**holder に帰属**させ、その中に入っている class には帰属させません。
つまり初稿は bug を再現してはいたが、**修正について何も証明していな
かった**——export surface を一度も通っていないので。

draft 2 は driver 方式にしましたが、**修正を revert しても pass
しました**——検出力ゼロ、この repo が何度も記録している
coverage-shaped そのものです。原因は自分が置いた **control class**
でした。`prop_assigns` は receiver の**名前**で引くので、`this` は
bundle 内の全 class の**和**になります（`surface_escape_class` の
comment 自身がそう書いています）。holder 6 つが payload class を
共有していたため、control の素の
`this.slot = new Payload(…)`——最初から通っていた唯一の綴り——が
その class に到達し、**6 つ全員の method を keep していました**。

draft 3 では **holder ごとに専用の payload class と専用の method 名**
を持たせました。index されない綴りは何にも到達せず、その holder の
method だけが死にます。`param` を呼ぶのは `driver.mjs`——bundle の
**外**、コンパイル後です。bundle の中にそれらの名前は 1 つも無いので
static access collector では pin できず、`--external` を使わないので
off-bundle reachability も何も足しません。**export surface だけ**が
keep できます。それが試験対象の経路です。

`bag.counter = bag.counter + 1` も case に入れてあります（上の非終了）。

重要なのは **reference leg が検出している**ことです。この削除は mtsc の
**全 leg で起きる**ので、mtsc 2 本を比べても一致します——CLAUDE.md が
何度も記録している self-comparison の失敗そのもので、5 つの
scope-narrowing bug がそれで数千 seed を生き延びました。ここで比較相手に
なっているのは Node が同じ TypeScript を走らせた結果です。

この case が**できないこと**も書いておきます。「消しすぎていない」側は
値比較では見られません（reference leg には method があるので、absence は
観測できない）。そちらは `just verify-dce-coverage`（marker が消えている
ことを assert する）と type-aware corpus の byte 差が見ます。

### 5 つ目: 綴れない computed key（reasoning だけで書いていた arm）

`NAME[k] = value` で `k` が literal でない場合、名前は予約できません
——どれなのか分からないので——が、**値はオブジェクトの中に入って出て
いきます**。この file に既にある `@@computed:` sentinel
（`is_opaque_object_key`）に記録して、consumer 側は名前の予約だけを
withhold する、という arm を足しました。

これは **witness 無しで、reasoning だけで書いた**箇所でした。この文書の
残りの履歴を踏まえるとそれは不十分なので、後から確認しました:

```ts
class Payload { readComputed(k: string): string { … } }
const holder: Record<string, unknown> = {};
function pickSlotKey(): string { return "slot" }   // call 経由なので畳めない
holder[pickSlotKey()] = new Payload("computed");
export const out = holder;
```

| leg | 結果 |
| --- | --- |
| Node が同じ TypeScript を実行（oracle） | `computed:k` |
| 修正前の `mtsc --bundle` | `TypeError: mod.out.slot.readComputed is not a function` |
| 修正後の `mtsc --bundle` / 全 flag | `computed:k` |

つまり arm は**効いていました**——同じ族の 5 つ目です。`case60` に
6 番目の holder として入れたので、これも comment ではなく witness で
押さえられています。

### 修正の効果と代償（実測）

soundness 側を広げた修正なので byte を払うのが普通ですが、**10 target
すべて byte 完全一致**でした:

| target | 修正前 | 修正後 |
| --- | --- | --- |
| hono | 18,839 | 18,839 |
| valibot | 86,861 | 86,861 |
| typebox | 87,696 | 87,696 |
| immer | 20,116 | 20,116 |
| neverthrow | 5,125 | 5,125 |
| ts-pattern | 8,152 | 8,152 |
| superstruct | 10,394 | 10,394 |
| excalidraw | 276,573 | 276,573 |
| sprawlens | 370,414 | 370,414 |
| remeda | 28,459 | 28,459 |

0 byte は「pass が実コードで発火していない」の可能性もあるので、そこは
別の観測で確認します。**hono の判定が変わりました**:

```
修正前: SUPPRESSED — a sink in the bundle can observe a member name…
        would have dropped 18 unreached method(s):
          HonoRequest.param / queries / parseBody / bytes / blob /
          addValidatedData / valid / matchedRoutes / routePath

修正後: nothing to do — every declared method is read somewhere static
        or is on the export surface, so the reachability analysis was
        skipped.
```

つまり `HonoRequest` の public API 9 個が export surface に**乗るように
なった**——`#req ??= new HonoRequest(…)` という実物の綴りを辿れている
直接の証拠です。corpus 全体の #73 天井は **14 method から 5**
（excalidraw のみ）に下がりました。

byte が動かない理由はこの文書と CLAUDE.md が別の 4 方向から到達している
結論と同じです: これらの library では当該の名前が**別の経路でも既に
予約されている**（property 名 candidate は 9 target 中 7 つで 0 個）。
予約集合は「大きい」のではなく**網羅的**なので、予約経路を 1 つ増やして
も減らしても byte は動きません。DCE coverage も 31 eliminated /
0 broken で不変——過剰予約に振れていないことの確認です。

## 却下: `--verify` に「宣言された member の到達可能性」を足す案

この 5 つの穴（case60 / case61）はどれも `--verify` に見えません。
名前は全部解決するので、free variable も crash も出ないからです。
そこで「名前解決ではなく**宣言された member が出力に在るか**を検証する」
案を検討しました。**実装せず却下**します。理由は測って出しました。

### 判定の中心は誤検出率

`verify.mbt` は意図的に fail-quiet です——狼少年になった verifier は
切られるので。そして `class_method_dce` は**正しく**到達不能メソッドを
削除します。素朴な「宣言されたのに無い」チェックは、その正しい削除を
全部拾います。

corpus 10 target で測ると `--bundle` で 46 クラスを比較して誤検出は
**実質 0**（1 件は hono が `Node` という名前のクラスを 2 つ持つことに
よる、測定側の同名マージ artifact。バンドルに出るのは reg-exp router の
`Node` で、trie router の方は丸ごと tree-shake されています）。

**これは「チェックが精密」の証拠ではありませんでした。** #73 で分かって
いる通り、この corpus では `class_method_dce` が 8/10 で早期脱出し、
hono と excalidraw では suppressed です。0 は「パスが発火していない」の
0 でした。削除が実際に起きる場所で確かめる必要があります:

```ts
class Widget {
  live(): number { return 1 }
  deadNeverCalled(): number { return 2 }   // 誰も呼ばない・export もしない
}
export const out: number = new Widget().live();
```

```
FLAGGED: Widget.deadNeverCalled  (a CORRECT deletion)
```

`verify-dce-coverage` が「消えること」を assert しているメソッドを
flag します。つまり素朴形は**使えません**。

### 抑えるには検証対象と同じ解析が必要になる

正しい削除と誤った削除を分ける情報は「consumer から到達できるか」——
すなわち **export surface / off-bundle reachability そのもの**です。
それは今回バグっていた当の解析なので、verifier がそれを使えば
**検証される側とコードを共有**します。`--verify` の価値は
「passes と何も共有しない第二の目」であることなので、それを失うと
残るのは名前解決チェックだけです。

### では何が見るのか（既にあるもの）

この種のバグを見られるのは、外部 oracle を持つ実行差分だけです:

* `case60` / `case61` — payload の method を**バンドルの外**（`driver.mjs`）
  から呼び、Node が同じ TypeScript を走らせた結果と比較。5 つの穴は
  mtsc の全 leg で起きるので、mtsc 同士の比較では一致してしまいます。
* `case.json` の `expectKeep` — 「外から見える」と人間が宣言した名前に
  ついて、まさにこの「宣言されたのに無い」チェックを行っています。
  健全に成立する唯一の場所が、人間が外部可視性を宣言した名前の上、
  というのがこの案の答えです。
* `just fuzz-mangle` の `lazyHolderGroup` — 同じ形を seed から生成。

### 測定側で 2 つバグを踏んだ（記録）

1. 除外パターンを**絶対パス**に当てていた。corpus は全て `_build/` 配下
   なので、リポジトリ自身のビルド出力を除外するつもりのパターンが
   ソース 100% を捨て、`declared-but-absent 0` を返しました。探していた
   答えとそっくりの形です。`compared` 列を併記していたから
   「0 classes」で気づけました。**測定値と一緒に「何を測ったか」を出す。**
2. `--mangle` は**クラス名も rename** します。メソッド名（property）が
   rename されないことは考慮したのに、クラス名を見落とし、
   `shipping-no-propmangle` 行は全 target `0 classes` = 無情報でした。
   名前で突き合わせるなら mangle 前か rename map が必要です。
