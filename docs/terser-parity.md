# terser との比較: 移植済みの rule と、残っている rule

型を使った minify の主張は「terser より小さくできる」ではなく
「**terser には出せない結論を型から出せる**」です。ですが、型で勝って
byte で負けたら意味がありません。`const enum` を畳んで `return 3` に
できても、terser が `console.log(3)` と書くところで
`console.log(f())` と書いていたら、出力は terser の方が小さい。

なので rule ごとに測ります。

```sh
just compare-terser
just compare-terser --only inline --verbose
just compare-terser --update           # expected.json を再記録
```

## 測り方

terser は TypeScript を parse できません。`in.ts` を直接比べると
**parser の比較**になってしまうので、両者に同じ JavaScript を渡します。

```
in.ts ──[mtsc --bundle --no-check（最適化なし）]──> plain.mjs
                                                     │
                              ┌──────────────────────┴──────────────────────┐
                              │                                             │
                    terser (compress + mangle)                    mtsc (full pipeline)
                              │                                             │
                              └────────────── byte 数 / 挙動 ───────────────┘
```

terser 側は `passes: 3`、`toplevel: true`、`module: true`。`unsafe_*`
family は除外しています（意味を変える前提の option なので、それを
拒否している compiler との比較として不公平です）。両側とも Node で
実行して観測が一致することを確認してから byte を比べます。

case は 2 group あります。

- **`terser-rule`** — terser の compress option 1 つに対応する case。
  出典は terser 自身の default 一覧
  (`node_modules/terser/lib/compress/index.js`)。LOSS は
  **未移植の rule の名前**です。
- **`type-aware`** — 型情報がないと出せない結論。ここでの LOSS は
  もちろん、**TIE も失敗**です（型 pass が発火していない）。

## 現状

`31 win, 0 tie, 1 loss`。`type-aware` は 7 件すべて win。

残る 1 件は `computed_props` の +2 byte で、これは**移植しないと判断**
しました（理由は下記）。

### この作業で移植した rule

| rule | 何を見つけたか |
| --- | --- |
| `inline` | 最大の loss（2 行のプログラムで +27 byte）。かつ `type-aware` の 3 件が負け／引き分けだった原因。→ [`src/transform/call_inline.mbt`](../src/transform/call_inline.mbt) |
| `drop_debugger` | `debugger` を落としていなかった |
| `loops` | `while (true)` → `for (;;)` |
| `typeofs` | `typeof x === "undefined"` → `void 0 === x` |
| `computed_props` | `{ ["a"]: 1 }` → `{ a: 1 }` |
| （`evaluate` の穴） | `void 0 === void 0` を畳んでいなかった |

`inline` は「call を body で置き換える」ので、minifier が最も簡単に
意味を変えられる場所です。受け入れ条件は
[`call_inline.mbt`](../src/transform/call_inline.mbt) の冒頭に列挙して
ありますが、実装中に 2 回踏んだ落とし穴を書いておきます。どちらも
**mangle 後の code に対してしか出ません**。

1. **自分の parameter が自分の名前を隠す。** mangler は短い名前を
   使い回すので、`function helper(n) { return n + 1 }` は
   `function a(a) { return a + 1 }` になります。body の `a` は
   parameter ですが、再帰判定がこれを自己参照として読んで、
   **mangler が触った関数すべて**（つまり全部）を却下していました。
   rule は実 pipeline では何もしないまま、unmangled な入力に対する
   unit test は通り続けます。
2. **table は名前で引くのに、あらゆる scope に持ち込まれる。**
   同じ理由で、top-level の `function a(…)` と、別の関数の中の
   `let a = …` は mangle 後の code の**普通の姿**です。scope を見ずに
   名前で解決すると、内側の `a(1)` に外側の body が入ります。
   scope に入るたびに、その scope が束縛する名前を table から落とす
   ようにしてあります（`narrow_for_block` / `narrow_for_func` /
   `narrow_for_binding`）。parameter / 局所宣言 / loop 変数 / catch
   parameter の 4 通りそれぞれに regression test があり、narrowing を
   外すと 4 件とも落ちることを確認しています。

1 は「よく最適化された入力ほど壊れる」形なので、rule 自身の unit test
では絶対に出ません。

### 2 巡目に移植した 5 件

前の版ではここに 6 件の loss が並んでいました。rule 名は harness が
option 名で報告しますが、**5 件のうち 4 件は名前が指す rule と実際に
足りないものが違っていた**ので、まず output を並べて何が違うのかを
読むところから始めています。

| 差 | 報告された rule | 実際に足りなかったもの |
| --- | --- | --- |
| +11 → **-1** | `if_return` | 半分は本物（`if (c) return; g()` → `c \|\| g()`）。残り 3 byte は**こちらの regression**で、mangler が method shorthand を壊していた（下記） |
| +9 → **-1** | `reduce_vars` | top-level の scalar `const` を use 側に伝播する。新 phase `const-scalar-inline` |
| +9 → **-1** | `negate_iife` | negation ではなく、**IIFE の body を展開**する話だった。`(function(){ f(); })()` → `f();` |
| +5 → **-8** | `typeofs` | rule は移植済みだった。`fold` に畳む rule もあった。**phase 順序**の問題で、`void 0 === void 0` を作るのは peephole なのに、畳むのは その前に走る `fold-2` |
| +1 → **-1** | `loops` | `sequences` の一種。loop body の先頭の式文を最後の文に comma で畳み込むと 1 文になり、**波括弧が落ちる**。comma 自体は byte を節約しない（`a;b` と `a,b` は同じ長さ）——括弧の 2 byte が全部 |

#### method shorthand: 自分で作った 3 byte

`if_return` の case が 11 byte 負けていて、rule 自体は 8 byte 分です。
残り 3 byte は `{ p() {…} }` が `{ p:()=>{…} }` として出ていたためでした。

parser は method shorthand を `("p", FuncExpr { name: "p" })` として
持ち、emitter は `f.name == key` で shorthand を復元します。
mangler の `rename_function_expr` は、自分の名前を参照しない function
expression の名前を落とします——`module.exports = function isExtglob()`
には正しい処理ですが、ここでは**名前が binding ではなく key そのもの**
です。落とすと `p: function () {…}` に戻り、`this` を使わないものは
peephole が arrow にして `p:()=>{…}` になります。plain `--mangle` で、
method を持つ object literal すべてが対象でした。

最初の修正は名前を無条件に戻すもので、**別の case で 7 byte 損しました**
(`collapse_vars`)。body が `return expr` 1 文だけなら arrow の簡潔形の
方が短いからです:

```
p(a) { return a }      14 byte
p: a => a               6 byte
p() { f(); g() }        4 + body
p: () => { f(); g() }   7 + body
```

`is_method_shorthand_worth_keeping` が両方を比べます。1 文 return かつ
arrow 化が安全なときだけ名前を落とし、それ以外は shorthand を守ります。

#### `typeofs`: rule ではなく phase 順序

`fold_expr` の**先頭の arm** が `both_literal_undefined` を畳みます。
それでも `console.log(void 0===void 0)` が出ていました。

`typeof x === "undefined"` → `x === void 0` の書き換えは **peephole**
にあります。pipeline は `fold` → `inline` → `fold-2` → `peephole` で、
`f(undefined)` を inline した時点では body はまだ `typeof x === …` の形。
その形を `void 0 === void 0` に変えるのは peephole 自身で、その後には
何も走りません。rule は 2 箇所に必要でした。

「rule はあるのに発火しない」は、rule が無い場合と区別がつきません。
`--only <case> --verbose` で出力を見るまで、budget の話だと思って
定数をいじっていました。

### 最後の loss: 1 文字 export だけ移植した

最後まで残っていた +2 byte は `computed_props` とラベルされていましたが、
**その rule は移植済みで発火しています**（`{ ["key"]: 1 }` は
`{ key: 1 }` になる）。harness は case を名指すだけで、原因は名指し
ません。実際の差はこれです:

```
mtsc:   let a={key:1};console.log(o.key);export{a as o}   47
terser: const o={key:1};console.log(o.key);export{o};     45
```

mangler が export された `o` を**同じ長さの** `a` に rename し、
何も節約せずに alias 分を払っていた。損得は:

```
alias 形  : refs×len(local) + len(local) + 4 + len(export)
直接形    : refs×len(export) + len(export)
```

`len(local)=1` として、直接形が勝つのは `refs×(len(export)-1) < 4`。
export 名が 1 文字なら**常に**勝ち、2 文字なら refs ≤ 3 まで、
3 文字以上なら alias が勝ちます。

**1 文字の場合だけ移植しました。** rename が節約できる byte は
ちょうど 0 なので、参照回数も mangler が選ぶ名前も関係なく、
どんな bundle でも必ず損です。cost model を要らない唯一の部分集合です。
測定: zod **-78 byte**、この case は 47 → 42（最後の loss が win に）、
他の 9 target と real-world 5 target は byte 単位で不変。

**一般形は実装して測って、落としました。** `(len - 1) × sites < 5`
——`len(new)=1` を両辺に取った楽観的な上界、`sites` は参照数 + 宣言
——で測ると valibot -54 / immer -40 / zod -63 / excalidraw -231 /
superstruct -36 / ts-pattern -3 に対して remeda **+291** / typebox
**+267** / neverthrow +37 で、10 target 合計で **約 +168 byte の損**
でした。break-even (`<=`) はさらに悪く、hono を 8 byte 増やします
（strict `<` なら不変）。上の算術が model していない何かが、退行した
target では支配的です——予約した名前は**生成 pool からも外れる**ので、
最も使われる identifier が 1 文字を取れなくなる——そして「測って悪く
なった byte 最適化」は最適化ではありません。次に触る人が式からでは
なく数字から始められるように、ここに置いておきます。

`sequences` は loop body 以外——`if` の body、`else` の body、関数末尾——
にも効きますが、`if` の body では **dangling else** を作れます
(`if (c) { x; if (d) y; } else z` の波括弧は制御構造です)。今は loop
body だけに限定しています。

## 型を見ずに型を仮定していた 3 件

この作業の副産物として、既存の rule に「型が分かっている前提で書かれて
いるが、何も確認していない」ものが 3 件見つかりました。どれも実コード
（TypeScript compiler 本体）で実際に壊れています。詳細は
[`docs/real-world-minify.md`](./real-world-minify.md) にありますが、
分類だけ書いておくと:

| 書き換え | 前提 | 反例 |
| --- | --- | --- |
| `x === true` → `x`、`x === false` → `!x`、`x !== true` → `!x`、`x !== false` → `x` | `x` が boolean | `x = 1` で `x === true` は false、`x` は truthy |
| `!(a < b)` → `a >= b`（と 3 兄弟） | 比較が NaN を経由しない | `a = undefined` で `!(a<b)` は true、`a>=b` は false |
| single-use inliner が副作用のある initializer を移動 | use 位置が無条件 | `?` の取られない branch に移動して呼び出しが消える |

これらは byte を数えるだけの harness では見つかりません。**出力を実行
して観測を比べる**harness と、**実際に大きい実コード**の両方が必要
でした。前者だけなら corpus と fuzzer が通ってしまい、後者だけなら
「動いた」で終わります。

## 未移植のままにしている判断

`unsafe_*` family は移植しません。`unsafe_math`、`unsafe_proto`、
`unsafe_comps` などは「実際にはこう書かないだろう」を前提に意味を
変える option で、terser 自身の documentation もそう書いています。
型から結論を出すこの project にとっては、前提を置かずに証明できる
範囲だけが取り分です。

`keep_fargs: false` 相当（使われていない末尾 parameter の削除）は
移植済みですが、`Function.prototype.length` を読むコードがあると
壊れます。ここは
[`docs/mangle-safety.md`](./mangle-safety.md) の reflection gate と同じ
判断で、property enumeration が届く先だけを保護しています。

## 実バンドルでの head-to-head（`just compare-terser-bundles`）

このドキュメントの 32 win / 0 loss は**手書き case 34 件**の結果です。
「自分たちが思いついた rule では負けていない」という確認で、そして
それが 32-0 だった時点で **mtsc は実ライブラリで terser に 51% 負けて
いました**。どちらも真です——corpus は誰かが case を書いた rule だけを
覆い、残りについて何も言いません。

なので同じ入力で正面から測る harness を足しました。両者の入力は各
type-aware target の `mtsc --bundle` 出力（最適化なしの素の JS）です。

| target | terser | mtsc | 差 | gz terser | gz mtsc | 差 |
| --- | --- | --- | --- | --- | --- | --- |
| hono | 19,685 | 21,139 | +1,454 (+7.4%) | 7,576 | 7,952 | +376 (+5.0%) |
| valibot | 88,223 | 86,979 | −1,244 | 14,697 | 15,042 | **+345** |
| typebox | 79,127 | 90,028 | +10,901 (+13.8%) | 19,235 | 22,567 | +3,332 |
| immer | 20,287 | 20,383 | +96 | 7,297 | 7,520 | +223 |
| neverthrow | 5,262 | 5,166 | −96 | 1,382 | 1,362 | −20 |
| ts-pattern | 8,079 | 8,567 | +488 | 2,591 | 2,789 | +198 |
| superstruct | 20,785 | 10,433 | −67 | 3,417 | 3,451 | +34 |
| remeda | 28,909 | 28,521 | −388 | 9,156 | 9,308 | **+152** |
| excalidraw | 281,053 | 279,230 | −1,823 | 91,206 | 93,110 | **+1,904** |

raw byte では 5/9 で勝ち。**gzip 後は 1/9 しか勝っていません。**

remeda は raw −388 / gzip **+152**。つまり我々が削っているのは gzip が
どうせ縮める場所で、terser の変換のほうが gzip に効く形を出しています。
**誰も非 gzip の JS を配信しない**ので、raw byte を数えている harness は
間違った対象を採点しています。gzip 列を入れたのはそのためです。

### `--rules`: 未移植の rule はいくらか——terser 自身に値付けさせる

差の合計は「次に何をやるか」を何も教えません。そこで terser を rule
ごとに 1 つ落として走らせ、差分をその rule の価値として読みます。
**移植する前に上限が分かる**測り方です。

そしてこれは**数え方で作った順位を訂正しました**。mtsc の comma 結合
文は terser の 1/9 しかなく（valibot 322 vs 36）、`sequences` が最大の
差に見えていました。値付けすると `sequences` は corpus 全体で約 1,500
byte、`join_vars` は約 **15,500 byte**。数と byte は違う rule を指して
いて、目的関数は後者だけです。

harness の自前のラベルが原因を誤らせる、というのはこのリポジトリで
何度も起きています（`computed_props`、`loops`、`typeofs`）。今回は
**自分の順位付けが同じ罠にはまった**ケースで、しかも実装前に測ったので
無駄な移植をせずに済みました。

### そして `--rules` の値付けにも同じ罠があった

`join_vars` は第 1 表で最大（+15,522 raw / +1,875 gzip）です。実装しよう
として mtsc 側を数えたら、**伸び代はほぼゼロ**でした。

| excalidraw | let | const | var | 宣言キーワード計 | bytes |
| --- | --- | --- | --- | --- | --- |
| terser | 318 | 1,379 | 17 | **1,714** | 281,053 |
| mtsc | 1,643 | 0 | 2 | **1,645** | 279,230 |

mtsc は既に terser と同等以上に結合しています（declarator group は
parser が作り、emit が `,` で出す）。terser の +12,355 は、terser 自身の
`collapse_vars` / `reduce_vars` が生む**余分な宣言を掃除する分**です。

つまり **rule の「terser にとっての値段」は mtsc の伸び代ではない。**
移植先が既にやっている rule では、上限が大きくても取り分は 0 です。

harness に第 2 表を足しました——各 rule が**下げる**構造カウントを両者の
出力で数え、mtsc > terser なら伸び代、mtsc <= terser なら覆われている。
proxy は測定ではなく「どれを本気で測る価値があるか」を言うだけですが、
`join_vars` に無駄な実装をするのは止められます。

| excalidraw | mtsc / terser | 判定 |
| --- | --- | --- |
| join_vars（宣言キーワード） | 1,645 / 1,714 | **覆われている** |
| sequences（`;`） | 3,759 / 2,897 | 少しあり |
| arrows / reduce_funcs（`function`） | **516 / 102** | **5 倍** |
| conditionals（`if (`） | 1,050 / 893 | 少しあり |
| comparisons（`===`） | 1,037 / 968 | わずか |

**rule は第 1 表と第 2 表の両方が言ったときだけ移植の価値がある。**
