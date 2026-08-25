# mangle の偽陽性を fuzzing で探す

`--mangle-properties` が怖いのは、**間違ったときに静かだから**です。bundle は
動く。test は通る。どこか 1 箇所の `JSON.stringify` が
`{"count":1}` ではなく `{"a":1}` を返すようになる。それだけです。

既存の 2 つの検証はこれを見つけられません。
[`fixtures/mangle-safety`](../fixtures/mangle-safety) は**誰かが思いついた**
状況を網羅しますし、[real-world 検証](./real-world-minify.md) は
**実在する 5 パッケージ**を網羅します。どちらも「誰も思いつかなかった
ケース」の側にはいません。

なので、誰も書いていないプログラムを生成します。

```sh
just fuzz-mangle --iterations 500
just fuzz-mangle --seed 6 --iterations 1 --no-shrink   # 1 件を再現
```

## 何をしているか

1 つの seed から決定的にプログラムを作り、**同じ source を 2 回 compile**
します。片方は mangle あり、片方はなし。圧縮 pass は両側で同一なので、
差が出たらそれは rename が原因です（`--fold` を片側だけに掛けたら、
folding bug が mangling bug として報告されてしまう）。

```
                     ┌─ mtsc --bundle --treeshake --fold --minify ────────┐
generated .ts ───────┤                                                    ├─→ 比較
                     └─ 同上 + --mangle --mangle-properties ──────────────┘
```

差の判定は**タグ付き encoding** の上で行います。`JSON.stringify` では
`undefined` と「property が無い」が区別できず、`NaN` / `-0` / `Infinity` が
すべて `null` になります。それらは畳み込みバグがちょうど作る値なので、
値は `["number","-0"]` のような tuple に符号化してから比較します。

観測は**名前が値になる操作**に寄せてあります。値だけを見る観測は、
property がどう rename されても通ってしまうからです。

- `JSON.stringify(bag)` / `Object.keys(obj).sort()`
- class instance の `JSON.stringify` と `Object.keys`
  （native の method は prototype 側で non-enumerable なので
  `Object.keys` から**見えない**——「method を rename した」と
  「field を rename した」を区別するのはこの観測です）

## 元にした実装との違い

構造は Terser の [`ufuzz`](https://github.com/terser/terser/blob/v5.50.0/test/ufuzz.js)
を [oxc-project/oxc#25594](https://github.com/oxc-project/oxc/pull/25594)
経由で踏襲しています。決定的な seed、上限付き loop、共有の呼び出し予算、
タグ付き値符号化、隔離 context でのバッチ実行。違うのは 2 点です。

### 1. source text ではなく tree を生成する（だから縮められる）

上流の generator は RNG から**文字列**を直接組み立てます。それは
miscompilation を*見つける*には十分で、*説明する*には無力です。失敗の
手がかりが seed だけなので、成果物は「100 行のうち 4 行が本質」という
プログラムで、削るのは人間の午後の仕事になります（PR の説明文にも
"requiring human minimization of failures" と書かれています）。

ここでは生成物が JSON の tree（[`fuzz-ir.mjs`](../scripts/lib/fuzz-ir.mjs)）
なので、**失敗を見つけた loop がそのまま縮小もできます**
（[`fuzz-shrink.mjs`](../scripts/lib/fuzz-shrink.mjs)）。greedy な delta
debugging で、statement の塊を落とす → 宣言を落とす → class member を
落とす → 式を子で置き換える、を「まだ失敗する」限り繰り返します。

実測では **273 node → 6 node**、**87 → 4** まで落ちます。成果物は
「seed 12」ではなく、これです。

```ts
class C1 {}
for (let brake3 = 4; brake3-- > 0 && (new C1().c1f0); ) { ; }
console.log([a]);
```

縮小候補が **compile できなくなったら報告せず却下**します。まだ参照されて
いる宣言を消すのが典型なので、参照を自前で追うより compiler に訊くほうが
安いからです。

受理条件は「まだ壊れる」ではなく「**まだ同じ壊れ方をする**」です。
signature（throw の name と、識別子と数字を正規化した message）を握って
おかないと、稀なバグから始めた縮小が、小さくなる途中でよくあるバグに
乗り換えてしまい、稀なほうの再現が失われます。

### 2. 文法が mangler の証明義務を狙っている

汎用の JS fuzzer は圧縮バグを探します。それも価値がありますが
（`--no-mangle` で今も探せます）、ここでの問いはもっと狭い。安全性の解析が
**推論しなければならない構文**に重みを置いています。

- **computed-key の READ**（`holder[k]`）——key が予測できないので、
  到達可能なものすべてを予約するしかない。一度これが逆になっていました
  （read が致命的で、write はそうではない）
- **computed-key の WRITE と `delete`**——何の名前も観測しないので、
  何も汚染してはいけない
- `in` / spread / `Object.keys` `values` `entries` `assign` /
  `JSON.stringify` / `structuredClone` / `for...in`——どれも property の
  **名前を値にする**ので、どれも sink
- class の method / field / static / accessor / `#private` field——native の
  method は prototype 上で non-enumerable、`#private` は class body の外から
  名指しできない。どちらも解析が攻撃的に振る舞ってよい場所で、つまり
  推論の off-by-one が出る場所
- property 名を宣言する interface / type alias——`--reserve-typed-props` の入力
- rename を伴う destructuring と computed key——mangler が 2 箇所を同時に
  書き換えねばならない site

### 3 本目の脚: reference

これは元の実装には無く、ここでは既存の
[mangle-safety harness](../scripts/verify_mangle_safety.mjs) から持ち込んだ
ものです。baseline bundle が走らなかったとき、seed を skip する前に
「**元のプログラムは動くのか**」を訊きます。Node が TypeScript を
type stripping で直接実行するので、我々の compiler は一切関与しません。

- 元も落ちる → 本当の skip（生成物がそもそも壊れている）
- 元は動いて我々の bundle が落ちる → **findings**

これが無かった最初の版では、16 seed のうち 11 個が「skip」として
黙って捨てられていました。全部 mtsc のバグでした。

## 見つかったもの（seed 0..119、両 shape）

12 の異なる family。それぞれ最小化済みの再現が
`_build/fuzz-mangle/` に出ます。

| 回数 | 種別 | 症状 | 最小 |
| --- | --- | --- | --- |
| 17 | compress | `ReferenceError: keys is not defined` | 14 node |
| 6 | compress | `TypeError: C.f is not a constructor` | 6 node |
| 4 | **mangle** | 到達可能な class field が消える | **5 node** |
| 4 | compress | `TypeError: C.m is not a constructor` | 6 node |
| 3 | compress | `Identifier 'arr' / 'x' has already been declared` | 4 node |
| 2 | compress | `Lexical declaration cannot appear in a single-statement context` | 19 node |
| 1 | **mangle** | mangle 後の bundle が `Identifier 'b' has already been declared` | 24 node |
| 1 | compress | `Unexpected identifier 'vN'` | 19 node |
| 1 | compress | `Unexpected token '('` | 14 node |
| 1 | compress | `Unexpected token 'new'` | 6 node |

### 本題だったもの: 到達可能な field が消える

5 node。`console.log` は sink で、instance はそこに流れ込み、その
own enumerable property は観測可能です。

```ts
class C0 { c0f0 = 's'; }
console.log([new C0()]);
```

```js
// baseline: class C0{constructor(){this.c0f0="s"}}console.log([new C0])
// mangled:  class c{}console.log([new c])
```

```
$ node baseline.mjs   → [ C0 { c0f0: 's' } ]
$ node mangled.mjs    → [ c {} ]
```

field が消えています。dead-property pass が、**bundle 内で誰も読まないが
instance が sink に逃げる** field を削っています。class 名の `C0` → `c` は
正しい rename です（encoder は function の `name` を意図的に見ません。
local binding を rename すれば `Function.name` は変わり、それを保つ
minifier は存在しないので、見れば成功した mangle まで失敗報告になります）。

### 圧縮側: 意味を持つ括弧が落ちる

3 family が同じ場所です。emitter が、外すと parse が変わる括弧を外します。

```ts
let v2 = (trace.push(0), x);      // → let v2=trace.push(0),x;
                                  //   sequence が 2 つ目の declarator になる
let v2 = (trace.push(0), new C0()); // → let v2=trace.push(0),new C0;
new C1().c1f0                     // → new C1.c1f0
                                  //   new の空引数リストは、member access の
                                  //   対象になるときは省略できない
```

### 圧縮側: computed key が参照として数えられていない

```ts
const keys = ['alpha', 'beta'];
function f1() { const { [keys[0]]: v2 } = bag; }
```

treeshake が `keys` を未使用と判断して宣言を落とし、`keys[0]` は残ります。
object binding pattern の `key_expr` を参照収集が歩いていません——
[以前 mangle 側で直したのと同じ死角](./real-world-minify.md)の、DCE 側です。

## 現状と限界

- **圧縮バグが mangling の信号を埋めています。** sink shape の 120 seed で、
  比較できたのは 13 件、baseline が壊れたのが 35 件。問いを問える状態に
  するには、まず emitter を直す必要があります。
- 生成される TypeScript は**型としては正しくありません**。`--no-check` で
  走らせていますし、Node の type stripping も型検査しません。ここで
  探しているのは emit と rename の正しさであって、型検査の正しさでは
  ありません。
- shape は 2 つ（`sink` / `export`）。export shape の観測は module の
  export 面を外から見るので、内側に観測を書く場合と違って名前が
  到達可能になりません。
- CI には**入れていません**。campaign が commit する価値のある規模で
  静かになってから、exit status がそのまま gate になります。
