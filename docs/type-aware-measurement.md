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

9 個試して、挙動まで検証できたのは 2 個でした。残りは表に
`BLOCKED` / `size-only` として残してあります——理由が finding であり、
理由が消えた日にそのまま measurement になるからです。

| target | 状態 | 理由 |
| --- | --- | --- |
| hono | measured | — |
| valibot | measured | — |
| typebox | size-only | bundle が load で throw: 型専用の名前 `TTypeArray` が値として emit されている |
| immer | size-only | bundle が load で throw: module 跨ぎの `const enum ArchType` が emit も inline もされない |
| zod | BLOCKED | export-surface の blowup |
| neverthrow | BLOCKED | export-surface の blowup（33 KB / 5 file で 420s 未完） |
| superstruct | BLOCKED | export-surface の blowup |
| ts-pattern | BLOCKED | export-surface の blowup |
| remeda | BLOCKED | `setPath.ts` の parse error: `Expected Semicolon, got Extends` |

### export-surface の blowup

4 つの target が同じ原因で止まっています。`--bundle` **だけ**でも
再現します（最適化 flag は要りません）: `bundle.mbt:1102` の
非最適化パスが `exported_surface_props` を無条件で呼んでいます。

neverthrow（33 KB / 5 file）で 420 秒経っても終わらない状態の
backtrace は、`export_surface.mbt` のこの往復です。

```
surface_escape_class  <->  surface_escape_expr        (frames 15-24)
  class_this_writes -> index_prop_assigns -> surface_visit_exprs_*   (frames 0-13)
```

`surface_escape_expr` には `SURFACE_MAX_DEPTH` の深さ制限がありますが、
**class は memo されていません**。`class_this_writes` は呼ばれるたびに
scratch walk を作り直して constructor と全 method body を walk しなおすので、
同じ class が複数の escape 経路から届くと、その都度 nested class ごと
walk が再実行されます。

再現:

```sh
git clone --depth 1 https://github.com/supermacro/neverthrow /tmp/nt
mtsc /tmp/nt/src/index.ts --bundle --no-check -o /dev/null   # 戻ってこない
```

各 file を単体で（`--bundle` なしで）compile すると全部通ります。
bundle 側だけの問題です。
