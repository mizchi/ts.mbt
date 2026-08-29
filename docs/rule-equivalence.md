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

## 2 回目: 表に無い rule は検査されていなかった

typebox の bundle が load で死んでいた原因が
`Array.from({ length: 256 }).map(…)` -> `[...{ length: 256 }].map(…)`
でした。`Array.from` は **array-LIKE** を受け、spread は
**ITERABLE** を要求するので、これは throw します。

問題はこの rule が **表に無かった**ことです。value domain には
`{ length: 0 }` も `{ length: -1 }` も既に入っていたので、case を
1 行足すだけで初回から落ちていました。

そして最悪なのは、**3 行下に答えが書いてあった**ことです。
`Array.prototype.slice.call(x)` -> `[...x]` は同じ理由で削除済みで、
その理由がコメントとして残っていました。知識は隣にあり、rule は
出荷されていた。

これは構造的な穴です。この harness は **「誰かが case を書いた rule」**
だけを検査し、**case が無い rule については何も報告しません**。
peephole と fold には合わせて ~235 個の rewrite があり、case は
38 個でした。カバー率は約 16%、しかもどの 84% が未検査かは
どこにも書かれていない。

そこで方針を変えました: **妥当性が受け側の型に依存する rewrite は、
怪しく見えるかどうかに関係なく全部 case を書く**。それが
「型を仮定して何も確認しない」が隠れられる部分集合です。
built-in method の書き換えがその全体で、11 個。6 個が unsound でした。

| rule | 反例 | 対処 |
| --- | --- | --- |
| `Array.from(x)` -> `[...x]` | `Array.from({length:0})` は `[]`、spread は throw | `is_definitely_iterable` |
| `Array.prototype.M.call(x, …)` -> `x.M(…)` | string / `arguments` / array-like に method が無い。逆に receiver が同名 method を持つ場合は built-in ではなくそれを呼ぶ | 削除 |
| `x.slice(0)` -> `[...x]` | `"ab".slice(0)` は `"ab"`、`[..."ab"]` は `["a","b"]` | 削除 |
| `[].concat(a)` -> `[...a]` | `concat` は非 array を 1 要素として append。`[].concat(1)` は `[1]`、`[...1]` は throw | 引数が全部 array literal のときだけ |
| `Math.pow(a,b)` -> `a**b` | `Math.pow(10n,10n)` は throw、`10n ** 10n` は計算する | 片方が非 BigInt と証明できれば可 |
| `f.apply(null, a)` -> `f(...a)` | `apply` は array-like も `null`/`undefined`（引数なし）も受ける | `is_definitely_iterable` |

domain にも 1 つ足しました: `{ length: 2, 0: "a", 1: "b" }` —
`length` と index property を持ち `Symbol.iterator` を持たない、
本物の array-like。これらの built-in がまさに扱うために存在する形です。

証明は**構文的**で、意図的に狭くしています。`ArrayLit` / `StringLit` /
`new Set(…)` は自分の型を名乗りますが、`Var` は文脈でどれだけ array に
見えても証明になりません。型表を読めば広げられる（peephole の
`PeepCtx` は今それを持っていない）ので、E7 の候補です。

`Array.prototype.M.call` で `slice` だけが除外されていたのは示唆的です。
family 全体の問題を、誰かが踏んだ 1 例として直していた。

## 3 回目: spread 要素を 1 個として数えていた

remeda を corpus に入れたら `reverse([1,2,3])` が `[1,2,3]` を返しました。
実装は

```ts
function reverseImplementation<T>(array: readonly T[]): T[] {
  return [...array].reverse();
}
```

これが `return [...array]` にコンパイルされていました。
`[...array]` は要素 1 個の `ArrayLit`（要素は `Spread`）としてパースされ、
**1 要素の reverse は no-op** なので `.reverse()` が消えた。

`fold_array_method` の各 fold は `items` を**位置で**読みます——length、
順序、どの要素がどこにいるか。`Spread` はその全部を壊します:
runtime に何個の値になるかを構文が言っていない 1 個のノードだからです。

各 fold が既に持っていた `is_pure_value` guard は効きません。
**変数の spread は完全に pure** で、purity は問題ではなかった。
位置が問題でした。

そして `.length` fold には**すでに spread guard が付いていました**——
fuzzer が見つけて、その 1 箇所で終わっていた。`Array.prototype.M.call`
で `slice` だけが除外されていたのと同じ形です。今回は `items` を位置で
読む fold 全部に case を書き、guard を 1 つの述語
(`no_spread_elements`) に集約しました。index fold にも穴があり、
`[...a][0]` は **`return ...a` という構文エラーを出力**していました。

## 4 周目: bitwise —— case が 1 件もなかった family

この harness に **bitwise の case は 1 件もありませんでした**。そして
そのテーブルには誤った rule が 6 件ありました。「case を書いた rule に
ついてだけ報告し、case のない rule については何も言わない」という穴が、
`Array.from(x)` に続いて 3 度目に出た形です。

見つけたのは fuzzer で、`switch` 経由でした:

```ts
switch (('alpha' & -1)) {
case 0: break;
default: trace.push(2);      // 走ってはいけない
}
```

`'alpha' & -1` は `0` (`ToInt32(NaN)` が `0`) なので `case 0`。ところが
`x & -1 → x` が発火して scrutinee が `"alpha"` になり、`default` が走った。
`--bundle --fold` だけで、mangle は無関係です。

原因は 6 rule に共通する 1 つの読み違いです。**これらの演算子は強制変換
する**のに、identity 書き換えは**変換前の operand を返す**:

| rule | 反例 |
|---|---|
| `x & -1 → x` | `"alpha" & -1` は `0`、`1.5 & -1` は `1` |
| `-1 & x → x` | 同上 |
| `x \| x → x`, `x & x → x` | `"alpha" \| "alpha"` は `0` |
| `x - x → 0` | `"a" - "a"` は `NaN`、`5n - 5n` は `0n` |
| `x & 0 → 0`, `x \| -1 → -1` | `5n & 0` / `5n \| -1` は **throw** |
| `x ^ x → 0` | `5n ^ 5n` は `0n`、Symbol は throw |
| `x ** 0 → 1` | `5n ** 0` / `Symbol() ** 0` は throw |

さらに `is_number_valued` —— `Add` / `Sub` / `Mul` / `Div` の identity が
**すでに持っていた** numeric gate —— が `cmp_kind` に委譲していて、
`cmp_kind` は **BigInt literal を `CmpNum` と答えます**。関係比較では
それが正しい（BigInt と Number の混在が許され、NaN を経由しない唯一の
場所）が、算術では逆で `5n - 0` は throw します。つまり `5n - 0 → 5n`、
`5n * 1 → 5n`、`5n / 1 → 5n` の 3 件が、gate のある側にも同じ形で
入っていた。呼び出し側 7 箇所ではなく `is_number_valued` の定義 1 箇所を
直しました。

gate は 2 つの述語に分けました。identity は
`is_int32_valued`（値がすでに int32——bitwise/shift の結果、範囲内の整数
literal）を要求し、annihilator は `is_number_coercible`（`ToNumber` が
成功して Number を返す——BigInt と Symbol だけを除く）を要求します。

self-operand の 4 rule (`x|x`, `x&x`, `x^x`, `x-x`) は**削除**しました。
正しく gate すると bare `Var` はどれも満たさず、満たす式は bare `Var`
でないので、**発火しえない pattern になる**からです。死んだ pattern は
次に監査する人には生きた pattern に見えます。

case は壊れていた 6 件だけでなく **family 全体**に書きました。誤りの
原因が rule ではなく**演算子の性質**（強制変換する）なので、case が
無い rule は全部同じ疑いの下にあります。

## 5 周目: 値の domain に getter が無かった

domain には**poisoned `valueOf`**——coercion の危険——が最初から入って
いたのに、**getter**——read の危険——が入っていませんでした。property
read は accessor なら任意のコードを走らせます。

```moonbit
PropAccess(recv, _) => is_pure_value(recv)
```

`is_pure_value` は「receiver が pure なら read も pure」と答えていました。
これは `recv` を**評価する**ことについての主張で、そこから `.p` を
**読む**ことについての主張ではありません。

```ts
class Holder { get p() { trace.push(1); return 5; } }
const h = new Holder();
```

`--bundle --treeshake --fold` で **4 つの形が getter の body を捨てて
いました**: 裸の `h.p;`、`void h.p;`、捨てられる comma の左
`(h.p, 9)`、そして array literal の `.length` fold `[h.p, 1].length`。
数える / memoize する / log する / 遅延初期化する getter——getter が
存在する理由そのもの——が走らなくなります。

domain に自己カウントする getter を入れました:

```js
"{ hits: 0, get tick() { this.hits += 1; return this.hits; } }"
```

`a.tick` を読むと `a.hits` が増えるので、**比較される値の中に**「read が
起きたか」が現れます。最初に書いた 2 case は `[n, a.hits]` を返していて
**通ってしまいました**——array 返り値では差が出ず、optimized 側の body が
目に見えて `[2, a.hits]` になっていても equivalent と報告されます。
「効果が起きた」を主張する case は、**比較される値そのものに**それを
落とさないと coverage の形をした何もしない case になります。scalar
(`n + a.hits * 10`) に直して 4/4 が検出するようになりました。

健全な答えの代償は先に測りました: TypeScript の 3.5 MB 出力に **+845
byte (0.02%)**、react +3、checker.ts は **255 byte 減**、hono / valibot /
terser corpus は変化なし。「この receiver の宣言された shape に accessor
は無い」という type-driven な例外を正当化するには小さすぎます。

## 現在

`76 equivalent, 0 inert, 0 unsound`。

byte の代償は 2 回測ってあります。

1 回目（初回の 9 件）: `just compare-terser` は
**25 win / 1 tie / 6 loss で変化なし**——1 件も勝敗が動いていません。
`.length` 比較や `x.toString()` の 3〜9 byte は、terser の corpus では
どの case にも効いていなかったということです。

2 回目（built-in method の 6 件）: terser 比は**やはり変化なし**
（25 / 1 / 6）。ただし実 library では払っています——type-aware corpus の
9 target のうち 4 つで合計 ~700 byte 増（typebox +182、excalidraw +206、
immer +29、zod +23）。壊れない側に寄せた分の値段です。

## 「保証」の範囲

これは testing であって証明ではありません。ただ、この形が証明に一番
近づきます: **各書き換えの前提が case として明文化され、その前提の外で
発火しないことが機械検査されている**。rule を追加するときは case も
追加する、という運用にできます（`INERT` が「その case は書き換えを
発火させていない」と教えてくれるので、案山子 case も検出されます）。
