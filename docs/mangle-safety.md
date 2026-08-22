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

corpus は packelyze の `packages/transformer/fixtures`（`case00`〜`case25`、
重複の `case07-missing` を除く 25 件）を TypeScript source ごと移植した
ものです。`_expected.js` は持ち込まず、期待値は「特定の mangler の出力」
ではなく「振る舞い」として `case.json` に書いています。

### 現在の結果

25 件中 **18 件 pass、7 件 blocked**（下記のギャップで compile が通らない）、
安全性違反 0 件。

初回実行では 12 件が fail しました。内訳と対処:

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| exported const / function が返す object の key が **削除** される（case18/22/23/24） | reserved set が entry module の *宣言された* 型からしか作られていなかった。他 module の型で注釈された値や、推論された return shape は誰も読まないと判定され dead-property pass が消していた | `export_surface.mbt` を追加 |
| exported 関数の推論 return shape の key が rename される（case16） | 同上 | 同上 |
| external module の呼び出しに渡した literal の key が削除される（case15） | object literal は free variable を持たないので flow 解析の種にならなかった | sink literal の key を直接予約 |
| entry が `export { x } from "./sub"` だけのとき bundle に export が 1 つも出ない（case01/17/18/25） | `emit_entry_exports` が entry 自身の `export` spec しか見ていなかった | re-export を linker 経由で解決して emit（`export *`・bare specifier passthrough 含む） |
| `export type { T }` が値 export として emit され bundle が load 不能（case18） | `TsExportSpec` に type-only の区別がない | runtime binding を持たない export 名を落とす |
| `foo<T>(x)` の callee が rename されず `ReferenceError`（case08） | `TypeArgs` wrapper が両 renamer の catch-all に落ちていた | `TypeArgs` arm を追加 |
| `namespace N { … }` の body が消え、`N.member` 参照だけが残る（case09/10） | statement parser が namespace body を skip する | runtime member を持つ非 ambient namespace を **hard error** に（下記） |

`expectMangle` に挙がっていて実際には保持された名前は「missed
opportunity」として報告され、fail にはなりません。保守的に倒すのは常に
健全なので、圧縮率の話であって安全性の話ではありません。現在の
missed opportunity は `local` / `subLocal` / `prop1` / `prop2` / `vvv` /
`foo` — いずれも「値の出自を解決できず object 全体を escape 扱いにした」
ケースです。

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

## 残っているギャップ

corpus の 7 件はこれらで blocked です。それぞれ最小再現を添えます。

### 1. runtime member を持つ namespace の lowering がない（case09, case10）

```ts
export namespace MyNamespace {
  export function foo() {}
}
MyNamespace.foo();
```

statement parser は namespace body を skip するので、以前は
`MyNamespace.foo()` だけが残り `MyNamespace` を宣言する code が無い JS が
無診断で出ていました。現在は mtsc が compile を拒否します:

```
mtsc: unsupported in index.ts: `namespace MyNamespace` declares runtime
members, which mtsc cannot lower yet …
```

ambient（`declare namespace` / `declare global` / `declare module "x"`）は
正当に erase されるので通ります。`TsNamespaceDecl.is_declare` がこの区別を
持ちます。本来の修正は
`var N; (function (N) { … })(N || (N = {}))` への lowering です。

### 2. cross-module の型解決が CLI checker に無い（case19, case20）

```ts
// types.ts
export type Loc = { fileName: string };
// index.ts
import type { Loc } from "./types";
export function extend(names: string[]): Loc[] {
  return names.map((fileName) => ({ fileName }));  // ← 誤検出
}
```

`mtsc` は file ごとに checker を走らせるので、import された `Loc` は
解決できません。解決できない `Named` が array element 位置にあると、
top-level にある場合の「解決不能なら判定しない」規則が効かず、同一の
shape が mismatch として報告されます。`@mtsc.check_module_graph` は
module graph 全体を解決できるので、CLI の `--bundle` path をそちらに
繋ぐのが本筋です。

### 3. mapped type への indexed access（case11）

```ts
type Animal = "dog" | "cat";
type Info = { [K in Animal]: { name: K } };
let x: Info["dog"] = { name: "dog" };  // property `name` does not exist on `Info["dog" (string)]`
```

### 4. constructor の default parameter が arity に反映されない（case02）

```ts
class Calculator {
  constructor(private value: number = 0) {}
}
new Calculator();  // expected 1 argument(s), got 0
```

### 5. sibling `.d.ts` の ambient 宣言を読まない（case03）

```ts
// env.d.ts
declare const MyGlobal: { foo: string };
// index.ts
export const foo = () => MyGlobal.foo;  // cannot find name `MyGlobal`
```

`mtsc` は entry から relative import を辿るだけで、同じ directory の
ambient declaration file を program に含めません。

### 6. namespace 内の `const v = 1` が `int` に落ちる

case09 の縮小中に見つかった別件です。

```ts
export namespace N {
  export const v = 1;
  export function foo(): number { return v; }  // expected `number` but got `int`
}
```

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

```bash
just verify-checker-soundness
```
