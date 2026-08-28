// A real block scope destroyed by a pass that mistook it for the
// spelling of `let a = 1, b = 2`.
//
// `{ let v1 = …; let v2 = …; }` and `let v1 = …, v2 = …;` hold the SAME
// statements — the parser represents the multi-declarator form as a
// `Block` — so the difference is not derivable from the contents. It has
// to be recorded by the producer, and it was recorded as "`stmt_positions`
// is empty", which is not a marker but the absence of one: any rewrite
// that rebuilds a block erases it.
//
// Four passes asked "is this a declarator group?" with four independent
// implementations (`inline.mbt`, `symbol_graph.mbt`, `treeshake.mbt`,
// `emit.mbt`) and only the emitter's checked positions at all. Each of
// the other three said, in its own comment, that it mirrored the
// emitter's rule.
//
// The consequence below. `case 1`'s inner block is all-declarations, so
// the predicate said "group" and the pass spliced its bindings into the
// switch's scope — where `default` already declares one. The mangler had
// given them the same short name, correctly, because when IT looked they
// were in different scopes. Result: `let o = …, p = …; … let { … : o }`,
// a duplicate declaration that Node refuses to parse, under
// `--minify --mangle`.
//
// Every case pairs a scope that must survive with a group that must
// still collapse, so the fix cannot be "stop unboxing".

const log: number[] = [];
const bag: Record<string, number> = { alpha: 1, beta: 2 };
const keys = ["alpha"];

let n = 1;

// 1. The switch. Its cases share ONE lexical scope; the braces inside
//    `case 1` are what keep `v1` out of it.
switch (n) {
  case 0:
    break;
  case 1: {
    {
      let v1 = { ...bag, g: (log.push(0), 1) };
      let v2 = (log.push(1), "x");
    }
    break;
  }
  default: {
    const { [keys[0]]: v3 } = bag;
    log.push(v3);
  }
}

// 2. The same shape without a switch: an all-declaration block followed
//    by a redeclaration of one of its names in the enclosing scope.
//    This one is wrong under plain `--bundle --fold`, no mangling — the
//    fold pass had the identical hole.
export function shadowed(): number {
  {
    const x = (log.push(2), 1);
    const y = (log.push(3), 2);
  }
  const x = 3;
  return x;
}

// 3. The control: a REAL multi-declarator group must still collapse to
//    one `let`, and its bindings belong to the enclosing scope.
let p = (log.push(4), 1),
  q = (log.push(5), 2);
export const sum = p + q;

export const report = { trace: log, shadowed: shadowed(), sum };
console.log(JSON.stringify(report));
