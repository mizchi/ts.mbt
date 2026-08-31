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

### `function` 516 vs 102 の正体: mtsc が arrow を function に戻していた

第 2 表で mtsc と terser が 5 倍離れていた唯一の項目です。追ったら
**未移植 rule ではなく mtsc 自身の退行**でした。

| excalidraw | `function` | `=>` |
| --- | --- | --- |
| unopt (`mtsc --bundle`) | 135 | 1,403 |
| mtsc (full pipeline) | **516** | **761** |

source の arrow 642 個のうち約 381 個が `function` になっています。
`peep_decl_rhs` が block-body arrow を `FuncExpr` に変換していて、理由が
2 つ書かれていて**両方間違っていました**。

**「block arrow は同等の function expression より短くなることはない」** —
単独の宣言では引き分けです（`function f(a,b){B}` と `let f=(a,b)=>{B}` は
同じ長さ、単一の素な parameter なら arrow が 2 byte 勝ち）。しかし
**連続する宣言は `let` を共有する**のに、function 宣言は毎回
`function ` を丸ごと払います。そして join を行う `fold.mbt` の pass は
`FuncExpr` 初期化子を**意図的に除外**します——つまり変換は arrow を
join の射程外に追い出していました。実測 **1 site あたり 6.9 byte**。

**「bundle での TDZ を hoisting で避ける」** — 入力が既に arrow なので、
元の module で宣言前に呼ぶことは TDZ で不可能です。bundler の module
順序は ESM の評価順と同じ。hoisting が救うのは初期化中に跨いで呼ぶ
**import 循環**だけで、それは `const` arrow なら ESM 自身が拒否します。
つまり変換は**unbundled では動かないコードを動かしていた**。削除で ESM の
挙動に戻ります。

削除の結果（9 bundle、悪化した target なし）:

| target | before | after | 差 |
| --- | --- | --- | --- |
| excalidraw | 279,230 | **276,601** | **−2,629** |
| hono | 21,139 | 21,007 | −132 |
| remeda | 28,521 | 28,459 | −62 |
| ts-pattern | 8,567 | 8,509 | −58 |
| neverthrow | 5,166 | 5,144 | −22 |
| immer | 20,383 | 20,367 | −16 |
| valibot | 86,979 | 86,973 | −6 |
| **合計** | | | **−2,925** |

`function` は繰り返しの多い長い token なので gzip が得意なはずで、実際
gzip の取り分は小さい（excalidraw −229、合計 −250 前後）。それでも
**符号は raw と同じ**なので採用しました。

`--rules` 第 1 表がこの rule を安く値付けしていたことにも意味があります
（`arrows` は corpus 全体で +311、excalidraw では 0）。**terser 側で安い
のは terser がその変換をしていないから**で、mtsc 側で高いのは mtsc が
逆向きの変換をしていたからです。第 2 表が構造カウントを両者で並べるのは
このためです。

### typebox に残る +13.8% の帰属: 単一呼び出し関数の inline

`.name` の narrowing で +51.3% → +13.8% になった後の残りです。corpus で
2 桁の差が残る唯一の target なので分解しました。

まず**構造 proxy はほぼ互角**と言います:

| typebox | mtsc / terser |
| --- | --- |
| join_vars（宣言キーワード） | 135 / 164 |
| sequences（`;`） | 235 / 231 |
| conditionals（`if (`） | 26 / 23 |
| arrows（`function`） | 844 / 762 |

つまり残りの +10,901 はこれらの rule ではありません。byte を分類すると:

| 分類 | terser | mtsc | 差 |
| --- | --- | --- | --- |
| **識別子 byte** | 45,250 | 54,579 | **+9,329** |
| 記号 | 28,800 | 30,403 | +1,603 |
| 文字列 | 5,077 | 5,046 | −31 |

**85% が識別子**です。そして長さ分布が決定的:

| 長さ | terser | mtsc | 差 |
| --- | --- | --- | --- |
| 1 | **9,540** | 8,218 | **−1,322** |
| 2 | 3,888 | 5,355 | +1,467 |
| 4 | 316 | **1,142** | **+826** |

distinct 識別子は terser 1,153 / mtsc **1,692**。1 文字名は両者ちょうど
54 個（使い切っている）で、mtsc は 539 個多い名前を 2 文字以上に押し出して
います。

**命名の欠陥ではありません。** mtsc は scope 内で短名を再利用できます
（`function a(a,b){…}function b(a,b){…}`）。名前が多いのは**生き残っている
binding が多い**からです:

| | 関数 | 宣言 1 回・使用 1 回 | distinct 名 |
| --- | --- | --- | --- |
| mtsc | 841 | **422** | 1,692 |
| terser | 527 | **113** | 1,153 |

**terser は単一呼び出しの関数を約 309 個 inline しています。** mtsc の
`call_inline` は body が `return <pure expr>` 1 文のものだけを対象にする
ので、文を持つ body は残ります。422 のうち **414 は export 節に無い**
（つまり候補）で、body の中央値は 36 byte、p90 は 100 byte。wrapper だけで
**414 × 約 12 = 約 4,968 byte**、加えて空いた 1 文字 slot が他の名前を
短くします。合わせて +10,901 の大半を説明します。

これは「1 つの gate」ではなく**新しい pass**です。単一呼び出し地点への
文 body の inline には固有の証明義務があります: `arguments` / `this` /
再帰 / `var` の hoist が呼び出し側 scope に漏れること / label の衝突 /
そして **body の局所名と呼び出し側 scope の名前衝突**——これは
`case54` が掘り出した逐次代入 capture と同じ族の、より大きい形です。
mangle が inline より前に走るので、body の局所名も呼び出し側の binding も
`a`,`b`,`c` になります。

`--rules` の第 1 表がこれを `collapse_vars` +2,925 / `inline` +2,095 /
`reduce_funcs` +1,164 に分散して値付けしていたこと、そして私の第 2 表の
proxy（宣言キーワード数）が `collapse_vars` を**捉えられていなかった**
ことも記録しておきます。proxy は「どれを本気で測る価値があるか」しか
言いません——今回はそれで join_vars を止められた一方、この項目は proxy が
互角と言った裏で 5,000 byte 隠れていました。

## その仮説を実験したら、外れました（#87 = 却下）

上の節は「単一呼び出し関数を inline すれば typebox で約 5,000 byte」と
書いています。**実験の結果、これは二重に間違っていました。**

### 1. 「文 body」は 1% しかない

mtsc の typebox 出力を AST で数え直すと、1 回だけ呼ばれて他から参照され
ない関数は 371 個。その **body の形**と**呼び出し位置**は:

| body の形 | 数 | | 呼び出し位置 | 数 |
| --- | --- | --- | --- | --- |
| `return <expr>` 1 文 | **313** | | 三項演算子の枝 | 159 |
| 文 + `let`/`const` | 52 | | 配列リテラルの要素 | 101 |
| 文のみ | 6 | | 呼び出しの引数 | 56 |
| | | | **文の位置** | **4** |

上の節が勧めていた出発点——「call が文の位置にある多数派を block として
splice する」——は **371 のうち 4**、1% です。そして 313 は
`call_inline` が**構造的にすでに受け付ける形**でした。文 body は
最初から blocker ではなかった。

### 2. 本当の blocker は body の純粋性で、外しても 26 byte

`expr_is_inlinable_body` は body が pure であることを要求していました。
getter 修正以降 property read は impure なので、`return schema.kind` も
`return Type.Number(x)` も——ライブラリの 1 行 helper がまさにこの形——
拒否されます。拒否理由を数えると、typebox で調べた約 1,000 関数のうち:

| 拒否理由 | 数（1 pass あたり） |
| --- | --- |
| **impure-body** | **586** |
| 複数文の body | 281 |
| rest / default 付き parameter | 95 |
| 受理 | **35** |

そこで純粋性要求を外しました。impure な body に必要なのは実際には
(a) 引数が pure（body 自身の効果が引数を追い越さないため）と
(b) 宣言が死ぬこと（size）だけです——body は呼び出し地点で 1 回走り、
その地点は call があった場所なので、効果の回数も場所も変わりません。

**結果は typebox −26 byte、他 8 target は 0。**

さらに `expr_contains_function` の全面拒否（typebox の候補 394 個、
`return xs.map(x => …)` が原因）を「parameter を closure 内から読む場合
だけ拒否」に緩めました。**0 byte。** 緩めた候補はその次の gate
（複数の呼び出し地点）で止まるからです。

### 3. 複数地点への inline は損

天井を測りました。size gate を外して impure body を全地点に inline:

| target | 差 |
| --- | --- |
| typebox | **+1,896** |
| excalidraw | +1,009 |
| superstruct | +363 |
| ts-pattern | +306 |
| hono | +208 |

node 数の閾値によるコストモデルも掃きました。`K=4`（body が 4 node 以下、
`b(e,3)` 程度）でも hono +208 で純損、`K=6` は excalidraw +762。
**正の領域はありません。** 最善は「呼び出しが 1 箇所だけ」（= typebox
−26、他 0）で、それより緩めると必ず損をします。

コード変更は**全部差し戻しました**。

## では本当の差分は何か: **識別子の文字数**

#86 の帰属（関数の個数）は相関としては正しく、機構としては間違っていた。
出力を「変数位置の識別子」だけで測り直すと:

| | terser | mtsc | 差 |
| --- | --- | --- | --- |
| bytes | 79,127 | 90,355 | **+11,228** |
| 変数識別子の出現数 | 12,777 | 13,862 | +1,085 |
| **識別子の総文字数** | **16,416** | **21,581** | **+5,165** |
| 長さ 1 | 9,442 | 8,193 | −1,249 |
| 長さ 2 | 3,265 | 4,762 | +1,497 |
| **長さ 4** | **4** | **828** | **+824** |

差の **46% が識別子の文字数**です。そして長さ 4 が 828 対 4——長さ 3 が
両方 3 個しかない（つまり枯れていない）のに長さ 4 が 828 あるのは、
**mangler が rename を諦めた名前**だという意味です。

中身は 1 種類でした: **`type` が 824 回**。
`function a6(type, a = {})` が bundle 中に並んでいます。

> 最初にこれを数えたとき、TypeScript の AST では property 名も
> `Identifier` なので `type` が 856 回出て「長さ 4 の識別子」列の中身が
> ほぼ識別子ではありませんでした。mangle の名前プールと wire format を
> 混ぜた数字は、聞いている質問と別の質問に答えます。変数位置に限る
> フィルタを入れてから読むこと。

原因は `mangler_builtin_reserved`。この集合は
`ScopeFrame::bind` で**2 つの別の質問**に使われています:

* 生成プールが**作ってはいけない**名前（globals と予約語）← リストの目的
* 既存の binding を**rename してはいけない**名前 ← こちらは別問題

`type` / `namespace` / `declare` / `abstract` / `readonly` は TypeScript の
**contextual keyword** で、JavaScript の変数名として——strict mode でも
——完全に合法です。1 番目の質問には関係なく（プールは長さ 1 から配るので
4 文字に到達しない）、2 番目には純粋なコストでした。

残したものは strict mode で予約されており、module は strict です:
`interface` / `implements` / `private` / `protected` / `public` /
`static` / `enum`、および無条件の予約語。

**5 語をリストから外した結果**（挙動は全 harness で一致）:

| target | 差 |
| --- | --- |
| `typescript.js`（9 MB） | **−13,613** |
| typebox | **−2,440** |
| react | **−1,939** |
| excalidraw | −236 |
| valibot | −99 |
| immer | −45 |
| superstruct | −8 |
| hono / remeda / ts-pattern / neverthrow | 0 |

合計 **約 −18.4 KB**、大きくなった target はありません。typebox の
terser 差は **+14.2% → +11.1%**。

`fixtures/mangle-safety/case56-contextual-keyword-bindings` が安全側を
押さえます: 5 語それぞれを宣言し、読み、closure に閉じ込め、parameter で
shadow し、nested 関数でもう一度 shadow し、export し、同じ綴りの
**object key** を並べて（そちらは property なので動いてはいけない）
Node と比べます。出力では全 binding が 1 文字になり、key は無傷です。

**修正後の同じ表**（`node scripts/compare_terser_bundles.mjs --names`）:

| | terser | mtsc（前） | mtsc（後） |
| --- | --- | --- | --- |
| bytes | 79,127 | 90,355 | **87,915** |
| 識別子の総文字数 | 16,416 | 21,581 | **19,117** |
| 長さ 1 | 9,442 | 8,193 | 9,021 |
| 長さ 2 | 3,265 | 4,762 | 4,764 |
| 長さ 4 | 4 | 828 | **4** |

長さ 4 は terser と同数になりました。`--names` の第 2 表は
「mtsc に残る長さ 4 以上の変数名のうち terser が消したもの」を名前で
出します——typebox では `types` x3 と `Boolean` x1 だけです。

**残る差分**は 2,701 文字で、内訳は長さ 1 が 421 個少なく長さ 2 が
1,499 個多いこと、そして識別子の**出現数**が 1,091 多いこと（= terser が
inline した分）。後者は上で測ったとおり mtsc の pass 順では取れません。
**terser は inline してから mangle するので、宣言を消すたびに 1 文字 slot
が空いて他の名前が短くなる**——mtsc は inline 時点で名前を配り終えている
ので、宣言を消しても宣言自身の byte しか戻りません。長さ 1/長さ 2 の偏り
も同じ原因である可能性が高い（名前プールの競合が減る）。これは新しい pass
の問題ではなく **pass 順の問題**で、次に測るならそこです。

**現在の head-to-head**（raw / gzip）:

```
  target            unopt    terser      mtsc     diff       % │ gz diff       %
  hono             58,885    19,685    20,991   +1,306    6.6% │    +361    4.8%
  valibot         228,304    88,223    86,874   -1,349   -1.5% │    +323    2.2%
  typebox         367,321    79,127    87,915   +8,788   11.1% │  +3,153   16.4%
  immer            49,349    20,287    20,130     -157   -0.8% │    +196    2.7%
  neverthrow        9,991     5,262     5,144     -118   -2.2% │     -22   -1.6%
  ts-pattern       20,772     8,079     8,164      +85    1.1% │    +173    6.7%
  superstruct      20,785    10,500    10,425      -75   -0.7% │     +44    1.3%
  remeda           80,864    28,909    28,459     -450   -1.6% │    +166    1.8%
  excalidraw      788,038   281,053   276,515   -4,538   -1.6% │  +1,672    1.8%

  mtsc smaller on 6/9 raw, 1/9 gzipped
```
