# 各書き換えを、意地の悪い値すべてに対して検査する

peephole の書き換えは主張です。「この 2 つの式は同じ意味である」。
`src/transform/peephole.mbt` の主張はほとんどが**一部の入力に対してだけ**
真で、間違っていたものはコメントでそう言って何も確認していませんでした。

```
//   x !== false    -> x     (saves 7 bytes)
```

これは `x` が boolean のときだけ真です。TypeScript の binder は
`symbol.constEnumOnlyModule !== false` を、たいてい `undefined` な field
に対して書きます。`undefined !== false` は `true` ですが、書き換え後は
`undefined` が残ります。

```sh
just verify-rule-equivalence
just verify-rule-equivalence --rule comparisons --verbose
```

## なぜ既存の harness では出ないか

corpus / fuzzer / real-world はどれも「このプログラムはまだ正しく動くか」
を、**普通の値**で組み立てたプログラムに対して聞いています。この harness
はもっと狭い質問を直接します——**この書き換えは `undefined` に対して、
`-0` に対して、`NaN` に対して、Symbol に対して、BigInt に対して、
`valueOf` を仕込んだ object に対して、`length` が負の array-like に対して
成り立つか**。

## 仕組み

各 case は最大 2 つの穴（`a`, `b`）を持つ関数 body です。1 つの case から
1 つのプログラムを生成し、その body を**値領域の直積**で評価します
（1 回の compile で約 600 通り）。結果を 3 通りで比べます。

| leg | 何 |
| --- | --- |
| reference | Node が TypeScript を直接実行（type stripping）。こちらの compiler は一切触らない |
| plain | `mtsc --bundle`、最適化なし |
| optimized | `mtsc --bundle --fold --minify` |

- `optimized != reference` かつ `plain == reference` → **optimizer の bug**
- `plain != reference` → lowering の bug（そう報告される）
- `optimized` の body が `plain` と textual に同一 → **INERT**。書き換えが
  発火していないので、その case は何も証明していない

値領域は「網羅」ではなく「反例」で選んであります。`{ length: -1 }` と
`{ length: NaN }` は `x.length > 0 -> !!x.length` が非負整数を仮定して
いるから、`valueOf` を仕込んだ object は `x.toString() -> "" + x` が
両者の一致を仮定しているから、Symbol と BigInt は他のあらゆる値が変換
できるところで throw するから、入っています。

## 最初の実行で出たもの

**38 case 中 23 件 unsound。** 根本原因は 9 個でした。

| 書き換え | 仮定していたもの | 反例 |
| --- | --- | --- |
| `x === true` → `x` ほか 3 兄弟 | `x` が boolean | `x = 1` で `x === true` は false、`x` は truthy |
| `!(a < b)` → `a >= b` ほか 3 兄弟 | 比較が NaN を経由しない | `a = undefined` で `!(a<b)` は true、`a>=b` は false |
| `-0` → `0` | Int に負のゼロがない | `Object.is(x, -0)`、`1/x`、`Math.sign` が区別する |
| `x.length !== 0` → `!!x.length` ほか 3 兄弟 | `.length` が非負の数 | `(0).length` は `undefined`。`{length:-1}` |
| `0 + x` / `x + 0` / `x - 0` / `x * 1` / `x * 0` | operand が数 | `undefined + 0` は NaN、`"a" + 0` は `"a0"`、`-1 * 0` は `-0` |
| `x.toString()` → `"" + x` | 両者が一致する | `undefined.toString()` は throw、`+` は `valueOf` を優先、Symbol は逆 |
| `String(x)` → `"" + x` | 同上 | `String(sym)` は動き `"" + sym` は throw |
| `x.hasOwnProperty(k)` → `Object.hasOwn(x,k)` | receiver が自分の実装を持たない | 持っている object（parse した JSON、config bag） |
| `Array.prototype.slice.call(x,0)` → `[...x]` | x が iterable | slice は array-**like** で足りる。`slice.call(0,0)` は `[]`、`[...0]` は throw |
| `(0, o.m)()` → `o.m()` | comma が冗長 | comma は `this` を落とすためにある。TypeScript がこの形を出す理由そのもの |
| `` `p${x}` `` → `"p" + x` | ToString と ToPrimitive が一致 | 一致しない。Date、boxed number、value object |

同じ rule が **2 か所に実装されていて片方だけ直っている**ケースが 2 件
ありました（relational negation と加法単位元）。harness は片方を直した
直後にもう片方を報告したので、そこで気づけました。

## 現在

`38 equivalent, 0 inert, 0 unsound`。

byte の代償は測ってあります。`just compare-terser` は
**25 win / 1 tie / 6 loss で変化なし**——1 件も勝敗が動いていません。
`.length` 比較や `x.toString()` の 3〜9 byte は、terser の corpus では
どの case にも効いていなかったということです。

## 「保証」の範囲

これは testing であって証明ではありません。ただ、この形が証明に一番
近づきます: **各書き換えの前提が case として明文化され、その前提の外で
発火しないことが機械検査されている**。rule を追加するときは case も
追加する、という運用にできます（`INERT` が「その case は書き換えを
発火させていない」と教えてくれるので、案山子 case も検出されます）。
