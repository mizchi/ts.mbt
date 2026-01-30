# test262 修正計画

## 現状サマリー (2026-01-30)

| ステータス | 件数 |
|-----------|------|
| Passed | 14,215 |
| Failed | 5,595 |
| Skipped | 4,066 |
| **Total** | 23,876 |

### 最新の修正 (generator CPS対応 + yield*) - 完了
- **for/while/do-while ループ内の yield 対応**
  - `exec_for_loop_gen` と `exec_while_loop_gen` を追加
  - 継続渡しスタイル (CPS) で yield からの再開をサポート
- **try-catch-finally 内の yield 対応**
  - `exec_try_catch_gen` を追加
  - try ブロック内の yield から再開可能
- **`stmt_has_yield` / `block_has_yield` 判定関数を追加**
  - yield を含む構造のみ CPS 版を使用（パフォーマンス最適化）
- **yield* が元のイテレータ result をそのまま返すように修正**
  - `GenSignal::YieldRaw` / `GenSignal::SuspendRaw` を追加
  - yield* の結果で done フラグが自動追加されなくなった
- **eval_expr_gen に配列リテラル、条件演算子の generator 対応を追加**
  - `[yield x]` や `(yield x) ? a : b` が正しく動作
- **パーサー修正: yield の引数を AssignmentExpression でパース**
  - `yield 'hit' in obj` が正しく `yield ('hit' in obj)` としてパースされる
- **Passed: 14,169 → 14,215 (+46)**

### 以前の修正 (strict mode + prototype lookup) - 完了
- **グローバル定数を non-writable に**
  - `Infinity`, `NaN`, `undefined` を `writable: false, enumerable: false, configurable: false` に
  - strict mode で代入すると TypeError
- **Number 定数追加**
  - `Number.MAX_VALUE`, `MIN_VALUE`, `EPSILON`, `MIN_SAFE_INTEGER`
- **delete super.x で ReferenceError**
  - `delete super.property` や `delete super[key]` で ReferenceError
- **strict mode で non-configurable プロパティの delete で TypeError**
- **__proto__ in object literals**
  - `{ __proto__: obj }` がプロトタイプを設定 (own property として追加しない)
- **プリミティブのプロパティアクセス**
  - `(1).foo` が `Number.prototype.foo` を検索
  - 同様に String, Boolean も対応
- **Passed: 14,097 → 14,169 (+72)**

### 以前の修正 (private method/accessor エラー処理) - 完了
- **プライベートメソッドへの代入禁止**
  - `this.#privateMethod += 1` のような compound assignment で TypeError
  - PrivateSet で method kind の場合は常にエラー
- **getter-only プライベートアクセサへの代入禁止**
  - `get #field()` のみ定義され `set` がない場合、代入時に TypeError
  - プロトタイプチェーンを辿って getter/setter を検出
- **getter/setter 両方あるプライベートアクセサの setter 呼び出し**
  - プロトタイプチェーン上の setter を正しく呼び出し
- **delete null/undefined でTypeError**
  - `delete null.prop` や `delete undefined.prop` で TypeError を投げる
- **Passed: 13,991 → 14,097 (+106)**

### 以前の修正 (async/await テストサポート) - 完了
- **async フラグのスキップ解除**
  - async/await構文は既に動作していたが、テストがスキップされていた
  - `$DONE` コールバックパターンでエラー検出
  - `get_last_error()` API追加でテストランナーからエラー取得
- **asyncHelpers.js ハーネス実装**
  - `asyncTest()` - 非同期テストラッパー
  - `assert.throwsAsync()` - 非同期例外アサーション
- **Passed: 13,194 → 13,714 (+520)**
- **Skipped: 7,923 → 4,066 (-3,857)**
- ※ 以前スキップされていた3,857件が実行されるようになり、うち520件がパス

### 以前の修正 (propertyHelper.js サポート) - 完了
- **propertyHelper.js ハーネス実装**
  - `verifyProperty()` - プロパティディスクリプタの検証
  - `verifyCallableProperty()` - 関数プロパティの検証
  - `verifyWritable/NotWritable()` - writable属性の検証
  - `verifyEnumerable/NotEnumerable()` - enumerable属性の検証
  - `verifyConfigurable/NotConfigurable()` - configurable属性の検証
  - `isSameValue()`, `isWritable()`, `isEnumerable()`, `isConfigurable()`
- **依存機能の確認 (すべて動作済み)**
  - `Object.getOwnPropertyDescriptor`
  - `Object.defineProperty`
  - `Object.getOwnPropertyNames`
  - `Function.prototype.call.bind`
  - `Array.isArray`, `propertyIsEnumerable`
- **追加ハーネス**
  - `fnGlobalObject.js` - グローバルオブジェクト取得
  - `isConstructor.js` - コンストラクタ判定
  - `deepEqual.js` - 深い比較
  - `decimalToHexString.js` - 16進数変換
  - `proxyTrapsHelper.js` - Proxyトラップヘルパー
- **Passed: 12,366 → 13,194 (+828)**
- **Skipped: 9,109 → 7,923 (-1,186)**

### 以前の修正 (private fields / methods 対応) - 完了
- **プライベートフィールド/メソッドのアクセス制御実装**
  - `#field` 構文のパース (既存)
  - ブランドベースのアクセス制御 (WeakMap的セマンティクス)
  - インスタンスプライベートフィールド (`#field = value`)
  - インスタンスプライベートメソッド (`#method() {}`)
  - 静的プライベートフィールド (`static #field = value`)
  - 静的プライベートメソッド (`static #method() {}`)
  - 不正アクセス時の TypeError 発生
- **ブランド実装の詳細**
  - 各クラスにユニークなブランドID (`__private_brand__N`) を生成
  - プライベート名をブランド付きにマングリング (`#field` → `__private_brand_0__#field`)
  - インスタンス生成時にブランドプロパティを設定
  - プロパティアクセス時にブランドチェックを実行
- **class/elements テスト: 465 → 531 passed (+66)**
- **Passed: 12,300 → 12,366 (+66)**

### 以前の修正 (strict mode + TDZ 対応) - 一部完了
- **compound assignment で未宣言変数を参照するとReferenceError**
  - `x *= 1` で x が存在しない場合、ReferenceError を投げるように修正
  - CompoundAssignExpr (式としての compound assignment) も対応
- **class body は暗黙的に strict mode**
  - class IIFE の先頭に "use strict" を追加
  - class メソッド内での未宣言変数への代入が ReferenceError になる
- **非拡張オブジェクトへのプロパティ追加禁止 (strict mode)**
  - `Object.preventExtensions()` されたオブジェクトに新しいプロパティを追加すると TypeError
- **writable:false プロパティへの代入禁止 (strict mode)**
  - compound assignment (`obj.prop <<= value`) でも set_prop_value を使用
  - PropAccess と IndexAccess の両方で strict mode チェック
- **for-of / for-in の TDZ (Temporal Dead Zone) 対応**
  - `for (let x of [x])` や `for (let x in { x })` で TDZ エラーを投げる
  - iterable/object 式を binding 環境で評価するように修正
- **Passed: 12,240 → 12,300 (+60)**

### 以前の修正 (super対応) - 完了
- クラスのコンストラクタ/メソッド内での super.xxx 参照が動作するよう修正
- extends なしでも super は Object.prototype を参照
- static メソッドでは super は親クラス（または Function.prototype）を参照
- getter/setter 内での super 対応
- オブジェクトリテラルのメソッド内での super（`__home_object` 実装）
- generator メソッド内での super 対応
- クラスフィールドのアロー関数内での super 対応
- `__super_proto` 等の内部プロパティを non-enumerable に設定
- **"super is not defined" エラー: 18 → 0 件に解消**

---

## SKIPの内訳 (更新: 4,066件)

| 理由 | 件数 | 優先度 |
|------|------|--------|
| with statement not supported | 3,451 | 対応しない |
| module syntax | 319 | 中 |
| fixture | 252 | - |
| missing includes: tcoHelper.js | 34 | 低 (対応しない) |
| missing includes: resizableArrayBufferUtils.js | 7 | 低 (ES2024) |
| missing includes: testTypedArray.js | 2 | 低 |
| missing includes: wellKnownIntrinsicObjects.js | 1 | 低 |

### 完了したスキップ理由
- ~~async flag~~ → テスト実行可能に (+520 passed)
- ~~propertyHelper.js~~ → ハーネス実装完了
- ~~fnGlobalObject.js~~ → ハーネス実装完了
- ~~asyncHelpers.js~~ → ハーネス実装完了

---

## ERRORの内訳 (パースエラー)

| エラーパターン | 件数 | 対応方針 |
|----------------|------|----------|
| Unexpected token: Import | 184 | dynamic import構文 |
| Expected RBrace, got Eof | 146 | パーサー修正 |
| Expected 'from' in import/export | 75 | import defer構文 |
| Expected Colon, got Star | 62 | オブジェクトメソッド短縮構文 |
| Expected LBrace, got LParen | 24 | class式パース |
| Unexpected token: Slash | 23 | 正規表現リテラル |
| Expected identifier, got Eof | 20 | 不完全パース |
| Expected base class name, got Class | 11 | class extends |

---

## FAILの内訳

### エラータイプ別

| エラーパターン | 件数 | 優先度 |
|----------------|------|--------|
| Expected an error to be thrown | 663 | 高 |
| Expected SyntaxError but got TypeError | 69 | 中 |
| negative mismatch (parse phase) | 67 | 中 |
| Cannot read properties of null/undefined | 0 | 完了 |
| value is not callable | 44 | 高 |
| Expected SyntaxError but got ReferenceError | 44 | 中 |
| Assertion failed | 34 | 中 |
| super is not defined | 0 | 完了 |
| using is not defined | 21 | 低 (ES2024) |
| Spread value is not iterable | 16 | 中 |

### 機能別

| 機能領域 | FAIL数 | 主な問題 |
|---------|--------|----------|
| class | 547 | strict mode, static, ネストクラスprivate |
| compound-assignment | 115 | strict mode エラー処理 |
| for-of | 98 | イテレータ、destructuring |
| super | 49 | super参照解決 |
| object | 44 | メソッド定義、getter/setter |
| assignment | 36 | strict mode |
| generators | 32 | yield式の値 |
| yield | 30 | generator関連 |
| logical-assignment | 30 | ??=, &&=, ||= |
| function | 35 | strict mode |

---

## 優先度順 修正タスク

### P0: 高優先度 (影響範囲大)

1. **[ ] strict mode エラー処理 (~800件)**
   - 未宣言変数へのassignでReferenceErrorを投げる
   - arguments/eval への代入禁止
   - 重複引数名禁止
   - 関連: compound-assignment, assignment, class

2. **[x] superキーワード対応 (完了)**
   - [x] クラスコンストラクタ/メソッド内での super.xxx
   - [x] extends なしでも Object.prototype を参照
   - [x] static メソッド内での super
   - [x] getter/setter 内での super
   - [x] オブジェクトリテラルのメソッド内での super (`__home_object`)
   - [x] generator 内での super
   - [x] クラスフィールドのアロー関数内での super
   - ファイル: `parser_class.mbt`, `interpreter_eval.mbt`, `interpreter_iter_eval.mbt`

3. **[x] null/undefined のプロパティアクセス (完了)**
   - [x] 適切なTypeError投げ (strict mode無関係に常にエラー)
   - [x] メッセージ改善 (`Cannot read/set properties of null/undefined`)
   - ファイル: `interpreter_props.mbt`, `interpreter_eval.mbt`

4. **[ ] イテレータプロトコル完全対応 (~100件)**
   - for-of での正しいイテレータ呼び出し
   - Symbol.iterator対応
   - iterator.return() / throw() 呼び出し

### P1: 中優先度

5. **[x] private fields / methods (完了)**
   - [x] `#field` 構文のパース
   - [x] ブランドベースのアクセス制御 (WeakMap的セマンティクス)
   - [x] インスタンスプライベートフィールド/メソッド
   - [x] 静的プライベートフィールド/メソッド
   - [x] 不正アクセス時のTypeError
   - [ ] 残課題: プライベートメソッドの `.name` プロパティ
   - [ ] 残課題: ネストしたクラスでの外部クラスprivateアクセス
   - ファイル: `parser_class.mbt`, `parser_expr.mbt`, `parser_core.mbt`, `interpreter_props.mbt`

6. **[ ] generator関数の値 (~60件)**
   - yield式の戻り値
   - .next(value) の引数伝播

7. **[ ] オブジェクトリテラル拡張**
   - shorthand method: `{ foo() {} }`
   - computed property names in methods
   - getter/setter with super

8. **[ ] パースエラー修正 (~300件)**
   - ~~dynamic import `import()`~~ ✓完了
   - `import.meta` ✓完了
   - 正規表現リテラル `/pattern/flags`
   - オブジェクトメソッド短縮構文

9. **[x] propertyHelper.js 対応 (完了)**
   - Object.getOwnPropertyDescriptor ✓
   - Object.defineProperty ✓
   - property descriptor support ✓
   - **+814 passed, -1164 skipped**

### P2: 低優先度

10. **[ ] module構文完全対応 (~220件)**
    - import defer
    - import attributes
    - re-exports

11. **[x] async/await (完了)**
    - Promise対応 ✓
    - async function ✓
    - async generator (部分的)
    - **+520 passed, -3,857 skipped**

12. **[ ] using declaration (ES2024, ~50件)**
    - `using` キーワード
    - Symbol.dispose

---

## 対応しない項目

- **with statement** (3,451件): 非推奨、strict modeで禁止
- **tcoHelper.js** (34件): 末尾呼び出し最適化
- **eval strict mode の一部**: 複雑すぎる仕様

---

## 次のアクション

1. ~~private fields / methods の実装~~ ✓完了
2. ~~propertyHelper.js 対応~~ ✓完了
3. ~~async/await テストサポート~~ ✓完了
4. ~~dynamic import / import.meta~~ ✓完了
5. strict mode エラー処理の残り (arguments/eval代入禁止、重複引数名)
6. ~~generator関数内のループ/try-catch での yield~~ ✓完了
7. generator の yield* 対応の改善 (~30件失敗中)
8. パーサーの正規表現リテラル対応
9. module構文対応 (319件スキップ中)

---

## 進捗サマリー

| 日付 | Passed | Failed | Skipped | 主な変更 |
|------|--------|--------|---------|----------|
| 開始時 | 12,240 | - | - | baseline |
| strict+TDZ | 12,300 | - | - | +60 |
| private fields | 12,366 | - | - | +66 |
| propertyHelper | 13,194 | 2,759 | 7,923 | +828 |
| async/await | 13,714 | 6,096 | 4,066 | +520 |
| dynamic import | 13,991 | 5,819 | 4,066 | +277 |
| private method/accessor | 14,097 | 5,713 | 4,066 | +106 |
| strict mode + proto | 14,169 | 5,641 | 4,066 | +72 |
| generator CPS + yield* | 14,215 | 5,595 | 4,066 | +46 |

**総合改善: +1,975 passed tests**
