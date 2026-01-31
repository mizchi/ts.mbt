# test262 Progress

## Current Status (2026-01-31)

Based on `test262.allowlist.txt` (34,268 tests) and `test262.skiplist.txt` (14,029 skipped).

### Overall

| Category | Allowlist | Skipped | Runnable | Notes |
|----------|-----------|---------|----------|-------|
| Total | 34,268 | 14,029 | ~20,000 | |
| built-ins | 17,574 | - | - | |
| language | 13,179 | - | - | |
| intl402 | 1,712 | - | - | Not tested |
| staging | 1,051 | - | - | Not tested |
| annexB | 752 | - | - | Partial |

### Language Features

| Feature | Status | Notes |
|---------|--------|-------|
| expressions | Partial | class, generators, async need work |
| statements | Partial | for-of, generators |
| function-code | Good | |
| arguments-object | Partial | |
| literals | Good | |
| identifiers | Good | |
| module-code | Skipped | ESM not supported |
| eval-code | Partial | Direct eval only |

### Built-in Objects

| Object | Status | Notes |
|--------|--------|-------|
| Object | Good | keys, values, entries, assign, etc. |
| Array | Good | Most methods work |
| String | Good | Most methods work |
| Number | Good | |
| Math | Good | |
| Function | Partial | No dynamic Function() |
| Date | Minimal | Basic operations only |
| RegExp | Minimal | Literal parsing incomplete |
| Promise | Partial | async/await works |
| Proxy | Partial | Basic traps |
| Reflect | Partial | |
| Symbol | Not supported | Using @@iterator workaround |
| Temporal | Not tested | |
| TypedArray | Not tested | |
| WeakMap/Set | Not tested | |

---

## Skip Reasons (14,029 tests)

| Reason | Count | Notes |
|--------|-------|-------|
| flag:async | 5,513 | Async tests (some supported) |
| includes:temporalHelpers.js | 2,690 | Temporal API |
| includes:testTypedArray.js | 1,123 | TypedArray |
| banned:eval | 1,418 | Dynamic eval features |
| includes:regExpUtils.js | 574 | RegExp helpers |
| banned:with | 497 | with statement (deprecated) |
| banned:Function | 322 | Dynamic Function() |
| Other includes | ~1,900 | Various test helpers |

---

## Next Steps

### High Priority

1. **yield\* for async generators**
   - Thenable handling in yield*

2. **iterator.return() / throw()**
   - Cleanup on loop break
   - for-of early termination

3. **RegExp literal parser**
   - `/pattern/flags` syntax

### Medium Priority

4. **Symbol support**
   - Symbol.iterator (currently @@iterator workaround)
   - Well-known symbols

5. **More built-ins**
   - Set, Map
   - WeakMap, WeakSet

### Low Priority (ES2024+)

- `using` declaration
- import defer
- import attributes

---

## Not Supported

These features are intentionally not implemented:

- **with statement** - Deprecated, 497 tests skipped
- **Dynamic eval features** - Limited to direct eval
- **Tail call optimization** - Not implemented
- **ES modules** - Parser accepts but not fully executed

---

## Completed

- Strict mode duplicate parameter validation
- Strict mode eval/arguments assignment prohibition
- for-await-of parser fix
- Async generator basic support
- Line terminator handling (CR, LS, PS)
- AOT compilation基盤 (TypeScript → wasm-gc → wasm5 runtime)

---

## Architecture Decisions

### AOT Compilation & Intermediate Representation (2026-01-31)

**現在のアーキテクチャ:**
```
TypeScript → wasm-gc → wasmtime (Cranelift最適化)
```

**決定:** HIR/TIRのような独自中間IRは**現時点では不要**

**理由:**
1. AOTコンパイルで10-12x高速化を達成済み（インタプリタ比）
2. wasmtimeのCranelift最適化が成熟している
3. wasm外での実行を必要とするユースケースが現時点でない

**YAGNI原則を適用:** 具体的なニーズが生じた時点でIR層を追加する

**再検討するタイミング:**
- wasmがサポートされない環境への対応が必要になった場合
- Cranelift最適化を超える性能が必要になった場合
- ネイティブバイナリや他言語への出力が必要になった場合

### Generator AOT Compilation (2026-01-31) ✅ 完了

Generatorを状態機械としてwasm-gcにコンパイルする機能を実装。

**実装状況:**
- ✅ Phase 1: Generator分析 (`src/analysis/generator_analysis.mbt`)
  - yield ポイント抽出
  - 持続変数の収集
  - AOTコンパイル可能性判定
- ✅ Phase 2: 状態機械IR生成 (`src/codegen/generator_ir.mbt`)
  - GenStateMachine, GenInstr, GenExpr 定義
  - AST → GenIR 変換
- ✅ Phase 3: wasm-gc コード生成 (`src/codegen/generator_codegen.mbt`)
  - State struct type 生成
  - create()/next() 関数生成
  - br_table による状態遷移（最適化済み）
- ✅ メインcodegenへの統合 (`src/codegen/codegen.mbt`)
  - `compile_module_gc` でgeneratorを自動検出
  - `{name}_create` と `{name}_next` 関数をエクスポート

**残作業:**
- Iterator protocolとの完全な接続（ランタイム側）
- throw/return メソッドのサポート

詳細: `docs/generator-aot-design.md`
