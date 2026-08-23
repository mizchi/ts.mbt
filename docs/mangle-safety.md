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
