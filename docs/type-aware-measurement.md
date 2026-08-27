# 型情報は何バイト効いているのか

`--mangle-properties` の安全性は 4 つの harness で検査してあります。
効果を測ったものは一つもありませんでした。「type-aware minify」を名乗る
以上、**型を知っていることが実際に何バイトになるのか**は測れる質問です。

```sh
node scripts/measure_type_aware.mjs
node scripts/measure_type_aware.mjs --only hono --verbose
node scripts/measure_type_aware.mjs --update      # expected.json を再記録
```

## なぜ公開版の .js では測れないか

型を読んでいる phase は `src/transform/bundle.mbt` に 6 つあります。

| phase | 読んでいるもの |
| --- | --- |
| `predicate-inline` | `x is T` の型述語 |
| `switch-fold` | 閉じた string literal union の param 型 |
| `as-const-inline` | `as const` |
| `tag-rewrite` | discriminated union（`combined_type_aliases`）|
| `class-method-dce` | `combined_class_fields` + `combined_type_aliases` |
| `type-fold` | primitive の型注釈 |

これらが読む `combined_type_aliases` / `combined_interfaces` /
`combined_class_fields` は、**parse した TypeScript module** から
bundler が詰めています。公開済みの `.js` を渡すと 3 つとも空のままで、
6 つのうち 1 つも発火できません。つまり `verify-real-world` が
`typescript.js` や `react` で測っているものは、定義上ゼロです。

だから corpus は git から**ソースを clone** します。

## 測り方

同じ flag で 2 回最適化し、**入力の形だけ**を変えます。

| leg | 何 |
| --- | --- |
| `unopt` | `mtsc <entry.ts> --bundle` — TS in / plain JS out、最適化なし。サイズの分母かつ挙動の基準 |
| `aware` | `mtsc <entry.ts> --bundle --treeshake --fold --minify --mangle` — 注釈があるので 6 phase が発火できる |
| `blind` | `mtsc <unopt.mjs> --bundle …同じ flag` — 型を消した同じコード。型 table は全部空。これが公開 `.js` の状況 |

`delta = blind - aware`。正なら型情報が効いています。

`--no-check` は全 leg で有効です。これは**診断だけ**を飛ばします——実際の
library は subset checker を通りませんし、6 phase が読む型 table は check
ではなく parse から来るので、leg の差は入力の形だけになります。

### 引かないといけない分

`blind` の入力は一度 emit を通っているので、`blind` は `aware` にはない
**2 回目の最適化**を受けています。2 回目は 1 回目の取りこぼしを拾うので、
これは型とは無関係な下駄です。`aware2` leg が `aware` 自身の出力を
再最適化してその分を値付けし、`--verbose` が両方を出します。

### 信用の条件

3 つの leg が driver に対して**同一の観測**を出すことが条件です
（`fixtures/type-aware-corpus/*.driver.mjs`）。bundle がそもそも動かない
target は `size-only` と理由付きで報告されます。誰も実行できない byte 数は
証拠ではありません。

## 結果

`--mangle-properties` は**外してあります**。ここで測った library では
どれも完全に不発で（fail-closed な callee-provenance scan が
bundle 内と証明できない call を見つけて全部 reserve する）、
付けても両 leg で 1 byte も動かず実行時間だけ伸びます。
**実際の library に対して property mangler が動いていない**という事実
自体が、この harness が出した一番大きな発見です。

型情報の寄与は library によって符号が変わります。hono では効き、
valibot と immer では実質ゼロ、typebox では**マイナス**です。
最新の数字は `fixtures/type-aware-corpus/expected.json` にあります。

## corpus に入れられなかったもの

9 個試して measurement に到達したのは 4 個です。残りは表に
`BLOCKED` / `size-only` として残してあります——理由が finding であり、
理由が消えた日にそのまま measurement になるからです。

| target | 状態 | 理由 |
| --- | --- | --- |
| hono | measured | — |
| valibot | measured | — |
| neverthrow | measured | 元は BLOCKED。export-surface の memo で 420s 未完 → 1 秒未満 |
| ts-pattern | measured | 同上。corpus 唯一の「discriminated union に対する網羅 match」target。ただし `P` が bundle に無い（下記）|
| typebox | size-only | bundle が load で throw: 型専用の名前 `TTypeArray` が値として emit されている |
| immer | size-only | bundle が load で throw: module 跨ぎの `const enum ArchType` が emit も inline もされない |
| superstruct | BLOCKED | **parser** の blowup（再帰的 conditional type）|
| zod | BLOCKED | parse phase が 1,095s 経っても終わらない（stuck ではなく単に遅い）|
| remeda | BLOCKED | `setPath.ts` の parse error: `Expected Semicolon, got Extends` |

最初はこの 4 つを全部「export-surface の blowup」に帰していました。
直してみたら 2 つしか該当せず、残り 2 つは**別々の原因**でした。
一つの症状（戻ってこない）に一つの原因を当てはめていたわけで、
backtrace を 1 回取っただけで満足していたのが間違いです。

### 直したもの: export-surface の blowup

`--bundle` **だけ**でも再現します（最適化 flag は要りません）:
`bundle.mbt:1102` の非最適化パスが `exported_surface_props` を
無条件で呼んでいます。

neverthrow（33 KB / 5 file）で 420 秒経っても終わらない状態の
backtrace は、`export_surface.mbt` のこの往復でした。

```
surface_escape_class  <->  surface_escape_expr        (frames 15-24)
  class_this_writes -> index_prop_assigns -> surface_visit_exprs_*   (frames 0-13)
```

`surface_escape_expr` には `SURFACE_MAX_DEPTH`（96）の深さ制限が
ありますが、**class は memo されていませんでした**。`new C(…)` が N 箇所
あれば class は N 回 escape され、その都度全 method の return を walk し、
そこから更に `new` に届く——call graph の分岐に対して指数的で、96 の cap
では全く抑えられません。加えて `class_this_writes` は呼ばれるたびに
scratch walk を作り直して constructor と全 method body を walk しなおします。

`surface_should_walk` がこれを抑えます。memo は once-only ではなく
**深さ**で keying してあります: 深いところで先に truncate された walk が
key を取ってしまうと、後から浅く到達した経路が skip され、その先の名前が
**under-reserve** される——つまり rename されて consumer が壊れる。
浅い到達は再 walk します。

結果:

| | before | after |
| --- | --- | --- |
| neverthrow | 420s 未完 | 1 秒未満 / 10,171 bytes |
| ts-pattern | 100s 未完 | 0s / 20,977 bytes |

reserved set が縮んでいないことは mangle-safety 162/162 が変わらないこと、
および `export_surface_wbtest.mbt` の「3 経路から届く class の surface が
全部残る」test で確認しています（`new` から class を walk しないよう
mutate すると 5 test が落ちます）。

深さ次元そのものは test で覆えていません。once-only に mutate しても
どの test も落ちません。区別する case を作るには `SURFACE_MAX_DEPTH`
より深くネストした式が必要で、そのサイズだと walk 自体が病的になり、
実際 test suite が 10 分を超えました。再 walk は名前を**増やす**方向
なので保守的側であり、既存の `fn:` memo は once-only だったので、
どちらにしてもこれは安全側の変更です。

### 残っているもの: 別の 2 つ

**superstruct** は export-surface を抑えた後も終わりません。backtrace は
parser の中です。

```
Parser::parse_conditional_type_tail -> parse_type ->
  parse_intersection_type -> parse_type_operand -> parse_primary_type
```

`type` alias 上の再帰的 conditional type での blowup で、別の修正が必要です。

### ついでに見つかったもの: alias 付き re-export が落ちる

ts-pattern の entry は

```ts
import * as Pattern from './patterns';
export { Pattern, Pattern as P };
```

と書いていますが、bundle の export は
`export { match, isMatching, NonExhaustiveError }` だけです。
**別 module から束縛された名前を alias 付きで re-export すると、
両方の綴りが落ちます**。`P` は ts-pattern の API の半分なので、これは
実用上致命的です。

driver は bundle が実際に出している export の範囲に留めてあり
（`P` を使わない）、この件は独立した bug として残しています。

**zod** は stuck ではありません。stack を 2 回 sample すると動いており、
まだ `mtsc_load_bundle_files` の中です——18 分経っても 133 source file を
**parse し終えていない**、という throughput の問題です。
上の 2 つとは別件です。

再現:

```sh
git clone --depth 1 https://github.com/ianstormtaylor/superstruct /tmp/ss
mtsc /tmp/ss/src/index.ts --bundle --no-check -o /dev/null   # 戻ってこない
```
