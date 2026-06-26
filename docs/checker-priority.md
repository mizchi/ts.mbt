# Checker 未実装機能の実装優先度トリアージ

> 作成: 2026-06-26 / 基準: pinned conformance gate `recall=668/815`, `precision=414/414 (0 FP)`
>
> このドキュメントは「未実装の TS 機能をどの順番で実装するか」を、conformance の
> ファイル数ではなく **実世界の遭遇頻度** と **bridge プロダクトへの寄与** で
> トリアージしたもの。`TODO.md` の T0–T125 が「実装済みチェックの履歴」なのに対し、
> こちらは「これから何を、どの順で」の戦略メモ。

## 大前提：2 つのトラックを分離する

この repo の checker には 2 つの役割があり、「未実装機能」の優先度は
**どちらを最適化するかで逆転する**。

- **Track A（プロダクト = bridge）**: 実ユーザーが `ts2mbt` で npm の `.d.ts` を
  変換するときに踏むもの。= **パーサ網羅性** と **型マッピング忠実度**
  （generics / union / conditional / mapped / template-literal / utility types を
  MoonBit に正確に写す）。checker recall とは別軸。
- **Track B（checker recall = conformance）**: TS の型エラー検出（TS2322 等）。
  これまで `recall→700` を目指してきた軸。bridge では合成出力の sanity gate
  （`@checker.check_module`）として働く。

**conformance のファイル数 ≠ 実世界の遭遇頻度** に注意。例：

- `TS18014`（nested private name shadowing）は conformance に 6 ファイルあるが、
  実コードではほぼ書かれない。さらに実装にはパーサのクラス lowering 変更が前提
  （後述の「確定した手詰まり」参照）。
- 逆に「`.d.ts` の conditional type を MoonBit にどうマップするか」は
  checker recall には 1 ポイントも効かないが、bridge の実ユーザーは毎回踏む。

## conformance miss 分布（pinned 142 files / 815）

実頻度で重み付けする前の生データ。上位バケットのみ。

| miss 数 | コード | 機能 |
|---|---|---|
| 36 | TS2322 | Type X not assignable to Y（代入可能性） |
| 18 | TS2339 | Property does not exist（プロパティ解決＋絞り込み） |
| 14 | TS2345 | Argument not assignable（呼び出しの代入可能性） |
| 7 | TS2344 | does not satisfy constraint（ジェネリック制約） |
| 6 | TS2415 | incorrectly extends base（クラス代入可能性） |
| 6 | TS18014 | nested private name shadowing（エッジ・パーサ前提） |
| 5 | TS7006 | parameter implicitly has 'any'（noImplicitAny） |
| 4 | TS2554 | expected N arguments（アリティ・現在抑制中） |
| 3 ×複数 | TS7053 / TS2769 / TS2741 / TS2564 / TS2551 / TS2403 / TS2349 / TS2304 / TS2300 | — |
| 2 ×複数 | TS2872 / TS2806 / TS2739 / TS2684 / TS2502 / TS2445 / TS2420 / TS2411 / TS2367 / TS2353 / TS2352 / TS2314 / TS1268 / TS1206 / TS1005 | — |
| 1 ×約50 | ロングテール | エッジケース群 |

## 実世界の遭遇頻度でのトリアージ（Track B）

| 頻度 | 機能バケット | 関連コード | コスト | FP リスク |
|---|---|---|---|---|
| **S（毎日）** | 制御フロー絞り込み（typeof / instanceof / truthy / 判別共用体） | TS2339, TS18047/48, TS2367, TS2872, TS2345/2322 の一部 | 大 | 中〜高 |
| **A（頻繁）** | ジェネリック制約・インスタンス化 | TS2344, TS2314, TS2589 | 中 | 中 |
| **A** | 引数アリティ（現在意図的に抑制中） | TS2554, TS2575 | 小〜中 | 高 |
| **A** | noImplicitAny（文脈型推論） | TS7006/7008/7031/7053 | 中 | 中 |
| **B（時々）** | 高度な代入可能性（関数共用体・交差・深い構造比較） | TS2322/2345 の残り, TS2741/2739/2353 の高度形 | 中 | **高** |
| **B** | クラス継承エッジ | TS2415, TS2420, TS2445 | 中 | 低〜中 |
| **C（稀・エッジ）** | ロングテール | TS18014 ほか 1 件ずつ約 50 | 様々 | 様々 |

### 重要な非対称性（FP 方向）

- **代入可能性（TS2322 系）**: miss 最多（~55）だが **FP 方向が危険**。
  「TS は代入 OK なのに我々が NG」= FP。構造比較が過剰厳格だと valid を flag し、
  0-FP gate を最も壊しやすい。**数は多いが着手は最後**。
- **narrowing（絞り込み）**: 実世界頻度が最大。現状は union のプロパティアクセスを
  保守的に黙認しているので、ここを入れると TS2339 の塊＋null 系＋等価比較が
  一気に動く。ただしエンジンが大きい。

## 推奨ロードマップ（バランス軸・既定案）

`generics / union / narrowing` は **プロダクト忠実度と checker recall の両方に効く
交差領域**。ここを攻めるとどちらの目的でも無駄にならない。各 Phase は
「0-FP を守れる単位」で区切る。

### Phase 0 — 足場（低 FP リスク・ただし要プラミング・recall ほぼ +0）
1. **noImplicitAny（TS7006 系）**: トップレベル関数宣言の「型注釈なし param」限定で
   開始。文脈型が付く位置（コールバック引数等）は除外して FP を抑える。

   > **実装時に判明した制約（2026-06-26 調査）**:
   > - AST の `TsParam.type_` は非 optional で、**「注釈なし」と「明示 `: any`」を
   >   区別できない**（両方 `Any` になる）。TS7006 は前者だけに出すべきなので、
   >   パーサに「注釈なし param」を記録する新チャネル（`has_body_block` /
   >   `param_optional_initializer_misuses` と同パターン）が必要。
   > - `noImplicitAny` フラグも未追跡（`strict_null_checks` /
   >   `strict_property_initialization` はあるが noImplicitAny はない）。
   >   `TsModule` に `no_implicit_any : Bool` 追加＋ `@noImplicitAny` /
   >   `@strict` ディレクティブ検出が要る（構築サイト約 8 箇所）。
   > - **conformance recall は ~+0**: pinned の TS7006 miss 5 件は全て
   >   contextual-typing ケース（comma / `&&` の左辺 arrow、class expression
   >   method）で、単純なトップレベル param チェックでは捕捉できない。
   >   よってこれは「実世界の品質・プロダクト価値」枠であり、recall 目標には
   >   寄与しない。着手するなら期待値をそう設定する。

### Phase 1 — 交差領域（中コスト・両トラックに効く）
2. **ジェネリック制約検証（TS2344）**: `type_param_bounds` が既にあるので、
   明示型引数 `Foo<T>` の制約違反を構造的に検証。bridge では「制約付き
   ジェネリックの正しいマッピング」にも直結。
3. **判別共用体の絞り込み（narrowing 第一歩）**: `typeof` / リテラルタグによる
   discriminated union の絞り込みだけ先に。TS2339 の一部と bridge の union 表現
   精度が両方上がる。

### Phase 2 — 最大価値（要エンジン）
4. **制御フロー絞り込み本体**: `instanceof` / truthiness / null チェック。
   TS2339・TS18047/48・TS2367・TS2872 がまとめて動く。実世界頻度は最大だが
   エンジンなので Phase 1 で足場を固めてから。

   > **実装時に判明した制約（2026-06-26 調査）**:
   > - **narrowing エンジンは既に存在し、かなり完成している**
   >   （`analyse_narrowing` / `narrow_by_discriminant` / `narrow_union` /
   >   `typeof` / `instanceof` / `=== null/undefined` / 判別共用体 / `&&`）。
   >   単純 `Var` レシーバの判別共用体プロパティアクセスは正しく flag する
   >   （`if (v.kind==="a") v.y` → TS2339）。よって Phase 2 は「ゼロから
   >   エンジンを作る」ではなく **既存エンジンの穴を埋める**作業。
   > - 残る narrowing miss の正体は 2 つ:
   >   **(a) プリミティブ prototype テーブル未モデル** — `x.toFixed()` の
   >   `x:string` ですら 0 issue。`string`/`number`/`boolean` のメソッド表が
   >   無いので「narrowed 後に間違ったメソッド」を検出できない。完全な表が
   >   無いと逆に valid メソッドを誤検出するため FP リスク大。
   >   **(b) PropAccess-chain / aliased-discriminant の narrowing 未対応** —
   >   `this.test.name`（`this.test` がプロパティアクセス）や
   >   `const t = x.type; if (t===…)` は engine が narrow しない
   >   （`controlFlowAliasing2`）。union-プロパティ検査はここで FP を出すため、
   >   T127 では「単純 `Var` レシーバ限定」ゲートで回避済み。
   > - **T127 で union "全メンバーに無いと不正" ルールを追加済み**
   >   （some-but-not-all、`Var` レシーバ＋全メンバー列挙可能時のみ）。
   >   pinned recall 668→669（unionTypeMembers）。

### Phase 3 — 最後（FP リスク最大）
5. **代入可能性の深化**（関数共用体・交差・深い構造比較）。narrowing 投入後の方が
   「本当に不一致か」を切り分けやすく FP を避けやすい。miss 数は最多だが着手は最後。

## レンズを変える場合の差分

- **bridge プロダクト忠実度を最優先**にするなら順序を組み替え、
  「**パーサ網羅性**（実 npm の `.d.ts` で parse 失敗する構文）＋
  **conditional / mapped / template-literal / utility types の MoonBit マッピング
  忠実度**」を Phase 0–1 に引き上げる。checker recall はほぼ動かないが、
  実ユーザーの体感は最も良くなる。**着手前に実 npm パッケージ数本を `ts2mbt` に
  通して parse 失敗・型ロスを実測**し、そのデータでロードマップを引き直すのを推奨。
- **純粋に recall=700 最短**なら、ファイル数の多い TS2322（~55）バケットに機械的に
  突っ込む順序になるが、FP リスク最大で 0-FP gate と衝突しやすく **非推奨**。

## 後回し / 確定した手詰まり

着手前に判断済みの「やらない／今はできない」項目。再調査の無駄を防ぐため記録。

- **アリティ un-suppression（TS2554）**: optional / rest / overload を先にモデル化
  しないと FP 確定。実測で「`is not callable` 抑制を外すと +4 recall / 10 FP」を確認済み。
- **TS18014（nested private name shadowing, 6 files）**: メソッド/コンストラクタ本体内の
  ネストしたクラスは **IIFE 関数式に lowering** され、クリーンなクラス AST
  （private 名集合・メソッド param 型・`a.#foo` レシーバ）が失われる。実装には
  パーサのクラス lowering 変更が前提で、bridge/emit への回帰リスクが大きい。非増分。
- **permissive 抑制フィルタ（`is_permissively_suppressed`）の緩和**: 微妙に均衡しており、
  arity / `not callable` を外すと FP が出ることを確認済み。触らない。
- **`object` キーワード（NonPrimitive）**: 実装すると recall が **下がる**（665→661）
  ことを実測で確認済み（~149 箇所の Any wildcard match を継承しないため）。revert 済み。
- **TS2403（subsequent declarations must have same type）**: 構造的型 **等価性** が必要
  （`string|number` と `number|string` を等価判定できないと FP）。型機構が要る。
- **TS2445 を namespace 本体に拡張**: 全コーパスで namespace 本体の式を walk する必要があり
  ブラスト半径が大きい（1 ファイルのために全 namespace を新規検査）。非推奨。

## 結論（2026-06-26 時点）

- **増分的な sound recall win は枯渇**。`recall=668/815` までで、構造的・パース時・
  ヒープチェーン・オーバーロード検出系は全て収穫済み。残る miss を全クラスタ
  （≥2 件 + 主要 single）まで個別調査した結果、例外なく
  **(a) 型機構（代入可能性 / flow narrowing / generic instantiation）**、
  **(b) パーサ変更が前提（TS18014）**、**(c) エッジ/抑制フィルタ** のいずれか。
- したがって 668→700 は「小さな pass の積み上げ」では到達せず、上の Phase で挙げた
  **本格的な機能を 1 つずつ腰を据えて作る**ことになる。Phase 0 ですら
  パーサ・プラミングが要り、かつ recall には寄与しない（上記参照）。
- 次に着手する機能は **ユーザーが明示的に選んでから**始める（各 Phase は
  複数ターンの実装コミットメントで、0-FP 検証も個別に要るため）。

## 守るべき制約（数値目標より上位）

実装順に関わらず、以下は **常に** 数値目標より優先する（明示指示）。

1. **0 false positives** を維持（`scripts/checker_conformance_oracle.sh --max-fp 0`）。
2. テストスイート（現在 2379）と bridge プロダクトを壊さない。
3. recall 数値を捏造しない・unsound なチェックを出さない。

各機能は個別に oracle で 0-FP を検証してから merge する（measure → implement →
oracle-gate → commit → PR → merge → sync のループ）。
