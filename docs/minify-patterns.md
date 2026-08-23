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
| **未使用 parameter 削除** | **関数が export surface に無く、参照が全部 callee 位置、`arguments` を読まず、param が全部素の識別子、落とす引数式が純粋、末尾の連続分だけ** | **実装済（下記）** |
| **discriminant literal → int** | **名前が escape 集合に無く、直接 read が全部 equality / `switch` 判別子、書き込みが全部同じ閉集合の string literal** | **実装済（下記）** |
| method devirtualization | class が bundle 内部・未継承、method が値として取られない、receiver が escape しない | **やらない**（下記の採算計算） |
| shape-colored property slots | 同一 slot を共有する 2 名が同じ shape に同時に載らない（式単位の型伝播が必要） | opt-in / 未証明 (`--mangle-properties-shape-color`) |
| **型注釈による wildcard の狭め** | **注釈が閉じた key 集合を持つ（named 型は宣言が見えていて、index signature も不可視 base も無い）** | **実装済**（[`mangle-safety.md`](./mangle-safety.md#型注釈が-wildcard-を狭めるそして注釈が名前でも効く)） |
| **dead class field elimination** | **field 名がどこからも read されず、escape 解析が予約せず、書く値が純粋** | **実装済（下記）** |
| spread 結果への private name 参照を error にする | 型に「この object は spread 由来」という情報が必要 | 未実装（下記の TP 1 件と引き換え） |

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

## 実装: 未使用 parameter 削除

```ts
function fmt(value, unusedOpts) { return String(value); }
fmt(a, {}); fmt(b, {}); fmt(c, {});
```
→
```ts
function fmt(value) { return String(value); }
fmt(a); fmt(b); fmt(c);
```

terser はこれをやりません。関数をまたぐ書き換えで、しかも JS では arity
が観測可能（`f.length`、`arguments`、host が自分の引数個数で callback を
呼ぶ）だからです。だからこそここに属します — 「bundle の外から `f` を
**値として**掴めるか」は `export_surface.mbt` と `callee_provenance.mbt`
がすでに答えていて、それが証明の全部です。

`src/transform/unused_params.mbt`。1 つの関数について全部成立して初めて
削ります。

1. top-level の binding で初期化子が関数、かつ再代入されない。
2. entry が export する名前ではない。export された関数の arity は ABI。
3. **`f` への参照が全部 callee 位置**。この 1 条件が大半を担います —
   foreign call に渡らない、escape する object に入らない、`f.call` /
   `f.apply` / `f.length` で触られない、constructor に使われない、が
   まとめて出ます。
4. body が `arguments` を読まない。
5. param が全部素の識別子（分割代入なし、rest なし、default なし）。
   落とす param に default があると、その評価が消えます。
6. 末尾の連続分だけ落とす（間を抜くと位置がずれる）。
7. 全 call site で、落とす引数が純粋。今は評価されているので、
   `sideEffect()` を消すと program が変わります。

証明できない部分があれば関数ごと触りません。

### 副産物: mangler の shadowing miscompile

corpus case を書いていて、**parameter 削除とは無関係の**既存バグが出ました。

```ts
function bump() { … }
function withDefault(a, unused = bump()) { return a; }
```

`--mangle-properties` の出力:

```js
function b() { … }              // bump → b
function c(b, c = b()) { … }    // param a → b が外の b を shadow
```

`c = b()` が関数ではなく parameter を呼び、`TypeError: b is not a
function`。**parameter default は関数自身の scope で評価される**ので、
default が外側から読む名前に parameter を rename すると隠れます。
`rename_param_list` は param を先に bind して default を後で rename して
いたため、衝突を予見できませんでした。

修正は「param を 1 つも bind する前に、default が参照する名前を外側 scope
で解決して予約集合に入れる」。class method の param default にも同じ経路が
あったので両方直しています。

## 実装: dead class field elimination

`this.x = …` は field を存在させる書き込みです。`x` をどこも読まず、
escape 解析も予約しないなら、その書き込みの唯一の効果は「誰も観測できない
field があること」です。

`dead_props` が持っていた壁は 1 行でした。

```moonbit
PropAssign(t, name, v) => {
  // `obj.x = …` writes to `x`, but it also makes `x` a
  // potentially-observable name; keep it reserved.
  out[name] = true      // ← 書き込みを read として数えていた
```

「書き込み = read」だと write-only field は永遠に落ちません。**書き込みは
read ではない**に直し、観測可能かどうかは escape 解析 (`reserved`) の答えに
委ねました。`reserved` は今や `this` 書き込み・`Object.keys`・`in` probe・
export surface を全部見ているので、この委譲が成立します。

落とすのは `PropAssign` と `Expr(PropAssignExpr(...))` の両方の綴り
（constructor の field 書き込みは両方混在します）。値が純粋でないときは
残します — `this.slot = register()` は `slot` が死んでいても走る必要が
あります。

### 前提として直したこと 2 件

1. **method call が receiver 全体を escape させていた。** `c.add(1)` が
   渡すのは `add` の**戻り値**で `c` ではありません。receiver 丸ごとを
   escape させると、method を呼ばれた class の field は全部予約され、
   この pattern は永久に不発です。known class の method を解決して戻り値
   だけを escape させ、`this` に触る戻り値（`return this.rows`、fluent な
   `return this`）は従来どおり receiver ごと escape に倒します。
2. **`this` 書き込みの索引が bundle 全体だった。** `prop_assigns` は
   receiver 名で引くので `this` は全 class の union です。1 つ escape する
   class があると他の全 class の field が予約されます。class ごとの scan に
   変えました（`index_prop_assigns` を scratch walk に対して再利用）。
   native class の constructor は `NativeClassStmt(decl, ctor)` の第 2 要素に
   いるので、そこも索引しています。

## 実装: discriminant literal → int

```ts
type Shape = { kind: "circle"; r: number } | { kind: "square"; s: number };
switch (x.kind) { case "circle": …; case "square": … }
```
→ `case 0:` / `case 1:`、`{ kind: 0, r: 2 }`。

`"circle"` は出現ごとに 8 byte、`0` は 1 byte。**property mangling は
key を rename するだけで value には触らない**ので、bundle の外から誰も
見ないタグ文字列がそのまま残っていました。

証明の対象は property の**名前ではなく値**で、これは observability
lattice が答える問い（binding 単位）とは別物です。lattice を細分する
代わりに、2 条件の組で決めました。

1. **名前が escape 集合に無い。** object 丸ごとが出ていく経路
   （serialize / enumerate / `in` probe / foreign call / export surface）は
   すべて名前を予約するので、これで覆えます。
2. **直接 read が全部 equality 比較か `switch` 判別子**で、相手が同じ
   閉集合の literal。1 が拾えない残りの経路 —— 名前は隠れたまま**値だけ**が
   出ていく `return shape.kind` —— をこれで塞ぎます。

加えて 3. 書き込みが全部素の string literal（でないと集合が閉じない）。

それ以外の位置での read は名前ごと失格にします。template literal、引数、
そして **truthiness 判定**（`if (shape.kind)` は `"circle"` が truthy で
`0` は falsy）。`==` も `===` と同じ扱いで安全です —— 両辺が同時に数値に
なり、比較相手は「実際に書かれている literal」に限っているので、結果は
どの組み合わせでも変わりません。

解析の walk は**親を見る**形にしてあります。普通に到達した
`PropAccess(_, k)` は bare read として `k` を失格させ、承認される 2 つの形
（equality 比較と `switch` 判別子）だけが上から access を認識して
**receiver 側に降りる**ので、その access は bare として数えられません。

## やらないもの: method devirtualization

`obj.m(x)` → `m(obj, x)`。証明義務は書けます（class が bundle 内部・
未継承、method が値として取られない、receiver が escape しない）。
やらない理由は採算です。

property mangling が走った後、`obj.m(x)` はすでに `a.b(c)` です。
devirtualize すると `d(a,c)` —— **同じ 6 文字**。method 定義側は
`b(x){…}` から `function d(e,x){…}` になり、`function` キーワードと
カンマの分だけ**増えます**。

Closure で意味があるのは、devirtualize した後に inliner が本体を展開
できるからです。mtsc の inline pass は「1 回しか使われない const」
(`inline.mbt`) と「単一 `return expr` の type predicate」
(`predicate_inline.mbt`) だけで、複文の関数本体を展開する inliner は
持っていません。前提が無いので、この pass の期待値は 0 か負です。

汎用 inliner が入ったら再評価する価値があります。それまでは実装しない
方が正しい。

## 最適化されなかった理由を出す (`--explain-mangle`)

安全側に倒れる解析の既定の結果は「最適化されなかった」です。これは
正しい挙動ですが、利用者から見ると失敗と区別できません。判定は
yes/no で足りても、**人間が必要とするのは「どの規則が、どの式で
発火して、何を変えれば通るか」**です。

`--explain-mangle`（`mangle_explain.mbt`）はそれを出します。設計上の
要点は 1 つだけで、**説明を別実装にしない**ことです。

- `escape_breakdown` が予約集合を「理由ごとの部分集合」として計算する。
- `collect_externally_visible_props` はその merge だけを行う。

判定と説明が同じ 1 回の解析から出るので、説明だけが古くなる余地が
ありません。逆向き（説明用に再解析する）にすると、その 2 つが食い違った
ときに嘘の説明を出すほうが、説明が無いより悪くなります。

出力は pass の依存順 —— escape → parameter → field → tag —— に並びます。
wildcard が出た時点で後続 3 pass は連鎖して止まるので、その連鎖も明示
します。

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

dead class fields: why a write survived

  the wildcard above forced every property name in the bundle
  into the reserved set, so nothing here can proceed.
```

wildcard の帰属は 2 経路あります。

1. `External` として観測される binding のうち、閉じた key 集合を持つ
   型注釈が無いもの → その **binding 名**を出す。
2. external chain 上の `obj[k]` で `k` を特定できないもの → その
   **chain の root 名**を出す。

「どこかで何かが起きた」ではなく名前を出すのが要件です。1 つの binding が
bundle 全体の property mangling を落とすので、名前が分からないと直せません。

残り 3 pass（parameter 削除、dead field、discriminant tag）は
`plan_*` / `explain_*` に `declines` の out-param を足して、
発火しなかった条件をそのまま文にしています。条件ごとに文が違うので、
「7 条件のうちどれで落ちたか」が出力から一意に決まります。

検証は `mangle_explain_wbtest.mbt` です。最初の test が
「`escape_breakdown` の部分集合を merge した結果 == `collect_externally_visible_props`
の結果」を 8 種類の source で確認します。説明の内容ではなく、
**説明が説明している対象と一致していること**が壊れやすい側なので、
そこを最初に押さえます。

## テストパターンを払い出す

pass ごとに case を手書きしていると、corpus は「誰かが思いついた状況」の
集合になります。これは解析側で一度やらかしたのと同じ失敗の形で、
思いつかなかった状況の場所にちょうど穴が空きます。

そこで **モデルから払い出す**方向に変えました
（`scripts/generate_mangle_cases.mjs`、`just gen-mangle-cases`）。
軸は 2 つです。

- **carrier** — property を持つ値の作り方。top-level object literal /
  内部関数の戻り値 / class instance / array の要素 / spread で組んだ
  literal / conditional の分岐 / `Map` に入れて出した値。
- **exit** — 値の出口と、sink の観測の深さ。出口なし / `console.log` /
  `JSON.stringify` / `fetch` body / external package の関数 / nested な
  host chain / `Object.keys` / `for-in` / `Object.entries` /
  export された関数の戻り値 / `throw` / `structuredClone`。

期待値は**書かず、導出**します。

| 観測の深さ | 予約されるべき名前 |
| --- | --- |
| `none` | なし |
| `direct` (`Object.keys` / `for-in`) | 第 1 階層の key だけ |
| `recursive` (`JSON.stringify` / `console.log` / request body) | 木全体 |
| `external` (foreign callee) | 木全体 |

carrier 側は「観測される値から名前までの階層のずれ」を宣言します
（array 要素は 1 段深いので、`Object.keys(array)` は `"0"` を列挙する
だけで要素の key は露出しません）。この 2 つを掛けるだけで
`expectKeep` / `expectMangle` が決まります。8 carrier × 14 exit = 112 件。

### 初回実行で出た 4 件

全部本物の安全性違反でした。差分実行が独立に裏付けています。

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `console.log(payload)` で nested key (`{ wrap: { deep } }` の `deep`) が **削除**される | `reserved_props_from_observability` が `RecursiveProps` と `DirectProps` を同じ `collect_direct_props` で処理していた。lattice は区別しているのに予約側が使っていない | Phase 4d を追加 |
| 内部関数の戻り値を sink に渡すと key が**何も**予約されない（`const payload = build(); console.log(payload)` → `console.log({})`） | `collect_direct_props` は binding 自身の ObjectLit init しか読まない | 同上 |
| array の要素の key が予約されない（`[{ … }]` → `[{}]`） | 同上 | 同上 |
| class instance の field が rename される（`{"a":1,"b":{}}`） | `surface_escape_class` が `this.x = …` の**書き込み**を見ていなかった。`useDefineForClassFields: false` では初期化子の無い field 宣言は完全に消えるので、runtime shape を作るのは constructor の代入だけ | `prop_assigns["this"]` を参照 |

最初の 3 件は「値の木を root から歩く」という同じ walk を欲しがっていて、
それは door 1 が export された binding からやっていることそのままです。
root だけ差し替えて再利用しました（Phase 4d）。

`DirectProps` の 1 階層精度は残す価値があるので
（`Object.keys` された object の nested key は本当に mangle 可能）、
「literal が見えているときだけ 1 階層規則、見えないときは木全体に倒す」
という形にしています。

4 件目は **door 1 のバグでもあります**。field を constructor でしか
代入しない exported class は、field 名が rename され得る状態でした。
なお `this` 書き込みの収集では `decl.private_members` で絞っていません
— TypeScript の `private` は compile 時の約束で runtime には残るので、
`JSON.stringify` すれば普通に見えます。真の `#x` は parser が
`__private_brand__…` に脱糖するので marker 判定側で落ちます。

### 軸を足した 2 巡目

carrier に spread / conditional / `Map` 経由、exit に export された関数の
戻り値 / `throw` / `structuredClone` / `Object.entries` を足して
7 × 12 = 84 件にしたところ、さらに 3 件出ました。

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `Map` に入れて出した値の key が予約されない（全 exit で fail） | 値の木の walk は receiver の initializer（`new Map()`）しか見ない。`store.set("k", v)` で入れた `v` と `store.get("k")` の結果が繋がっていない | receiver 名ごとに `set` / `add` / `push` などの引数を index（`container_writes`） |
| `Object.entries(x)` / `Object.values(x)` で nested key が漏れる | `keys` と同じ `DirectKeys` sink として model していた。`entries` / `values` は **値**も渡すので、その中の名前も一緒に出ていく | `values` / `entries` を `Recursive` に |
| spread した key が `for-in` / `Object.keys` から漏れる（`{...base, wrap}` の `base` 由来の key が削除） | 1 階層規則が literal の entry key を読むが、spread entry の key は property 名ではない sentinel。読める分だけ読んで残りを落としていた | sentinel を含む literal では 1 階層規則を使わず木全体に倒す |

3 件目を直したら、**それまで通っていた 4 件が赤くなりました**。sentinel key
（`"..."` と `@@spread:N` と `@@computed:N` の 3 通りがある）が
「予約済みの property 名」として扱われていたのに依存していたためです。
偶然の予約に頼っていただけで、正しい修正は sentinel を property 名として
扱わないことでした。3 箇所直しています。

- `dead_props.mbt` — `"..."` だけを除外していたので、`@@spread:N` entry が
  dead key として**削除**される
- `mangle.mbt` の property renamer — 同じく `@@spread:N` を rename して
  しまう。`...base` が `a: base` になり、merge ではなく入れ子になる別の
  object が出る（意味が変わる miscompile）
- `mangle.mbt` の property 収集 — sentinel を property 名として数える

### 3 巡目: 生成器が checker の false positive を掘り出した

`spread` carrier を書いたときに、生成 case ではなく手元の repro で
checker の FP が出ました。

```ts
const base = { a: 1 };
function build(): number {
  const merged = { ...base, b: 2 };
  return merged.a + merged.b;   // ← property `a` does not exist on `{ b: number }`
}
```

`base` に注釈が無いので function body の中では `Any` に推論され、
`collect_declared_fields` が何も返さず、`{ ...base, b: 2 }` が
**見えた key だけで閉じて**いました。正しい TypeScript に対する誤検出です。

向きの問題としては sink 解析と同じで、**分からないときは閉じてはいけない**。
spread operand の shape を列挙できないときは結果の object 型を開いたまま
にします（`[k: string]: any` entry を足す）。列挙できるときは従来どおり
閉じるので、`{ ...knownBase, b: 2 }` に対する `.nope` は今も error です。

conformance の計測は **FP 0 / PFLEGAL 0 / TN 1750 のまま、TP が 2,339 →
2,338**。減った 1 件は `privateNameAndObjectRestSpread` で、TS が error に
する理由は「spread は private field (`#x`) を copy しないので
`{ ...other }.#prop` は参照できない」という**専用の規則**です。ts.mbt は
その規則を model しておらず、閉じた object の missing-property 判定に
たまたま引っかかっていただけでした。model していた検出ではなく偶然の
検出を 1 件失った、という取引です。

原理的に取り戻すなら「spread 結果に対する private name 参照は常に
error」という規則を足すことになります（型に「spread 由来」の情報を
持たせる必要があるので、未実装の欄に置いています）。

### 4 巡目: getter / `in` / `Object.assign` の target

carrier に「getter だけの object literal」、exit に `in` 演算子と
`Object.assign` の target 側を足して 8 × 14 = 112 件。

exit の観測を深さの梯子だけで表せない形が出たので、exit が「露出する名前を
名指しする」上書き (`exposes`) を入れました。`"k" in obj` は **その 1 名
だけ**を露出し、木でも第 1 階層でもありません。

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `Object.assign({}, payload)` の結果を export すると nested key が削除される | `assign` の source を `DirectKeys` として model していた。assign は浅いコピーなので値は同一参照で、nested な名前は target と一緒に出ていく | source を `Recursive` に |

`in` 演算子の case は**全部通りました**。理由は追ってあります —
literal key を rename できる object は、`in` 式の被演算子として
export surface / observability の walk からも必ず到達するので、key は
どちらにせよ予約されます。つまり穴ではなく偶然でした。ただし
「偶然そうなっている」と「証明されている」は別なので、
`"k" in obj` の `k` は明示的に予約し、`dead_props` の read 集合にも
数えるようにしました（`BinOp(In, StringLit(k), _)`）。

### 生成物の扱い

`fixtures/mangle-safety/generated/` は commit します（CI が走るため）。
`just verify-mangle-safety` が `--check` で再生成して差分を検出するので、
generator と fixture が乖離できません。

## 証明義務の記述

「安全に拡張できる範囲」を具体的に残しておくための節です。実装より
証明義務の記述が本体なので、実装済みになったものも記述を残しています
（下の 2 件は実装済み。3 件目以降が未実装）。

### 未使用 parameter 削除（実装済み）

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

### discriminant literal → int（実装済み）

`type Shape = { kind: "circle"; r: number } | { kind: "square"; s: number }`
の `"circle"` / `"square"` を `0` / `1` にする。必要な証明は
「その property の**値**が door 1・2 に到達しない」で、今の
observability lattice は **binding** 単位なので足りません
（`obj` が観測されるかは分かるが、`obj.kind` の値だけが観測されるかは
分からない）。per-(binding, property) に lattice を細分するのが本来の
前提条件で、`fetch(url + obj.kind)` のように名前は漏れないが値だけ漏れる
形があるためです。

実装 (`discriminant_ints.mbt`) は lattice を細分する代わりに、
**値の read 側を全部列挙できる形に限る**方向で証明義務を満たしています
——直接の read が equality 比較か `switch` 判別子だけ、という条件です。
それ以外の read（interpolation、他へ渡す、truthiness）が 1 つでもあれば
名前ごと降ります。lattice の細分は依然として「もっと広く効かせる」ための
残作業です。

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
- **`as_const_inline` は assignment の receiver を見落としていました。**
  `cfg.k = v` は statement (`PropAssign`) と expression
  (`PropAssignExpr`) の 2 通りで AST に来ます。前者だけが receiver を
  disqualify していたので、関数本体の中で書き換えられる object は
  「mutation されていない const」と判定され、全 read site が初期値に
  inline されていました（`--fold` 単体で再現、mangle と無関係）。
  同じ形の穴が `AssignExpr` の左辺にもありました。**同じ意味の構文が
  2 つある所は、片方だけ書いた時点で穴が空きます。** 型注釈の
  `Named` 解決を入れて corpus に case36 を足したときに出ました ——
  最適化を 1 つ通せるようにすると、その先で止まっていた別 pass の
  bug が初めて観測できるようになる、という順序です。
- **`JSON.stringify` を effect-free 扱いにしています。** `toJSON` と
  getter に到達するので厳密には getter の純粋性に依存します。purity
  pass は impure getter を warning として別途報告しており、実運用の
  minifier はどれも同じ判断をしています。
