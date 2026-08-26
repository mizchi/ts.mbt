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

`25 win, 1 tie, 6 loss`。`type-aware` は 7 件すべて win。

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

### 残っている loss

| 差 | rule | 何をすれば埋まるか |
| --- | --- | --- |
| +11 byte | `if_return` | `if (c) return; g();` → `c \|\| g()`。return の有無で分岐を演算子に落とす |
| +9 byte | `reduce_vars` | top-level `const k = 5` の値を、複数 use があっても use 側に伝播する |
| +9 byte | `negate_iife` | 正確には terser は IIFE の body を展開し、`sequences` で 1 文に潰している。`negate_iife` 単体ではない |
| +5 byte | `typeofs` | 移植済みだが、この case では terser がさらに周辺を畳んでいる |
| +2 byte | `computed_props` | 同上 |
| +1 byte | `loops` | terser の `sequences` が loop 前後の文を comma 式に merge している |

`sequences`（連続する文を `,` で 1 文に潰す）が 3 件に効いていて、
単独の rule としては次に大きい移植候補です。

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
