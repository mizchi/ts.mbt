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

## 3 本目の脚を、mismatch にも使う

reference を「baseline が走らなかったとき」だけに使っていた版には、
もっと大きな穴がありました。baseline と candidate が**違う**とき、
どちらが悪いのかを訊いていなかったのです。既定で rename を疑う、
という決めつけです。

それを教えたのがこれです。

```ts
class C0 { #secret = 7; }
console.log([new C0()]);
```

baseline は `C0 { __private_brand__0__secret: 7 }`、mangle 後は `c {}`。
「生きている field を消した」と読みました。**元のプログラムを Node で
走らせると `C0 {}` です。** 本物の `#private` field は own enumerable
property ではありません。mangle 側が正しく、壊れているのは**unmangled
な bundle** ——mtsc の private field lowering が `#secret` を普通の
可視 property にしていました。

なので reference が裁定します。2 つの compile 出力のうち、元と食い違う
方が悪い。

| | 意味 |
| --- | --- |
| reference == baseline | `mangle` —— rename が間違っている |
| reference == candidate | `lowering` —— 共有 pipeline が間違っていて、mangle が偶然直した |
| どちらでもない | `both` |

## 見つかったもの

seed 0..299、両 shape、404 comparison。**mangle の偽陽性は 1 件**です。
残りは lowering / 圧縮側のバグで、mangle は無関係でした。

| 回数 | 種別 | 症状 | 最小 | 状態 |
| --- | --- | --- | --- | --- |
| 104 | lowering | `#private` field が own enumerable になる | 5 node | 未修正（[fixtures/fuzz-findings](../fixtures/fuzz-findings)） |
| 2 | both | 同上（両出力に brand 名が残る経路） | — | 同上 |
| 2 | compress | `ReferenceError: fN is not defined` | — | 一部修正、残あり |
| 2 | compress | `Invalid left-hand side expression in prefix operation` | — | 未調査 |
| 1 | **mangle** | 観測される object への property write を追えていない | 12 node | 未修正（[同](../fixtures/fuzz-findings)） |

### 修正したもの（この campaign が見つけたもの）

最初の 120 seed では 13 comparison に対し 35 が「baseline が壊れている」
でした。問いを問える状態ではなかったので、まず直しました。

| 症状 | 原因 | 最小 |
| --- | --- | --- |
| `C.f is not a constructor` | `new C()` の空引数リスト省略が member access の head では不正 | 6 node |
| `Identifier 'x' has already been declared` | declarator の初期化子を precedence 0 で出力し、comma 式の括弧が落ちて 2 つ目の declarator になっていた | 4 node |
| `Lexical declaration cannot appear in a single-statement context` | 宣言だけの block を `do` 本体で de-brace | 19 node |
| `keys is not defined` | `count_var_uses` が declaration の **binding** を歩かず、computed key 内の参照を数えていなかった | 14 node |
| `let x=1;let x=2` (mangle 時は同名衝突) | 「multi-declarator の Block」と「本物の nested block」を emit が区別できていなかった | — |
| `[0]` vs `[-1]` | treeshake の `is_pure_init` が `UnaryOp` の**演算子を無視**（`c--` が pure 扱い） | 4 node |
| `[12]` vs `[11]` | `[a, f()].length` → `2` の fold が要素の副作用を捨てていた | 6 node |
| `f0 is not defined` | `count_var_uses` は `try` 内の使用を local と数えるのに、`substitute_stmt` に `Try` の arm が無かった | — |

同じ形のバグが繰り返し出ています——**対になった 2 つの walker のうち
片方だけが、ある構文を知っている**。`count_var_uses` と
`collect_var_refs`、`is_pure_init` と `purity.mbt`、`count_var_uses_stmt`
と `substitute_stmt`。fuzzer が見つけているのは、その非対称です。

結果:

```
最初      13 compared,  35 broken baselines, 10 compress families
8 修正後  404 compared,   2 broken baselines,  1 mangle finding
```

出力は不変です。161/161 の mangle-safety case、real-world 5 target すべて
挙動一致（`typescript.js` だけ括弧の分 36 byte 増）。

## 本題だったもの: 到達可能な field が消える

これは**修正済み**です。sink に流れ込む値の property が予約されない
穴が 2 つありました。

```
console.log(o)      → { k: 1 }        ✓ 元から正しい
console.log([o])    → [ {} ]          ✗ container を通ると追えない
console.log({w:o})  → { w: {} }       ✗ 同上
console.log(new C()) → a {}           ✗ 無名の instance に binding が無い
const i = new C(); console.log(i)     ✓ binding があれば正しい
```

原因は `seed_from_expr` が **binding を追い、無名の部分式を追わなかった**
ことです。container（array / object literal / spread / template）の中身へ
降りるようにし、`New(C, …)` は **class の宣言 symbol** を seed して
`reserved_props_from_observability` がその member 名に変換するように
しました（`class_member_names`）。

内部だけで読まれる field は今も mangle されます——予約が増えたのは
観測される経路だけで、real-world 5 target の byte 数は 1 byte も
変わっていません。

## 現状と限界

- 生成される TypeScript は**型としては正しくありません**。`--no-check` で
  走らせていますし、Node の type stripping も型検査しません。ここで
  探しているのは emit と rename の正しさであって、型検査の正しさでは
  ありません。
- shape は 2 つ（`sink` / `export`）。export shape の観測は module の
  export 面を外から見るので、内側に観測を書く場合と違って名前が
  到達可能になりません。
- CI には**入れていません**。`#private` lowering が 300 seed 中 104 件を
  占めているので、今 gate にすると常に赤です。それを直せば、exit status
  がそのまま gate になります。
- shrink の受理条件は「同じ signature で失敗し続ける」です。signature は
  throw の name と正規化した message で、値の差はすべて `diff` に
  まとまります。別々の値バグが 1 つの family に見える可能性は残ります。
