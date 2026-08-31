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
| baseline == candidate | `lowering` —— 共有 pipeline が間違っていて、mangle は何も変えていない |
| どちらでもない | `both` |

## 3 本目の脚を、**一致したとき**にも使う

上の版にはまだ穴があり、そちらの方が大きかった。**baseline と
candidate が一致したら pass にしていた**のです。

```js
if (outcome.verdict === "equivalent") {
  summary.checked += 1;
  continue;              // ← reference に訊かない
}
```

2 つの mtsc 出力が一致することは**consistency であって correctness では
ない**。mangle より前に壊れている pass は両 leg で同じだけ壊れるので、
差が出ません。仮定の話ではなく、これが実際に起きていました:

```ts
const enum E { M = 3 }
function f() { const E = { M: 77 }; return E.M; }
```

`f()` は `--bundle` 単体で 3 を返します（正解は 77）。mangle しても
同じ 3 なので、**全 seed が "equivalent" と報告します**。この形の bug
は 5 つの pass にあり（[minify-patterns.md](./minify-patterns.md) の
表）、どれも数千 seed を通り抜けて、最後は pass の source を読んで
見つかりました。

いまは reference が**全プログラム**の oracle です。batch 単位で 1
child process にまとめてあり、`--no-reference` で切れます。

### leg が答えられていない数を報告する

答えない leg は、何も見つけない leg と見分けがつきません。それは
まさにこの leg が捕まえるための bug なので、ここで再現するのは
みっともない。要約行が参加率を出します:

```
80 compared, 0 skipped, 0 mismatch(es), … ; 80 checked against the original
```

最初に走らせたときは `68 checked against the original (12 unusable)`
で、理由は 1 つでした:

```
[no-oracle] 12x original threw SyntaxError: TypeScript enum is not supported in strip-only mode
```

Node の type stripping は既定が strip-only mode で、`enum` を拒否します。
つまり **`const enum` ——「最適化 flag 無しで壊れる」唯一の形、いちばん
見張る価値のある形 —— だけが裁定できていなかった**。
`--experimental-transform-types` に切り替えて 80/80 になりました。実装は
Node のものなので leg の独立性は変わりません。

同じ穴が corpus harness にもありました。`case43-table-shadowing` は
「5 pass を独立 reference と比べる」case として足したのに、`const enum`
のせいで reference が `unavailable` になり、自分の 2 出力を比べる形に
落ちていました。`pass` と表示され、note に unavailable と書いてある
状態です。

### 検出力を測る

「leg を足した」と「leg が働く」は別です。narrowing の修正を 1 行
戻して、campaign が捕まえるかを確認しました。

| 戻した pass | 結果 |
| --- | --- |
| `as_const_inline` | seed 14 で `lowering`、214 → **2 node** に縮小 |
| `const_enum_inline` | seed 11 で `lowering`、`s1Shadowed()` が 3、正解 77 |

artifact は手で書いた case43 とほぼ同じものが、seed から自動で出てきます:

```ts
const s0K = 5;
function s0Shadowed() {
  const s0K = 9;
  return s0K * 2;
}
function s0Direct() { return s0K * 2; }
console.log([s0Shadowed()]);
```

1 回目の測定では shrink が `214 -> 214 nodes (0 accepted)` でした。
shrinker の oracle は `attribute()` の `kind` が一致することを要求し、
`attribute()` はこの形を `both` に分類していたためです（reference が
baseline とも candidate とも違う）。`baseline == candidate` なら
`lowering` ——「rename ではなく共有 pipeline」——と分類するようにして、
2 node まで落ちました。**分類が粗いと縮小が止まる**、という繋がりは
事前には見えていませんでした。

## 名前解決を狙う文法

generator は property mangler の証明義務に向いていて、名前解決には
向いていませんでした。名前は `freshVar()` が `v0`, `v1`, … と一意に
配るので、**入れ子 scope で同じ名前が 2 回束縛されることが一度も
ありません**。上の 5 pass に届く形も 1 つもありませんでした。

`shadowGroup` が 6 形（`as const` の array / object、scalar `const`、
`const enum`、型 guard、literal-union dispatcher）を出し、それぞれに:

- pass が書き換えたい外側の宣言
- `shadowed` —— 名前を再束縛する scope からの read。**内側**を読まな
  ければならない
- `direct` —— shadow しない read。**今も最適化されなければならない**
  （でないと「table を narrow する」と「pass を止める」が外から
  区別できません）

shadow の形は 4 通りを回します: 内側 `const`、**parameter**（block が
宣言しないので block 単位の検査では見えない）、`catch` binding、loop
変数。

読み手は observe / export に入れます。入れないと dead code になって
treeshake が消し、間違って書き換えるはずの pass に機会が来ません。

6 形は verbatim text の `raw` node で出しています。printer に 6 個の
arm を足しても得るものが無い（欲しいのは固定の形と fresh な名前だけ）
一方で、shrinker が raw node の**内側**を縮小できないという代償が
あります。だから形ごとに別の raw decl にしてあり、6 個のうち 5 個を
落として問題の 1 個だけ残す縮小はできます。

## 新しい oracle が実際に見つけたもの

seed 0..399 を回して **4 件**。どれも `lowering`（共有 pipeline 側）で、
mangle は無関係です。2 件を追いました。

### 1. `delete obj['q']` が `delete 1` になる

artifact（自動縮小、15 node）:

```ts
const obj: Record<string, number> = { p: 0, q: 1 };
delete obj['q'];
export const viaIndex = obj['q'];
export const viaDot = obj.q;
```

正解は `undefined undefined`、`--bundle --fold` の出力は `1 1`。
配列でも同じで `delete arr2[1]` が `delete 20` になります。

`as_const_inline` の disqualification scan には
`UnaryOp(_, inner) => scan_expr_for_unsafe_uses(inner, …)` という
汎用 arm があり、`delete obj['q']` の operand に降りると
`IndexAccess(Var(obj), StringLit("q"))` を**安全な keyed read**として
読みます。だから candidate は生き残り、read は古い値に畳まれ、
**delete 自身も literal に書き換えられて no-op になる**。

`delete` の operand は read ではなく mutation です。assignment の
receiver と同じく `flag_all_candidate_refs` で潰し、rewriter 側でも
`delete` の operand には触らないようにしました（同じ扉の 2 つ目の鍵。
失敗の形が crash ではなく「黙って実行されない mutation」なので）。

### 2. 値が分かっている条件が、実行ごと捨てられる

fuzzer の報告は trace 1 個の差でしたが、掘ると **7 箇所**ありました。

`is_js_truthy` / `is_js_falsy` は「boolean 文脈で何に coerce するか」
に答えます。呼び出し側はそれを「**捨てて良い**」として使っていました。
この 2 つが食い違う形がちょうど 2 つあり、どちらも実在します:

- object / array literal は**中身が何であれ**truthy。中身は実行される。
  `{ g: f() } ? a : b` は `f` を呼ぶ。
- `void EXPR` は `EXPR` が何であれ falsy。`void f() || a` は `f` を呼ぶ。

8 つの site を並べたプログラムで、**8 個の効果のうち 7 個が消えました**
（`--bundle --fold`、mangle 無し）。

```
truth              [1,2,3,4,5,6,7,70,8]
--bundle --fold    [7,70]
```

生き残った 1 つが `if` 文です。そして `fold_stmt_into` の `If` arm には
**すでにこの guard が入っていて、コメントに「fuzzer の効果トレースが
見つけた」と書いてありました**。同じ規則が必要な 6 箇所——ternary、
`!`、`&&`、`||`、`while` / `do…while` / `for` の dead-loop 削除、
`Boolean(…)`——には入っていなかった。この repo で**7 回目**の
「同じ規則を複数箇所に書いて、1 箇所だけ直した」です。

`keep_effects(original, value)` を 1 つ書いて全 site から呼ぶ形に
しました。`do…while` は条件が body の**後**に走るので、効果の位置も
そこに合わせています。

corpus case にはできませんでした。**mtsc の checker 自身が、condition
/ logical operand / unary 位置の literal を拒否します**（"this kind of
expression is always truthy"）。つまりこの bug は型検査を切った入力
——published `.js`、`verify-real-world-minify` が使う経路——でしか
届きません。regression test は `fold_wbtest.mbt` に置き、「純粋な条件は
今も畳まれる」対を必ず付けてあります（でないと修正が「fold を止める」
形になっていないか分かりません）。

## seed 600..3999 —— 6010 comparison、8 family

前節の修正を入れてから 3400 seed 回して 16 mismatch / 8 family。
うち 4 件を追い、3 件を直しました。

### 3. `'alpha' & -1` が `'alpha'` に畳まれる（16 node）

```ts
switch (('alpha' & -1)) {
case 0: break;
default: (arr[0] ||= `k${(trace.push(2), false)}`);
}
```

`'alpha' & -1` は `0` なので `case 0`。`x & -1 → x` が発火して scrutinee
が `"alpha"` になり `default` が走りました。bitwise の identity /
annihilator **6 rule**が同じ読み違いを共有していて、この harness には
bitwise の case が 1 件もなかった。詳細は
[`rule-equivalence.md`](./rule-equivalence.md) の「4 周目」。

### 4. 代入で入った object の key が消える（9 node）

```ts
let brake2 = 4;
while (--brake2 > 0 && ((bag.beta &&= { ...obj, g14: a }))) { }
console.log([bag, obj]);
```

`--mangle-properties` 側で `g14` が消え、`obj` の `p`/`q`/`r` も落ちる。
`--explain-mangle` が答えを一行で出しました:「reaches a side-effect
sink」が**空**。escape 解析が何も予約していない。

JS には代入が 6 通りあり、**member expression を経由する 4 つだけ**が
`sg_record_write_into` を呼んでいました:

| 形 | 記録していたか |
|---|---|
| `IndexAssign` / `PropAssign`（文） | ✅ |
| `IndexAssignExpr` / `PropAssignExpr` | ✅ |
| `Assign` / `AssignExpr`（`v = …`） | ❌ flow edge だけ、written value なし |
| `CompoundAssign*`（`v \|\|= …`, `bag.beta &&= …`） | ❌ 何もなし |

なので

```ts
let v: any = 1;
v = { ...obj, g14: 100 };
console.log([v]);
```

は `g14` も `obj` の `p` も落とし、**同じプログラムを
`bag.beta = { ...obj, g14: 100 }` と書けば両方残る**。escape の判断が
違ったのではなく、文が walker のどの arm に落ちたかが違っただけです。

`sg_record_written_value(w, id, val)` を切り出して 4 つの arm 全部から
呼びます。`v += …` は値が算術結果なので key を記録する必要はありませんが、
**演算子ごとに要否を判断したのがこの arm が何も記録しない状態の入口**
なので、compound は一律に記録して over-reserve 側に倒しました。
「escape したから予約する」であって「質問を諦めたから予約する」では
ないことを、sink に届かない対の case で固定しています。

### 5. `a < (b > (c))` が parse error（parser）

3 seed が `ParseError("Expected RParen, got RParen")` で compile 不能。
message 自体が意味を成していないのが手がかりでした。

`try_skip_type_args` は `<`…`>` の均衡を見ながら、型が含みうる
brace / paren / bracket を数えています。「均衡」の**半分しか**見て
いませんでした——開いていない closer で abort する guard はあるのに、
`depth` が 0 になった時点で**その 3 つの count が 0 である要求がない**。
だから `a < (b > (c))` は `< ( b >` まで食って `parens == 1` で停止し、
呼び出し側は続く `(` を見て `a<(b>(c)` を generic call として commit し、
`)` が余りました。`[` と `{` にも同じ形があります
(`a < [b > (c)]`, `a < {b: (c > (d))}`)。

### 6. `return void f()` が call ごと消える（33 node）

```ts
function f0(p0, p1) {
  if (--callBudget < 0) return 0;
  trace.push(1);
  return (void f0(a, z));
}
```

`f0` の body が `if(--callBudget<0)return 0;trace.push(1)` になり、
**再帰呼び出しが消えて** `f0` の tree-shake まで走りました。budget が
減らないので全ての呼び出しが `undefined` を返し、原文が最終的に返す `0`
にならない。

「値が分かっている条件が実行ごと捨てられる」（前節 2）と**同じ規則の
8 番目と 9 番目の site**です。`void EXPR` は `EXPR` が何であれ
`undefined`——そして `EXPR` は走る。`fold.mbt` の `Return` arm と
`peephole.mbt` の `Return` arm、両方に同じ形で入っていました。

`fold.mbt` は statement 列を作れるので `EXPR; return;` に割り、trailing
の bare return が剥がれて **`return void f()` より短くなります**。
`peep_stmt` は 1 文しか返せないので、そこでは fold しないだけです。

### 7. `arr[0] += 1` が `arr[0]++` になる（29 node）

```ts
while (--brake1 > 0 && (((arr[0] += 1) ? (b ^ arr[2]) : (trace.push(4), 10))))
```

`arr[0]` は 0 から始まるので `arr[0] += 1` は **1**（truthy）で第 1 枝。
出力の `arr[0]++` は **0**（falsy）なので `trace.push(4)` が走りました。

`x += 1` は**新しい値**に評価され、`x++` は**古い値**に評価される。
`peep_expr` の 4 site が post-fix を作っていました。`++x` と `x++` は
同じ 3 byte なので、これは trade-off ではなく単に演算子の間違いで、
それが 4 箇所に書かれていた。`compound_step_value` 1 つに集約し、
statement 位置（値が捨てられ、`x++` が JS の慣習）への戻しは
`peep_stmt` の `Expr` arm 1 箇所に置きました。

### 8. `switch` の scrutinee が case ごとに再評価される（21 node）

```ts
switch ((trace.push(2), obj?.['gamma'])) {
case 0: return (a |= obj?.['gamma']);
case 1: return (y--);
default: ;
}
```

全 case が terminator で終わる switch は if-else chain に落とします。
chain は scrutinee を **named case ごとに 1 回**評価するのに対し、
switch は 1 回だけ。`trace.push(2)` が 2 回走りました。

`is_pure_value(scrutinee)` を要求します（named case が 1 つなら
1 回しか書かないので不要）。同じ議論が「読むたびに値が変わりうる式」にも
効きます。single-case の 2 つの arm は `ep` を 1 回しか書かないので
gate は要りません。

### 9. class の source text を observe していた（harness 側）

`bag.gamma += C1` が `class C1 { c1f0 = true; }` を含む文字列を作り、
minify が正当に整形を変えるので mismatch になっていました。
`encode` は関数の source を**わざと記録しない**のに、`+=` が走った後は
ただの文字列で observer には区別できない。generator 側で、member の
無い class receiver は **bare constructor ではなく instance** を返す
ようにしました（instance は `[object Object]` に coerce され安定）。
class の値は `new C()` と `export` shape 経由で今も sink に届きます。

### 10. `[no-oracle] Rest parameter must be last formal parameter`

23 / 6019 seed が oracle を失っていた理由。**generator の不備ではなく
Node の bug** でした。

```ts
const obj: Record<string, number> = { p: 1 };
let a = 5;
(({ ...obj, g: 1 } ? 1 : 2), (a--));
```

Node v22.22.2 の `--experimental-transform-types` はこれを

```js
{ ...obj, g: 1 } ? 1 : 2, a--;
```

に変換します。**paren が落ちて `{` が文頭に来る**ので block として
読まれ、中の `...obj` が module wrapper の rest parameter と解釈されて
`SyntaxError: Rest parameter must be last formal parameter`。原文は
完全に正当で、mtsc は正しく compile します。message が構文と全く
関係ないので、generator の不備に見えます（実際そう記録していました）。

printer 側で、`(` を剥がした先頭が `{` になる expression statement には
`void` を付けます。`0,` では**駄目**でした——SWC は捨てられる comma の
定数第 1 引数を落として `{` を先頭に戻します。`void` は捨てられる
operand ではなく unary operator なので残り、値が捨てられる
expression statement では意味を変えません。3 本の leg は同じ source を
走り続けます。

### 11. class の method が消える（37 node）

```ts
class C { m() {} }
console.log(new C());
```

`mtsc --bundle` だけで `m` が削除されます。`class_method_dce` の `keep`
は export surface だけで、**class の値が bundle 境界を越えたという概念が
なかった**——library bundle の話しかしていないので、application bundle
には保護が一切ありません。実コードでの形は `JSON.stringify` が `toJSON`
を呼び、`String(x)` が `toString` を、`await` が `then` を呼ぶという、
**library 自身は決して呼ばない protocol method** です。

#### 最初の試みと、なぜ revert したか

`collect_externally_visible_props` をそのまま食わせたら **dce-coverage が
3 件退行**しました。あの集合は property mangler の質問——「この *名前* を
rename して良いか」——に答えるもので、正しく広い: rename は名前が現れる
全箇所で一貫していなければならないので、escape する式の部分木に instance
が現れただけで class を observed と見なします。**削除はより強い主張**で、
より狭い事実を必要とします。`console.log(new C().live())` で全部予約され、
pass は名前だけ残って何もしなくなりました。

#### 正しい gate

`External` observability **だけ**で pin します。`External` は「値が bundle
を出た、または semantics が列挙できない sink に届いた」という水準で、
それ未満は全部**既知の** sink——そして既知の sink は任意の method を
呼びません。加えて、既知 sink が実際に呼ぶ protocol method
(`toJSON` / `toString` / `valueOf` / `then`) は固定リストで持ちます
(`sink_invoked_protocol_methods`)。

`class_members_reachable_off_bundle` が両者を合わせた答えを返し、
`class_method_dce_block` は `off_bundle` を**デフォルトなしで**取ります。
`scope` parameter が「無害に見えるデフォルト」の代償を示した通りなので、
答えを用意できない caller は「黙って到達可能な method を消す」のではなく
「何もしない」に落ちます。

#### 途中で見つかった 2 つ

**(a) `new C()` が class に繋がっていなかった。**
`collect_immediate_sources` の `New` arm が `Unknown` を返していたので、

```ts
const w = new Widget();
register(w);          // register は外部 import
```

の backward propagation は `w` で止まり `Widget` に届きませんでした。
一方 `register(new Widget())` は**届く**——sink seeder が式自身を歩くので。
**同じプログラムの 2 つの綴りで答えが違い、負ける方が実コードの書き方**
です。instance の identity は class から来るので、`New` は
`SymVal(class)` を source にします。

**(b) `analyze_observability` が quadratic だった。**
worklist が pop するたびに **flow_edges 全体を走査**していました
(O(symbols × edges))。`FuncArg` 向けの逆引き index は既にあったのに
`SymVal` 向けが無い。9 MB の TypeScript bundle で
`mtsc --bundle --mangle` の **43.8s のうち 40s** がここでした。
`--mangle-properties` しか consumer が無く、その規模の target で
それを有効にする harness が無かったので見えていなかった。
`class_method_dce` が全 bundle で同じ質問をするようになって表に出ました。

| | before | after |
| --- | --- | --- |
| `--bundle --mangle` | 43.8 s | **4.7 s** |
| `+ --mangle-properties` | 85.3 s | **7.0 s** |

出力は byte 単位で同一、type-aware corpus も 10 target 全て不変です。

#### fuzzer 側: sink での prototype reflection

seed 1261 自身は **false positive** でした。`console.log`、`util.inspect`、
`JSON.stringify`、`String(x)`、`Object.keys` の**どれも prototype method
の存在を観測できません**——`C {}` と出るだけです。observer の
`functionMembers` / `protoMembers` は、プログラム自身の sink が届かない
ところまで手を伸ばしていました。

なので sink shape の観測では prototype を reflect しません。export shape
では**そのまま**です: library bundle の consumer は本当に任意の method を
呼べるので、そこでは正しい観測です。

そして sink shape が到達できない**本当の危険**——bundle が見えない callee
に class を渡す形——は corpus に置きました
(`fixtures/mangle-safety/case45-class-escapes-external`)。実際の external
import が instance を受け取って method を呼び返し、Node で走ります。
kept な名前は全て、同じ class か同じ sink 経由の dropped な名前と対に
してあるので、修正が「pass を止める」形になっていないことが分かります。

## generator が届いていなかった位置

`is_pure_value` を読んでいて見つけた bug——property read を pure と
答えていた——を、この campaign は **8000 comparison で 1 件も報告して
いませんでした**。generator は getter を 30% の確率で出していたのに。

理由が 2 つあり、どちらも「文法にあるつもりだった形が実は無かった」です。

**(a) receiver が `new C()` だった。** getter read は `expr()` の case 16
から出ていて、そこは `new C().g` を組み立てます。ところが
`is_pure_value(New(...))` は **false** なので、read は receiver 経由で
impure と判定され、**この bug の影響を受けません**。影響を受けるのは
receiver が pure な形——ただの変数——で、それは実コードが getter を読む
書き方でもあります。class ごとに `const c0Inst = new C0();` を出して、
そこから読むようにしました。

**(b) 値が捨てられる位置に無かった。** `expr(3)` が bare member read で
底を打つことはほぼありません——binary op / assignment / call に包まれ、
どれも**値を使う**ので read は生き残ります。捨てられる位置を直接出す
`discardedReadStmt()` を足しました: 裸の statement、`void EXPR`、
捨てられる comma の左、`.length` を取る array literal——4 つの誤っていた
綴りそのものです。

検出力を測りました。修正を戻した状態で:

| generator | 結果 |
| --- | --- |
| 元のまま | 300 seed / 600 comparison で **0 件** |
| getter が常に自己申告 | やはり **0 件** |
| + binding から読む / 捨てられる位置 | **209 comparison で 21 件**、最初は seed 7 |

「harness に case を足した」と「harness が検出できる」は別、という
[rule-equivalence](./rule-equivalence.md) と同じ教訓が、generator 側にも
ありました。

## 文法に無かった 3 つ: inheritance / generator / async

generator が一度も出していなかった構文を 3 つ選んで、まず**手で**探りました。

### inheritance —— 17 probe で異常なし

`class_method_dce` の narrowing、`observed_names` の階層 narrowing、
private field remap の 3 つが class 階層を読むのに、generator は
`extends` を一度も出していませんでした。

`--mangle --mangle-properties` 込みで 17 通り試して**すべて一致**:
override の dispatch、`super.m()`、3 段の chain、getter override、
継承 field の `JSON.stringify` / `Object.keys`、static 継承、
module を跨いだ `extends`、`instanceof`、`this.constructor.name`。

1 件だけ差が出たのは `console.log(new Sub())` が `b {}` と出る件ですが、
これは**仕様通り**です。`observed_names.mbt` の contract は「source に
書かれた `.name` read を予約する」で、`console.log` が constructor 名を
出すのは `util.inspect` の挙動であって source read ではありません。
`fuzz-runner.mjs` の `encode` が `name` を除外しているのも同じ理由です。

健全だと分かった上で、**保ち続けるために** generator に入れました:
40% の確率で既存 class を継承し、60% の確率で継承 method を override
して `super.<name>()` を呼ぶ。継承 member は `instanceMembers` に
引き継ぐので、subclass の instance から読めます。200 seed 中 24 が
`extends`、11 が `super` を含み、800 comparison で mismatch 0。

### generator —— `next` が消えていた

こちらは**当たり**でした。

```ts
class Range {
  [Symbol.iterator]() { return this; }
  next() { … }
}
console.log([...new Range()]);
```

`next` が削除され、spread が
`is not a function or its return value is not iterable` で throw。

`implicitly_invoked_protocol_methods`（前節で作った list）は
`toJSON` / `toString` / `valueOf` / `then` の 4 つで止まっていて、
**その list 自身のコメントが**「spread は `Symbol.iterator` を呼ぶが
それは computed key なのでこの pass は落とせない」と書いていました。
その 1 歩先——`Symbol.iterator` が返す object の **`next`** は
ただの識別子で、落とせるし落とした——を書いていなかった。

しかも `mangle.mbt` の `mangler_builtin_reserved_properties` には
`// Iterator protocol` として `next` / `return` / `throw` / `done` /
`value` が**最初から入っていました**。つまり rename は最初から安全で、
**削除だけが**危険だった——`class_method_dce` が別の集合を読むからです。
2 つの list が drift しないよう、unit test で包含関係を検査します。

`for…of` が早期離脱で呼ぶ `return`、`yield*` が呼ぶ `throw` も
同時に入れました。

generator 側にも入れました: 45% の確率で `function* genN()` と
hand-rolled iterator class を出し、`[...genN()]` / `[...new genNIter()]`
を observation に加えます。修正を戻すと **64 comparison 中 16 件**が
`[BROKEN BASELINE] original ran; our bundle threw: genNIter is not a
function` として報告されます。

### async —— 意図的に入れていない

observation は同期です。`async` 関数の効果は observation の**後**に
落ちるので、両 leg が同じ空 trace で一致してしまう——coverage の形を
した何も証明しない case です。`await` の順序を観測するには runner を
変える必要があり、generator の仕事ではありません。手で 8 通り
（`await` 順序、捨てられる `await`、thenable の `then`、`for await`、
`try/finally` を跨ぐ `await`、async method の mangle）試して全部一致
することは確認済みです。

## 修正後の全域 sweep

seed 0..3999、両 shape、**8000 comparison**:

```
8000 compared, 0 skipped, 6 mismatch(es), 0 broken baseline(s),
0 did not compile; 7966 checked against the original

distinct failure families, most frequent first:
     6x  lowering first at seed 1261 (sink)  lowering:diff:0:-cNmN
```

16 mismatch / 8 family から **6 mismatch / 1 family** へ。残る 1 family は
上の「追えたが直さなかったもの」——`class_method_dce` の穴だけです。

`did not compile` が **0** になりました（parser の 3 seed が解消）。
この run は printer の `void` 修正より前に起動しているので
`34 unusable` が残っていますが、同じ seed 0..699 を修正後に回すと
`1400 compared … 1400 checked against the original`——unusable は 0 です。

## それ以前に見つかっていたもの

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

## 効果トレースを oracle に入れる

最初の版は**観測した値**だけを比べていました。値を誰も読まない呼び出し
の消失は、それでは原理的に見えません。そして minify した TypeScript
compiler を殺したのは、まさにその形でした——node に symbol を付ける
だけの呼び出しが、たまたま false になる条件の下に移されて実行されなく
なった。値の比較は一致します。module が symbol を持たなくなるだけです。

なので**生成した callable は自分の呼び出しを申告します**。

```ts
function f0(p0, p1) {
  if (--callBudget < 0) return 0;
  trace.push(2);          // これ
  ...
}
```

`trace` は観測列に入っているので、呼び出しの消失・重複・並び替えが値と
無関係に差分になります。ただし `trace.push` を入れると関数が pure でなく
なり DCE が絶対に消せなくなるので、**申告するのは 7 割だけ**にして
「消せる関数」の経路も残しています。

同時に、壊れた形そのものを生成するようにしました。

```ts
let v = f0(a, b);                        // 副作用のある呼び出し
obj.p = (c > 137) ? v : 0;               // 唯一の use が条件下
```

3 通りの guard（ternary の branch、`&&` の右、`if` の body）を作ります。
条件は prelude の可変カウンタから組み立てるので folder が畳めず、かつ
たいてい false になるように書いてあります——常に通る guard は何も証明
しません。

## family の signature が粗すぎた

もう 1 つ、harness 自身の欠陥です。値差分の signature が
`${kind}:diff` で**すべての値差分が 1 family に潰れていました**。
最初に見つかった差分が family を占有し、以降の差分——別の pass の別の
bug——は重複として捨てられます。既知の未修正 finding（`#private` の
lowering）が seed 2 で出るので、実質的に**campaign は 2 seed で終わって
いました**。

signature に「どの観測が、どの token で」違うかを入れ、既知 finding は
報告するが `--keep-going` の予算を消費しないようにしました。結果、
比較数が 2 → 236 に増え、その場で 2 件の実バグが出ました。

| 見つかったもの | 何 |
| --- | --- |
| `+++a` を出力 | `+(++a)` を密着させると `++ (+a)` と読まれて SyntaxError。binary 側（`"" + +x`）には guard があり unary 側には無かった |
| 宣言を消して呼び出しを残す | single-use inliner が `Block` と `switch` の case body に substitute の arm を持たず、`ReferenceError: f0 is not defined` |

2 件目は `try` で 1 度直したのと同型（walker が 2 つあって片方が知らない）
なので、**族ごと閉じました**: 置換後に参照が残っていたら inline を諦めて
宣言を保持します。今後 arm が足りなくても、miscompile ではなく最適化の
取りこぼしになります。

## 効果トレースが見つけたもの

trace を oracle に入れて campaign が seed 2 で止まらなくなった直後に、
既知 2 件とは別に 4 件出ました。

| 見つかったもの | 何 |
| --- | --- |
| `+++a` を出力 | `+(++a)` を密着させると `++ (+a)` と読まれて SyntaxError |
| 宣言を消して呼び出しを残す | single-use inliner の `substitute_stmt` に `Block` / `switch` case body の arm が無い |
| 条件の副作用を捨てる | `if ({ ...bag, g: f() }) {}` — object literal は中身に関係なく truthy だが**中身は評価される**。`f()` が消えた。値比較では絶対に見えない（object を誰も読まない） |
| 戻り値の literal キーが消える | `return { ...obj, g10: v }` の `g10` は bundle の他のどこにも名前が無いので、関数の戻り値が観測されていても誰も生かせなかった |

最後の 2 件は**どちらも trace が無ければ出ません**。前者は呼び出しの
消失そのもの、後者は「観測された値の中身」で、値の一致だけを見る oracle
は通してしまいます。

200 seed / 400 比較で mismatch 0、既知 finding も 0 になりました。

## property 書き込みの 4 つの綴り: 生成器が届いていなかった場所

#73 で見つけた export surface の 4 つの穴は `mtsc --bundle`（最適化
flag 無し）に入っていて、**数千 seed の campaign が 1 つも見つけて
いませんでした**。文法が届いていなかった理由は 3 つです。

* `mutableTarget()` に `this.<field>` の arm が無い。つまり class の
  field への compound write —— `this.slot ??= new Payload()`、hono の
  実物の `#req ??=` の綴りで、実コードが lazy member を書く形 ——
  は**生成不可能**でした。
* index の arm は `arr` を数値 literal で引くだけで、`obj["p"]` は
  一度も出ません。
* class の instance が、**観測される holder の property に書き込まれる**
  ことが無い。だから export surface の経路自体が通りませんでした。

`lazyHolderGroup` は「consumer への唯一の経路が 1 回の property write」
である payload class を出し、綴りを 5 つ回します:

| 綴り | 600 export seed 中 |
| --- | --- |
| `this.slot ??= new P()` | 125 |
| `this.slot \|\|= new P()` | 110 |
| `this["slot"] = new P()` | 126 |
| `bag.slot = new P()` して読み返す | 100 |
| `this.slot = new P()`（control） | 102 |

control を入れているのは、それが無いと「修正が効いている」と
「pass が切れている」が外から同じに見えるからです。read-through 形には
**自己参照の increment** も入れてあります——key を書く write がその key を
READ する形で、修正後の walk が停止しなくなった原因そのものです。

### runner は変えていない

`encode` は export された instance の own enumerable field を辿り、
内側の object の prototype member を報告します。だから **holder を
export するだけ**で、payload の method が消えたことが差として出ます。
payload class は**意図的に export しません**——export したら member が
直接 surface に乗り、write が唯一の経路でなくなります（`case60` の
draft 2 で実際にやった間違いです）。

検出は **reference leg** から来ます。この削除は mtsc の全 leg で起きる
ので mangled と unmangled は一致します——この repo が何度も記録している
self-comparison の罠です。

### 検出力の確認（これが本題）

生成器に形を足しただけでは何も言えません。getter の回が
「600 比較で 0 件 → 209 比較で 21 件」になったのは綴りが正しくなった
後で、それまでは形があっても届いていませんでした。なので**修正を
revert した compiler に対して campaign を回します**:

```
[LOWERING BUG (unmangled side is wrong)] seed 0 (export)
    shrunk 107 -> 6 nodes in 154 probes
    original  ["slot",["object",1,[["tag","lz0"]],["lz0Read"]]]
    our bundle["slot",["object",1,[["tag","lz0"]],[]          ]]
```

**seed 0**、つまり最初の 1 つで出ました。107 node が 6 node に縮み、
しかも lowering bug（unmangled 側が間違い）として正しく分類されて
います——削除は `--bundle` 自体で起きるので、mangling bug ではありません。

修正入りの compiler では **700 seed / 700 比較で mismatch 0**、
700 件すべてが original と照合済みです。

### 入れていない綴り

`#private` field は**生成しません**。`Object.keys` は private field を
見られないので、compiler が何をしようとこの観測では届きません。
`fixtures/mangle-safety/case61-private-field-value-escape` が担当します。
ここで「covered」と書くのは coverage-shaped です。
