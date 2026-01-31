# Generator AOT Compilation Design

## 概要

Generatorを状態機械としてwasm-gcにコンパイルする設計。

## 現在の実装

インタプリタではCPS（継続渡しスタイル）を使用:

```moonbit
priv enum GenValue {
  Value(JSValue)
  Yield(JSValue, (JSValue) -> GenValue)
  YieldRaw(JSValue, (JSValue) -> GenValue)
}

priv enum GenSignal {
  Continue
  Yield(JSValue)
  Suspend(JSValue, (JSValue) -> GenSignal)
  Return(JSValue)
}
```

## wasm-gc 状態機械設計

### 1. Generator State Struct

```typescript
// 入力
function* counter(start: number, end: number) {
  let i = start;
  while (i < end) {
    yield i;
    i = i + 1;
  }
  return end;
}
```

↓ 変換

```wasm-gc
;; ローカル変数を保持するstruct
(type $counter_locals (struct
  (field $start f64)
  (field $end f64)
  (field $i f64)
))

;; Generator状態
(type $counter_state (struct
  (field $state i32)              ;; 現在の状態番号
  (field $locals (ref $counter_locals))
  (field $done i32)
))
```

### 2. 状態遷移

```
State 0: 初期状態 → let i = start を実行
State 1: while条件チェック → falseならState 3へ
State 2: yield i → 呼び出し元に返す、次回State 1から再開
State 3: return end → done=true
```

### 3. next() 関数

```wasm-gc
(func $counter_next
  (param $gen (ref $counter_state))
  (param $sent f64)
  (result (ref $iter_result))

  (local $s i32)
  (local.set $s (struct.get $counter_state $state (local.get $gen)))

  (block $done
    (block $state_3
      (block $state_2
        (block $state_1
          (block $state_0
            (br_table $state_0 $state_1 $state_2 $state_3 $done
              (local.get $s))
          )
          ;; State 0: 初期化
          ;; i = start (既にlocalsに設定済み)
          (struct.set $counter_state $state (local.get $gen) (i32.const 1))
          (br $state_1)
        )
        ;; State 1: while条件チェック
        (if (f64.lt
              (struct.get $counter_locals $i
                (struct.get $counter_state $locals (local.get $gen)))
              (struct.get $counter_locals $end
                (struct.get $counter_state $locals (local.get $gen))))
          (then
            (struct.set $counter_state $state (local.get $gen) (i32.const 2))
            (br $state_2))
          (else
            (struct.set $counter_state $state (local.get $gen) (i32.const 3))
            (br $state_3)))
      )
      ;; State 2: yield i, then i++
      ;; 値を返す前にi++を準備
      (struct.set $counter_locals $i
        (struct.get $counter_state $locals (local.get $gen))
        (f64.add
          (struct.get $counter_locals $i
            (struct.get $counter_state $locals (local.get $gen)))
          (f64.const 1)))
      ;; 次の状態を設定
      (struct.set $counter_state $state (local.get $gen) (i32.const 1))
      ;; yield値を返す（done=false）
      (return (call $make_iter_result
        (struct.get $counter_locals $i ...) ;; 古い値
        (i32.const 0)))
    )
    ;; State 3: return end
    (struct.set $counter_state $done (local.get $gen) (i32.const 1))
    (return (call $make_iter_result
      (struct.get $counter_locals $end ...)
      (i32.const 1)))
  )
  ;; Already done
  (call $make_iter_result (ref.null any) (i32.const 1))
)
```

## 実装フェーズ

### Phase 1: Generator分析 ✅ 完了

1. yield ポイントの抽出
2. ローカル変数の収集（yieldをまたぐもの）
3. 状態番号の割り当て
4. AOTコンパイル可能性判定

実装: `src/analysis/generator_analysis.mbt`

```moonbit
pub struct GeneratorAnalysis {
  yield_points : Array[YieldPoint]
  persisted_vars : Array[PersistedVar]
  state_count : Int
  compilable : Bool
  not_compilable_reason : String?
}

pub struct YieldPoint {
  id : Int
  expr : @ast.TsExpr?
  is_delegate : Bool
}

pub struct PersistedVar {
  name : String
  is_param : Bool
}
```

### Phase 2: 状態機械IR生成 ✅ 完了

AST → Generator中間表現への変換

実装: `src/codegen/generator_ir.mbt`

```moonbit
pub struct GenStateMachine {
  name : String
  params : Array[GenVar]
  locals : Array[GenVar]
  states : Array[GenState]
  initial_state : Int
  done_state : Int
}

pub enum GenInstr {
  Branch(GenExpr, Array[GenInstr], Array[GenInstr])
  While(GenExpr, Array[GenInstr])
  Yield(GenExpr, Int)
  Return(GenExpr)
  SetLocal(String, GenExpr)
  Exec(GenExpr)
  Nop
}

pub enum GenExpr {
  Number(Double)
  Bool(Bool)
  Str(String)
  Undefined
  Null
  Var(String)
  BinOp(GenBinOp, GenExpr, GenExpr)
  UnaryOp(GenUnaryOp, GenExpr)
  Call(String, Array[GenExpr])
  MethodCall(GenExpr, String, Array[GenExpr])
  PropAccess(GenExpr, String)
  IndexAccess(GenExpr, GenExpr)
  ArrayLit(Array[GenExpr])
  ObjectLit(Array[(String, GenExpr)])
  Cond(GenExpr, GenExpr, GenExpr)
  Raw(@ast.TsExpr)
}
```

### Phase 3: wasm-gc コード生成 ✅ 完了

GenIR → wasm-gc bytecode

実装: `src/codegen/generator_codegen.mbt`

```moonbit
pub struct GeneratorWasmCode {
  state_struct_type : @core.TypeDef
  next_func_type : @core.TypeDef
  create_func_type : @core.TypeDef
  next_func_code : @core.Code
  create_func_code : @core.Code
}

pub fn compile_generator(
  sm : GenStateMachine,
  state_struct_type_idx : UInt,
) -> GeneratorWasmCode

pub fn compile_generator_func(
  func : @ast.TsFunc,
  state_struct_type_idx : UInt,
) -> GeneratorWasmCode?
```

生成されるもの:
1. State struct type (state番号 + done flag + params + locals)
2. create() 関数 (パラメータを受け取りstate structを生成)
3. next() 関数 (br_tableによる状態遷移、yield/return処理)

### Phase 4: メインcodegen統合 ✅ 完了

`compile_module_gc` にgeneratorサポートを追加:
- generatorを自動検出
- state struct typeを追加
- `{name}_create` と `{name}_next` 関数をエクスポート

```typescript
// 入力
function* counter(n) { ... }

// 出力 (wasm exports)
counter_create(n: f64) -> ref $counter_state
counter_next(state: ref $counter_state, sent: f64) -> (f64, i32)
```

## 制約

AOTコンパイル可能なgeneratorの条件:

1. **サポート**
   - `yield expr` - 単純なyield
   - `yield*` - イテラブルの委譲（制限付き）
   - for/while/do-while ループ内のyield
   - if/else 内のyield
   - switch 内のyield

2. **非サポート（インタプリタにフォールバック）**
   - try/catch 内のyield（状態保存が複雑）
   - クロージャからのyield
   - eval内でのyield

## 変更ファイル

| ファイル | 変更 |
|---------|------|
| `src/analysis/generator_analysis.mbt` | **新規** Generator分析 |
| `src/codegen/generator_ir.mbt` | **新規** GenIR定義 |
| `src/codegen/generator_codegen.mbt` | **新規** wasm-gc生成 |
| `src/analysis/compilability.mbt` | Generator判定追加 |

## テスト戦略

```typescript
// テストケース
function* simple() { yield 1; yield 2; }
function* loop(n) { for (let i = 0; i < n; i++) yield i; }
function* fib(n) { let a = 0, b = 1; while (n-- > 0) { yield a; [a, b] = [b, a + b]; } }
```

## 性能期待値

インタプリタ比で5-10x高速化を期待（CPS変換のオーバーヘッド削減）
