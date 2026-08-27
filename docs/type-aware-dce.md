# 型がある状況の DCE: 実験プラン

このメモは「次に何を作るか」ではなく「**何を確かめるか**」を書いたものです。
各実験に仮説・測り方・成功条件・**撤退条件**を付けてあります。撤退条件が
無い項目は実験ではなく願望なので、書けなかったものは最後の
「まだ実験にできていないもの」に落としてあります。

出発点は
[`docs/type-aware-measurement.md`](./type-aware-measurement.md) の測定結果です。
9 target で **WIN 0 件**、残る差は noise floor 直上の 2 件。そして
その測定を作る過程で踏んだバグが、この plan の設計根拠になっています。

## 0. 反省: バグは 4 機構に還元できた

| # | 機構 | 実例 | 失敗の向き |
| --- | --- | --- | --- |
| A | **部分的な walker** — catch-all で subtree が消える | `TypeArgs` を剥がさない 19 file | 解析では fail-**open**（不健全）、rewriter では最適化漏れ。両方混ざると「宣言を消して参照を残す」 |
| B | **暗黙の universe** — contract は bundle 全体、渡すのは 1 module | class-method DCE の scope | 質問文が黙って書き換わる |
| C | **cost model / linearity の欠如** | predicate-inline（本体を撒く / 引数を複製） | サイズ増 + 副作用の重複実行 |
| D | **oracle が被検体で作られている** | 壊れた `unopt` が reference leg | 3 leg が一致しても正しくない |

共通点は「解析が正しいか」ではなく **「解析の前提が守られているか」の失敗**
です。前提はコード上どこにも書かれていませんでした。だから対策は pass ごとの
注意深さではなく、**機械が守れる不変条件**に落とします。

これは精度の話にも直結します。A も B も C も、**壊れる方向が
「削りすぎ」**でした。削りすぎを機械が捕まえられるようになるほど、
gate を緩めて精度を上げる余地が生まれます。順序は
**安全の自動化が先、精度の追求が後**です。

---

## Phase 1: 削りすぎを機械が捕まえる

### E1. 出力 verifier（自由変数）

**仮説**: `ReferenceError: X is not defined` の類は、bundle を実行せずに
出力の走査 1 回で検出できる。今回の A / B のバグは両方これで落ちた。

**根拠**: `symbol_graph.mbt:1388` の `sg_record_use` は解決できない名前を
`None => ()` で捨てています（コメント: "global / runtime built-in / typo.
Nothing to record"）。**typo をここで捨てているのが問題**で、捨てずに
集めれば verifier になります。globals 表は
`js_runtime_global_names()`（`bundle_link.mbt`）が既にあります。

**測り方**:
1. `SymbolGraph` に unresolved 参照を記録する
2. `verify_block(block, externals) -> Array[Violation]`:
   unresolved − globals − imports − externals
3. `--verify` flag と、`bundle_modules` の debug 経路で pass ごとに実行
4. **既存の全 fixture + type-aware corpus の 9 target に当てて、
   今日バグが出るかを見る**

**成功条件**: (a) 修正済みバグを再現させると検出する（`--treeshake` で
`CODES` を消す旧挙動を再現した最小例）、かつ (b) 現行 corpus で
false positive が 0。

**撤退条件**: false positive が構造的に消えない（globals の網羅が
終わらない / `with` や `eval` で scope が決まらない）場合。その場合は
「entry の module だけ」「minify 前だけ」に縮退させる。

**工数**: 半日。**この plan の中で唯一、他の全項目の前提になります**
（gate を緩める実験は、緩めた結果壊れたことを検出できないと走れない）。

#### 結果: 成功。半日で 4 件の実バグ

実装は `src/transform/verify.mbt` + `--verify` flag。`SymbolGraph` に
`unresolved` を持たせ、globals / import binding を引いて残りを報告します。

**corpus 9 target を 1 周した結果**（`--treeshake --fold --minify --mangle`）:

| target | 報告 | 判定 |
| --- | --- | --- |
| hono / valibot / typebox / neverthrow / ts-pattern / superstruct | なし | clean |
| excalidraw | `added` `removed` `updated` `appStateDelta` | **実バグ**（下記、修正済み）|
| excalidraw | `simplify` | **実バグ**（未修正。4 箇所から呼ばれる関数の宣言が無い）|
| excalidraw | `type` | 未再現。最小例では出ない → symbol graph の穴の可能性 |
| zod | `dO` `dP` `dQ` `dR` `dS` `dT` `dU` `dV` | **実バグ**（未修正。`processJSONSchema` 系 8 関数が宣言なしで呼ばれる）|
| immer | `aK` | **実バグ**（未修正。`let aL=(new az).produce, aM=aK.produceWithPatches.bind(aK), …` — multi-declarator の 1 個目だけ inline されて残り 13 参照が孤立）|
| immer | `ArchType` | 既知（module 跨ぎ `const enum`）|

false positive は 2 種類出て、両方 allowlist で消えました:

- `__ts_no_init__` — parser の「初期化子なし」sentinel。**出力には存在しない**
  のに、verifier が出力を**再 parse** するので再生成されて自由変数に見える
- `addEventListener` 等の web global — `js_runtime_global_names()` は
  linker の衝突回避用なので「読む名前」を網羅していない

**この 2 件は verifier の設計上の教訓**でもあります。再 parse は
「pipeline と bug を共有しない」ために選んだ方式で、その代償が
parser sentinel の再生成。globals 表の網羅がこの check の維持コストです。

#### 見つかった実バグ 1 件目（修正済み）: class method の分割代入引数

`TsClassMethodDecl.params` は `Array[(String, TsType)]` で、
**pattern を入れる場所がありません**。class lift はパターンを
「最初に束縛する名前」に潰していました。

```ts
class C {
  m({ a, b }) { return a + b }       // → m(a) { return a + b }     ReferenceError
  n({ a: { b } }) { return b }       // → n(b) { return b }         引数オブジェクトを返す
}
```

2 個目が怖い方です——**例外を投げず、間違った値を返す**。
`--bundle` だけ、最適化 flag なしで起きていて、164 case の
mangle-safety corpus と 2800 の unit test のどこにも
「分割代入引数を持つ class method」が無かったので誰も気付いていませんでした。
checker 側も同じ穴で、`m({ a: x })` の `x` に**パラメータ全体の型**が
付いていました（`x * 2` が「オブジェクトの乗算」になる）。

修正は境界での desugar です:

```
m({ a, b }, c) { … }   →   m(__pat0, c) { const { a, b } = __pat0; … }
```

AST を広げて emitter / mangler / param trimmer に「pattern が住む 2 つ目の
場所」を教える代わりに、失われる直前で普通の文に落とします。arity は
保存されるので `arguments` と `Function.length` は動きません。
`fixtures/mangle-safety/case42-method-destructuring` が 8 形を実行で
検査し（`arity` も pin）、`bundle_wbtest.mbt` が emit を pin します。

**未修正の 3 件（`simplify` / `dO..dV` / `aK`）は次の作業**です。どれも
「corpus が measured 判定を出していた target」に入っていました——
driver がその経路を通らなかっただけで、実行すれば throw します。

### E2. TDZ 順序チェック

**仮説**: typebox が `Cannot access 'IntegerKey' before initialization` で
落ちているのは linker の順序付けで、これも静的に検出できる。

**測り方**: top-level の `const` / `let` / `class` について、宣言より前の
statement から**同期的に**参照されていないかを見る（関数本体の中は除く
—— 呼ばれるのが後なら合法）。E1 と同じ walk に相乗り。

**成功条件**: typebox の現行 bundle で `IntegerKey` を指摘する。
そのまま `size-only` を外す修正に繋がる。

**撤退条件**: 「同期的に到達するか」の判定が call graph 依存になり、
false positive が実 corpus で 1 件でも出る場合 → 警告に降格。

**工数**: 1 日（E1 の後）。

### E3. erasure equivalence を correctness gate に昇格

**仮説**: 「TS を最適化した結果」と「型を消して最適化した結果」の挙動は
一致しなければならない。これは既に measurement harness としてやっていて、
**実際に `TypeArgs` バグを見つけた**。fixture 全体に広げれば
最も安い correctness harness になる。

**測り方**: `fixtures/mangle-safety` の 164 case それぞれで
`aware` / `blind` 2 leg を回して観測を比較。case ごとの追加コストは
1 compile + 1 run。

**成功条件**: 既存 164 case で不一致 0（= 今の実装が clean であることの
確認）。そのうえで `TypeArgs` の修正を revert すると落ちる。

**撤退条件**: 実行時間が CI で許容外（現状 mangle-safety が数分なので、
倍になっても許容範囲と見込んでいる）。

**工数**: 半日。harness は既にある。

### E4. 解析の monotonicity property test

**仮説**: B（scope バグ）は性質テストで機械的に落とせた。
**「module M の live set ⊆ M を含む bundle の live set」**。

**測り方**: 小さな 2 module program を生成し、
(1) module 単体で pass を走らせた結果と (2) bundle 全体で走らせた結果の
live set / accessed set を比較。既存の fuzzer の generator を使う。
同種の性質:

- 単調性: statement を足すと live set は縮まない
- scope 拡大性: 上記
- 順序不変性: pass の順を入れ替えても**挙動**は不変（サイズは可変）

**成功条件**: `class_method_dce_block` の `scope` 引数を外すと落ちる。

**撤退条件**: 性質が実装の内部表現に強く依存して、pass を触るたびに
テストを書き換えることになる場合。

**工数**: 2 日。

---

## Phase 2: バグ機構 A を構造的に閉じる

### E5. 型 wrapper を IR から消す

**仮説**: `As` / `Satisfies` / `NonNull` / `TypeArgs` は値の意味を持たない
ので、optimizer に届く前に剥がせば A は**表現不能**になる。
esbuild は parse 時点で型を落とす。

**測り方**: parse 直後（linker の前）に erase pass を 1 本入れ、
型情報は既にある side table（`combined_type_aliases` など）だけに残す。
そのうえで 19 file から `TypeArgs` の arm を消して**テストが落ちないこと**を
確認する（= arm が不要になったことの証明）。

**成功条件**: arm を全部消しても mangle-safety 164 / erasure equivalence /
corpus が全部通る。かつ出力が byte 一致（意味が変わっていない証明）。

**撤退条件**: checker が同じ AST を読んでいて剥がせない、または
`--dts` 経路が型を必要とする場合。→ E5' に縮退: erase はせず、
**catch-all を持つ解析関数のリストを固定して CI で増加を落とす** lint。
これは半日で、効果は「新規の穴を止める」だけ。

**工数**: 2〜3 日。

### E6. traversal を 1 本にする

**仮説**: 手書き walker が 19 個あるのが A の根本。oxc / SWC が visitor を
codegen しているのはこの理由。

**測り方**: `surface_visit_exprs_*` が既に完全な walker なので、
解析（collector 系）を全部これに callback で載せ替える。rewriter 系は
別途（戻り値があるので generic map が必要）。

**成功条件**: collector 系の catch-all が 0 になる。出力 byte 一致。

**撤退条件**: callback 化で 2 倍以上遅くなる場合（現状 parse が支配的なので
大丈夫と見込んでいるが、`bench-pipeline` で測る）。

**工数**: 1〜2 日。

---

## Phase 3: 精度 — ここからが「型で得する DCE」の本題

現状の 6 phase は全部**局所**の使い方（peephole に型を足したもの）です。
WIN 0 は驚くことではなく、**bundle のサイズを決めているのは到達可能性で、
局所の畳み込みではない**からです。

### E7. computed access gate の局所化（最優先の精度実験）

**仮説**: 測定で一番大きな失敗は「実 library で property mangler が
完全に不発」。原因は `obj[k]` 1 個で **bundle 全体**の gate が閉じること。
gate を **receiver 単位**に局所化すれば、実データで有意に開く。

**根拠**: excalidraw の `--explain-mangle` 出力がそのまま証拠です。

```
SUPPRESSED — a sink in the bundle can observe a member name…
  [x14] `points[i]`      [x7] `elements[index]`   [x4] `…[key]`
  [x3]  `updates[key]`   [x2] `Math[func]`
```

`Math[func]` 1 個が `LaserPointer` の method DCE を殺すのは設計として過剰。

**測り方**:
1. `--explain-mangle` の sink を receiver ごとに分類し、
   **「その receiver に到達しうる class / object 集合」**だけを免除する
2 `keyed_containers` / `numeric` の推論を型からも引く（`k: keyof T` なら
   key 集合は T の key、`Record<string, V>` なら member 名ではない）
3. corpus 9 target で「gate が開いた receiver の割合」と
   「aware leg の byte 差」を測る

**成功条件**: 少なくとも 1 target で property mangler が実際に発火し、
挙動が 3 leg 一致のまま byte が減る。**現状 0 なので、1 でも動けば前進**。

**撤退条件**: 局所化しても実 library では sink が全 receiver に散っていて
開かない場合。その時は「property mangler は library には効かない」を
結論として文書化し、`--closed-world`（E8）に賭ける。

**参考**: Sridharan et al., *Correlation Tracking for Points-To Analysis of
JavaScript* (ECOOP 2012) — `for (k in o) f(o[k])` の相関を追う手法。
`updates[key]` はまさにこの形。

**工数**: 3〜5 日。**測定 harness が既にあるので判定は早い**。

### E8. closed world を宣言物にする

**仮説**: 型駆動 DCE は必ず前提を置く。産業実装は前提を**一級市民**に
した（R8 / GraalVM の reflection config、Binaryen の `--closed-world`）。
宣言できれば gate を大きく開ける。

**測り方**:
- `--closed-world`: 「bundle の外から property を読む者はいない」を宣言。
  app 向け。excalidraw で byte 差を測る
- library 向けには **ABI を推論ではなく宣言に**。`.d.ts` を書いている
  library なら export 面は既に宣言済みなので、`export_surface` の推論を
  「宣言 + 検証」に変えられる（推論より狭くなるはず = 精度向上）
- **assumption ledger**: 型を根拠に消した箇所ごとに前提を記録し、
  `--assert-assumptions` で dev build に検査を挿す

**成功条件**: `--closed-world` で excalidraw / typebox の byte が有意に減り、
かつ 3 leg 一致が保たれる。ledger の検査を入れた build が現行 corpus で
1 件も throw しない（= 前提が実際に成立していることの確認）。

**撤退条件**: 宣言しても減らない（= 前提が bottleneck ではなかった）場合。
E7 の結果次第で不要になる可能性がある。

**参考**: [Binaryen GlobalTypeOptimization](https://github.com/WebAssembly/binaryen/blob/main/src/passes/GlobalTypeOptimization.cpp)
（GC type の field を「読まれないなら削る」→ vtable の `ref.func` が落ちる
→ devirtualize が進む）、[closed-world issue](https://github.com/WebAssembly/binaryen/issues/4462)、
[Closure の Type Based Property Renaming](https://github.com/google/closure-compiler/wiki/Type-Based-Property-Renaming)。
**TS の型は設計上 unsound**（`any` / cast / 宣言と実装の乖離）なので、
型を証明として使うなら検査を出荷するのが唯一誠実な形です。

### E9. RTA ベースの class 到達可能性

**仮説**: いまの class-method DCE は**名前ベース**（「bundle 内の誰かが
`m` と書いたか」）。型があるなら質問を変えられる:
**「この receiver はどの class になり得るか」**。`x: Shape` の `x.draw()` は
Shape の subtype の `draw` にしか到達しない。**computed key があっても
死なない** — key の話ではなく receiver の話だから。

**測り方**: RTA（Bacon & Sweeney, OOPSLA'96）から。
「bundle 内で `new` される class の集合」×「型で絞った receiver 候補」の交差。
excalidraw / superstruct（class が多い target）で byte 差を測る。

**TS 固有の注意**: structural typing なので subtype は宣言ではなく形。
CHA をそのまま持ってくると「構造的に代入可能な class 全部」になります。
現実的には nominal に近い部分（`class` を書いていて `extends` / `implements`
がある、branded）に限定し、それ以外は名前ベースに fallback。

**成功条件**: E7 の後で、`Math[func]` 級の sink があっても
class method が削れる。

**撤退条件**: 構造的部分型のせいで候補集合が縮まない（= 全 class が
候補になる）場合。TS で CHA が使えないという結論自体が finding。

**参考**: Dean/Grove/Chambers CHA (ECOOP'95)、Bacon & Sweeney RTA
(OOPSLA'96)、Tip & Palsberg XTA/CTA/MTA (OOPSLA 2000)。

**工数**: 5 日以上。E7 の結果を見てから。

---

## Phase 4: cost model（C の一般化）

### E10. 投機 + 巻き戻し

**仮説**: predicate-inline で分かったのは「述語 inline はそれ自体では
byte を減らさない」（`x === "a"` は `f(x)` より長い）。得になるのは
後段が畳めたときだけで、それは inline を決める時点では分からない。
→ **変換 → 局所 fold → 縮まなければ捨てる**。

**測り方**: `fold_expr` は同一 package にあるので局所適用できる。
predicate-inline の budget 2 をこれに置き換え、corpus で比較。

**成功条件**: budget 方式（typebox −261）より縮む。

**撤退条件**: 局所 fold では後段（`type-fold` / `tag-rewrite`）の寄与が
見えず、budget 方式と差が出ない場合。→ その事実を記録して e-graph（E11）
に判断を委ねる。

**工数**: 1〜2 日。

### E11. equality saturation（式レベル）

**仮説**: phase ordering に対する原理的な答え。全書き換え候補を e-graph に
入れ、byte cost で extract する。

**着手条件**: **E7 / E9 が終わってから**。今やっても、e-graph が選ぶべき
候補（型駆動の書き換え）がまだ少なく、測る対象がない。

**参考**: Tate et al., *Equality saturation* (POPL 2009)、Willsey et al.,
*egg* (POPL 2021)、Cranelift の aegraph mid-end。

---

## 検証側（D の反省）

| 項目 | 現状 | やること |
| --- | --- | --- |
| reference leg | mtsc 自身の `--bundle` | **別実装**（tsc / esbuild）に寄せる。mangle-safety には既に reference compiler leg があるので、type-aware corpus の `unopt` も同様にする |
| erasure equivalence | measurement のみ | E3 で correctness gate に昇格 |
| mutation self-check | mangle-safety にある | 効いている（case41 で「expectKeep が observable でない」と怒られた）。[intramorphic testing](https://arxiv.org/pdf/2210.11228) と同じ発想 |
| 出力の静的検査 | 無い | E1 / E2 |
| 性質テスト | 無い | E4 |

**D の教訓を 1 行で**: leg 間の一致は consistency であって correctness では
ない。基準を被検体で作ってはいけない。

---

## まだ実験にできていないもの

撤退条件が書けなかったので、この plan には入れていません。

- **effect 型 / `readonly` を DCE の根拠にする** — TS の `readonly` は
  compile-time のみで cast で破れるので、そのままでは根拠にならない。
  E8 の ledger + 実行時検査が入れば「hint として使って検査する」形に
  できるかもしれない
- **`sideEffects` / `@__PURE__` の生態系との整合** — 既に読んではいるが、
  実 library でどれだけ効いているかを測っていない
- **`--dts` 経路との共有** — 型を side table に寄せる（E5）と、
  宣言生成側と最適化側で同じ table を使えるはずだが、設計を見ていない

---

## 判定の順序

```
E1 (verifier)  ──┬─> E3 (erasure gate) ──┐
                 └─> E2 (TDZ)            ├─> E7 (gate 局所化) ─> E9 (RTA)
E4 (monotonicity) ──> E5/E6 (walker) ────┘         │
                                                   └─> E8 (closed world)
E10 (投機) ─────────────────────────────────────────> E11 (e-graph)
```

Phase 1 は**全部合わせて 2 日**で、今回のバグ 3 件のうち 2 件が機械検出に
なります。Phase 3 が本題ですが、Phase 1 無しで gate を緩めるのは
「壊れたことに気付けない状態で削りすぎに近づく」ことなので、順序は動かせません。

## E1 が開けた bug backlog

verifier が指摘してまだ直していないもの。どれも `mtsc --verify` で再現します。

| # | 症状 | 見立て |
| --- | --- | --- |
| B1 | excalidraw: `simplify(...)` が 4 箇所から呼ばれるのに宣言が無い | import か再 export の落ち。laser-pointer の `simplify.ts` 由来 |
| B2 | zod: `dO` 〜 `dV` の 8 関数が宣言なしで呼ばれる（`a._zod.processJSONSchema=(b,json,c)=>dO(a,b,json,c)`）| JSON-schema 系 1 module 分がまとめて消えている |
| B3 | immer: `let aL=(new az).produce, aM=aK.produceWithPatches.bind(aK), …` で `aK` が未宣言 | multi-declarator の 1 個目だけ inline され、同じ文の残り 13 参照が孤立。**single-use inliner の use 数え漏れ**が最有力 |
| B4 | excalidraw: `type` が未解決と報告される（`function dx(a){let type=a?.type; …}`）| 最小例で再現せず。`let type` が symbol graph に declare されない経路がある可能性。**graph の穴なら mangler / DCE も同じ穴を見ている** |

B3 と B4 は verifier の副産物として**解析側の穴**を示しているので、
Phase 2（walker / universe）の優先度に影響します。

## この plan 自体の失敗条件

E7 と E8 と E9 が全部撤退条件に当たった場合、結論は
**「TS の型は minify のサイズには効かない」**になります。その場合でも
測定で価値が出ているのは
「型で**安全に**削る」側（`observed_names` の `.name` reserve、
export-surface の ABI 推論、fail-closed な escape 判定）なので、
差別化をそこに置き直すことになります。**「他より小さい」ではなく
「同じ削除を、壊さない証拠付きでやる」**。それはそれで測れる主張です。
