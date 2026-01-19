// JS → Instr 変換の実験用テスト

///|
/// JS: function answer() { return 42; }
test "js experiment: constant function" {
  let func_type : @core.TypeDef = Func({ params: [], results: [I32] })
  let code : @core.Code = {
    locals: [],
    body: @core.Expr::{ instrs: [I32Const(42U)] },
    compiled: None,
    max_stack_height: 0,
  }
  let module_ = @core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [@core.Export::{ name: b"answer", desc: Func(0U) }],
    codes: [code],
  }
  let runtime = @runtime.Runtime::load(module_)
  runtime.run_start()
  let results = runtime.call_compiled(b"answer", [])
  assert_eq(results[0], @runtime.Value::I32(42U))
}

///|
/// JS: function add(a: number, b: number): number { return a + b; }
/// (i32 版)
test "js experiment: add function i32" {
  let func_type : @core.TypeDef = Func({ params: [I32, I32], results: [I32] })
  let code : @core.Code = {
    locals: [],
    body: @core.Expr::{
      instrs: [
        LocalGet(0U), // a
        LocalGet(1U), // b
        I32Add,
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let module_ = @core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [@core.Export::{ name: b"add", desc: Func(0U) }],
    codes: [code],
  }
  let runtime = @runtime.Runtime::load(module_)
  runtime.run_start()
  let results = runtime.call_compiled(b"add", [@runtime.Value::I32(3U), @runtime.Value::I32(5U)])
  assert_eq(results[0], @runtime.Value::I32(8U))
}

///|
/// JS: function add(a: number, b: number): number { return a + b; }
/// (f64 版 - JS の number に近い)
test "js experiment: add function f64" {
  let func_type : @core.TypeDef = Func({ params: [F64, F64], results: [F64] })
  let code : @core.Code = {
    locals: [],
    body: @core.Expr::{
      instrs: [
        LocalGet(0U), // a
        LocalGet(1U), // b
        F64Add,
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let module_ = @core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [@core.Export::{ name: b"add", desc: Func(0U) }],
    codes: [code],
  }
  let runtime = @runtime.Runtime::load(module_)
  runtime.run_start()
  let results = runtime.call_compiled(b"add", [
    @runtime.Value::F64(3.14),
    @runtime.Value::F64(2.86),
  ])
  assert_eq(results[0], @runtime.Value::F64(6.0))
}

///|
/// JS: function max(a: number, b: number): number {
///       if (a > b) { return a; } else { return b; }
///     }
test "js experiment: if-else max function" {
  let func_type : @core.TypeDef = Func({ params: [I32, I32], results: [I32] })
  let code : @core.Code = {
    locals: [],
    body: @core.Expr::{
      instrs: [
        LocalGet(0U), // a
        LocalGet(1U), // b
        I32GtS, // a > b (signed)
        If(
          Value(I32),
          [LocalGet(0U)], // then: return a
          [LocalGet(1U)], // else: return b
        ),
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let module_ = @core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [@core.Export::{ name: b"max", desc: Func(0U) }],
    codes: [code],
  }
  let runtime = @runtime.Runtime::load(module_)
  runtime.run_start()
  // max(10, 5) = 10
  let results1 = runtime.call_compiled(b"max", [@runtime.Value::I32(10U), @runtime.Value::I32(5U)])
  assert_eq(results1[0], @runtime.Value::I32(10U))
  // max(3, 7) = 7
  let results2 = runtime.call_compiled(b"max", [@runtime.Value::I32(3U), @runtime.Value::I32(7U)])
  assert_eq(results2[0], @runtime.Value::I32(7U))
}

///|
/// JS: function factorial(n: number): number {
///       if (n <= 1) { return 1; }
///       return n * factorial(n - 1);
///     }
test "js experiment: recursive factorial" {
  let func_type : @core.TypeDef = Func({ params: [I32], results: [I32] })
  let code : @core.Code = {
    locals: [],
    body: @core.Expr::{
      instrs: [
        // if (n <= 1)
        LocalGet(0U), // n
        I32Const(1U),
        I32LeS, // n <= 1
        If(
          Value(I32),
          // then: return 1
          [I32Const(1U)],
          // else: return n * factorial(n - 1)
          [
            LocalGet(0U), // n
            LocalGet(0U), // n
            I32Const(1U),
            I32Sub, // n - 1
            Call(0U), // factorial(n - 1) - func index 0 は自分自身
            I32Mul, // n * result
          ],
        ),
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let module_ = @core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [@core.Export::{ name: b"factorial", desc: Func(0U) }],
    codes: [code],
  }
  let runtime = @runtime.Runtime::load(module_)
  runtime.run_start()
  // factorial(5) = 120
  let results = runtime.call_compiled(b"factorial", [@runtime.Value::I32(5U)])
  assert_eq(results[0], @runtime.Value::I32(120U))
  // factorial(0) = 1
  let results0 = runtime.call_compiled(b"factorial", [@runtime.Value::I32(0U)])
  assert_eq(results0[0], @runtime.Value::I32(1U))
}

///|
/// JS: function sum_loop(n: number): number {
///       let total = 0;
///       let i = 1;
///       while (i <= n) {
///         total = total + i;
///         i = i + 1;
///       }
///       return total;
///     }
test "js experiment: while loop sum" {
  let func_type : @core.TypeDef = Func({ params: [I32], results: [I32] })
  // locals: [0]=n(param), [1]=total, [2]=i
  let code : @core.Code = {
    locals: [I32, I32], // total, i
    body: @core.Expr::{
      instrs: [
        // let total = 0
        I32Const(0U),
        LocalSet(1U),
        // let i = 1
        I32Const(1U),
        LocalSet(2U),
        // while loop
        Block(Empty, [
          Loop(Empty, [
            // if (i > n) break
            LocalGet(2U), // i
            LocalGet(0U), // n
            I32GtS,
            BrIf(1U), // break outer block
            // total = total + i
            LocalGet(1U),
            LocalGet(2U),
            I32Add,
            LocalSet(1U),
            // i = i + 1
            LocalGet(2U),
            I32Const(1U),
            I32Add,
            LocalSet(2U),
            // continue loop
            Br(0U),
          ]),
        ]),
        // return total
        LocalGet(1U),
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let module_ = @core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [@core.Export::{ name: b"sum_loop", desc: Func(0U) }],
    codes: [code],
  }
  let runtime = @runtime.Runtime::load(module_)
  runtime.run_start()
  // sum_loop(10) = 1+2+...+10 = 55
  let results = runtime.call_compiled(b"sum_loop", [@runtime.Value::I32(10U)])
  assert_eq(results[0], @runtime.Value::I32(55U))
  // sum_loop(0) = 0
  let results0 = runtime.call_compiled(b"sum_loop", [@runtime.Value::I32(0U)])
  assert_eq(results0[0], @runtime.Value::I32(0U))
}
