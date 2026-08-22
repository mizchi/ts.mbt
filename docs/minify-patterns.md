# 安全な minify / mangle パターンのカタログ

`mtsc` の変換 pass を「何を証明すれば安全か」で並べた表です。
[`docs/mangle-safety.md`](./mangle-safety.md) が property 名の rename に
限った証明モデルを扱うのに対し、こちらは pass 全体を横断して
「追加できるパターン」と「その証明義務」を列挙します。

## 安全性の定義

変換 `T` が安全とは、任意の入力 program `P` について `P` と `T(P)` が
**観測的に等価**であること。観測とは:

1. **export surface** — entry が export した値から到達できる名前と値。
2. **side-effect sink** — `fetch` / `console.*` / `JSON.stringify` /
   host API / 解析できない callee への値の受け渡し。
3. **副作用の発生そのもの** — 書き込み、I/O、例外、unhandled rejection。
   発生の有無だけでなく順序も含みます。

1 と 2 は「名前が漏れるか」、3 は「作用が消えるか」を見ています。
mangle 系の pass は 1・2 を、DCE 系の pass は 3 を証明義務に持ちます。

## 列挙の向きが精度ではなく安全性を決める

sink 解析でこれを一度間違えました
([`mangle-safety.md`](./mangle-safety.md#sink-の列挙ではなく-callee-の-provenance-で決める))。
教訓は pass の種類を問わず同じです。

- **危険なものを列挙する** → 列挙漏れが silent miscompile。host API は
  増え続けるので列挙は完成しない。
- **安全なものを列挙する（allowlist）** → 列挙漏れは「最適化されない」
  だけ。失敗が閉じている。

新しいパターンを足すときは、判定を必ず後者の向きに書きます。
`pure_builtins.mbt`（名前が漏れるか）と `purity.mbt` の
`is_effect_free_static_call`（作用があるか）は、別の問いに答える別の
allowlist です。同じ名前が両方に載る／片方だけに載るのが正常で、
`console.log` は前者に載り後者には絶対に載りません。

## パターン表

| パターン | 証明義務 | 状態 |
| --- | --- | --- |
| identifier mangling | scope 内で一意な rename。top-level は bundle 内部なので自由 | 実装済 (`mangle.mbt`) |
| property mangling | 名前が door 1・2 のどちらからも到達しない | 実装済 (`mangle_safety.mbt` + `export_surface.mbt` + `callee_provenance.mbt`) |
| dead property elimination | 上に加えて、値式が純粋 | 実装済 (`dead_props.mbt`) |
| class method DCE | method 名が bundle 内で read されず、export surface からも到達しない | 実装済 (`class_method_dce.mbt`) |
| tree-shaking | 宣言が live root から到達不能、かつ initializer が純粋 | 実装済 (`treeshake.mbt`) |
| **inferred-purity DCE** | **callee が「自分の scope 外に書かない・impure を呼ばない」を推移的に満たす** | **実装済（下記）** |
| `as const` / const enum inline | binding が never mutated かつ never escape、access が静的 | 実装済 (`as_const_inline.mbt`, `const_enum_inline.mbt`) |
| 型駆動 fold | `x` の静的型が単一 primitive で、narrowing に依存しない | 実装済 (`type_fold.mbt`) |
| type predicate inline | `x is T` 注釈があり body が単一 `return expr` | 実装済 (`predicate_inline.mbt`) |
| 未使用 parameter 削除 | 関数が export surface に無く foreign call に渡らず、`arguments` を読まず、全 call site が既知で、落とす引数式が純粋 | 未実装（証明義務は既存の道具で書ける） |
| discriminant literal → int | その property の**値**が door 1・2 に到達せず、比較相手が常に同じ閉集合の literal | 未実装（per-(binding, property) の値観測が必要） |
| method devirtualization | class が bundle 内部・未継承、method が値として取られない、receiver が escape しない | 未実装 |
| shape-colored property slots | 同一 slot を共有する 2 名が同じ shape に同時に載らない（式単位の型伝播が必要） | opt-in / 未証明 (`--mangle-properties-shape-color`) |
| dead class field elimination | field 名が read されず export surface 外、initializer が純粋 | 未実装（`dead_props` は ObjectLit のみ） |

## 実装: inferred-purity DCE

`purity.mbt` は以前から「bundle 内部の top-level 関数のうち、自分の
scope 外に書かず、impure を呼ばないもの」を推移的に計算していました
（`PurityReport.pure_functions`）。ところが結果を使っていたのは
impure getter の warning だけで、`pure_functions` は誰も読んでいません。

一方 treeshake の純粋判定は完全に構文的で、`/* @__PURE__ */`
（`PureCall`）だけを信じます。つまり:

```ts
function scale(n: number): number { return n * 2 + Math.max(n, 1); }
const droppable = scale(21);      // 結果は誰も読まない
export const total = scale(4);
```

`scale` が純粋であることは既に**証明済み**なのに、`droppable` は
「call は side-effect root」という構文規則で残っていました。注釈を
書けば消える、というのは証明器を持っている処理系としては倒錯しています。

そこで `pure_functions` を `treeshake_block(block, pure_calls~)` に
繋ぎ、`is_pure_init` に 3 つの arm を足しました。

- `Call(f, args)` / `CallExpr(Var(f), args)` — `f ∈ pure_calls` かつ
  全 argument が純粋。callee が無害でも `f(sideEffect())` は残す必要が
  あるので、引数の純粋性は別途要求します。
- `MethodCall(Var(ns), m, args)` — `is_effect_free_static_call(ns, m, argc)`
  かつ全 argument が純粋。

purity は link 後の merged block で再実行します。link は module ごとに
local を rename する（`helper` と `helper$0`）ので、pre-link の名前で
引いた集合は merged block に対して意味を持ちません。診断用の早い実行は
`--mangle` / `--minify` の有無に関わらず動く必要があるため残し、
削除に使う 2 回目だけを treeshake の直前に置いています。`@__PURE__`
注釈も `link_renames.locals` を通して post-link 名に写しています。

### 前提として直したこと: purity table の粒度

`pure_functions` を削除に使う前に、purity の built-in 判定を直す必要が
ありました。旧実装は **namespace 単位**でした。

```moonbit
let pure_global_methods = ["Math", "JSON", "Object", ..., "Reflect", "Proxy"]
```

`Object` が丸ごと純粋なので、`Object.assign` も `Object.freeze` も
`Object.defineProperty` も純粋です。warning を出すだけなら精度の問題
ですが、削除に使うと miscompile になります。

```ts
const registry: { hits?: number } = {};
function record(n: number): number {
  Object.assign(registry, { hits: n });   // registry に書く
  return n;
}
const unused = record(7);
export const out = registry.hits === undefined ? 0 : registry.hits;
```

namespace 単位の table では `record` が純粋と判定され、`record(7)` が
消え、`out` が **7 ではなく 0** になります（実測）。member 単位の
`is_effect_free_static_call` に置き換えて、writer を全部落としました:

- `Object` — `assign` / `defineProperty` / `defineProperties` / `freeze`
  / `seal` / `preventExtensions` / `setPrototypeOf` を除外。
- `Reflect` — reader（`get` / `has` / `ownKeys` / …）だけ。`apply` /
  `construct` は任意の code を走らせるので除外。
- `Proxy` — trap が任意の code を走らせるので namespace ごと除外。
- `Map` / `Set` / `WeakMap` / `WeakSet` — static は `groupBy` しかなく
  callback を呼ぶので namespace ごと除外。
- `Array.from` / typed array の `from` — **引数の数で分ける**。
  `Array.from(xs)` は allocate するだけ、`Array.from(xs, fn)` は `fn`
  を呼ぶ。
- `Promise` — `resolve` のみ。未使用の `Promise.reject(x)` は unhandled
  rejection という観測を作るので、消すと観測が減ります。`all` / `race`
  / `any` は「どの promise が unhandled として報告されるか」を変えます。
- `Symbol.for` はグローバル registry に登録するので除外、`keyFor` は可。

`Date.now()` / `Math.random()` は冪等ではありませんが何も変えないので、
未使用の呼び出しを消しても観測されません。載せてあります。

### 検証

corpus に 2 件足しました（`just verify-mangle-safety`）。

| case | 役割 |
| --- | --- |
| `case31-pure-call-dce` | 証明済みの call が消え、同じ file の impure な隣人（`console.log` に届く）が残ること |
| `case32-effect-controls` | `Object.assign` と `Array.from(xs, fn)` が消えないこと |

`case32` は歯があります。table を namespace 単位に戻すと差分検出が
こう出ます:

```
✗ observable behaviour changed
  baseline: {"result":{"out":11},"sinks":[{"sink":"console.log","args":[{"hits":7}]}]}
  mangled:  {"result":{"out":4},"sinks":[{"sink":"console.log","args":[{}]}]}
```

`--treeshake` は case の `mtscArgs` で mangled 側だけに渡しています。
baseline は素の `--bundle` なので、消してはいけない call を消せば
必ず 2 つの観測がずれます。

## 未実装パターンの証明義務

「安全に拡張できる範囲」を具体的に残しておくための節です。実装より
証明義務の記述が本体です。

### 未使用 parameter 削除

`function f(a, b) { return a; }` の `b` と、全 call site の 2 番目の
引数を落とす。必要な証明:

1. `f` が export surface に到達しない（`export_surface.mbt`）。
2. `f` が foreign call に値として渡らない（`callee_provenance.mbt` の
   `call_site_is_foreign` + 引数が function 式かどうか）。渡ると
   host が任意の arity で呼びます。
3. body が `arguments` を読まない。
4. `f` への参照がすべて call site（値として取られない）。
5. 落とす引数式が純粋（そうでなければ sequence として残す）。
6. 末尾から連続して落とす（間を飛ばすと位置がずれる）。

1 と 2 は既にある道具でそのまま書けます。`Function.length` の観測は
現実には誰も依存していませんが、厳密には 3 に足すべき条件です。

### discriminant literal → int

`type Shape = { kind: "circle"; r: number } | { kind: "square"; s: number }`
の `"circle"` / `"square"` を `0` / `1` にする。必要な証明は
「その property の**値**が door 1・2 に到達しない」で、今の
observability lattice は **binding** 単位なので足りません
（`obj` が観測されるかは分かるが、`obj.kind` の値だけが観測されるかは
分からない）。per-(binding, property) に lattice を細分するのが前提
条件です。`fetch(url + obj.kind)` のように名前は漏れないが値だけ漏れる
形があるので、property mangling の可否とは独立に判定が必要です。

### method devirtualization

`obj.m(x)` → `m(obj, x)`。property access が identifier access になる
ので、mangle 後に 1 文字になります。必要な証明: class が bundle 内部で
継承されていない、`m` が値として取り出されない、receiver が escape
しない、`this` が body 内で他の意味に使われていない。`class_method_dce`
が持っている「名前で access されているか」の索引が土台になります。

### shape-colored property slots

`--mangle-properties-shape-color` は既にありますが、
「同一 slot を共有する 2 名が同じ shape に同時に載らない」を証明できて
おらず opt-in のままです。証明には式単位の型伝播（今は binding 単位）が
必要で、そこは checker 側の仕事になります。

## 落とし穴として記録しておくもの

- **`dead_props` / `class_method_dce` は独自の純粋判定を持っています。**
  今回 treeshake に繋いだ証明はまだそこには渡していません。渡すと
  「値式が純粋な dead property」の範囲が広がりますが、pass ごとに
  証明義務が違う（drop する対象が宣言ではなく property）ので分けて
  検証が必要です。
- **purity は top-level 関数宣言しか見ません。** class method、object
  literal の method、nested function は対象外です。安全側（未証明＝
  impure）に倒れます。
- **`JSON.stringify` を effect-free 扱いにしています。** `toJSON` と
  getter に到達するので厳密には getter の純粋性に依存します。purity
  pass は impure getter を warning として別途報告しており、実運用の
  minifier はどれも同じ判断をしています。
