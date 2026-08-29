// Seeded generator for the mangle fuzzer.
//
// The shape of the thing is Terser's `ufuzz` by way of
// https://github.com/oxc-project/oxc/pull/25594: a deterministic RNG, a
// fixed mutable surface, bounded loops, a shared call budget, and a
// single observation at the end. What differs is what it aims at.
//
// A general-purpose JS fuzzer looks for compression bugs — a fold that
// changes `ToNumber` semantics, an operand rotation that drops a side
// effect. Those are worth finding, and `--no-mangle` still looks for
// them. But the question that motivated this is narrower and scarier:
// **can the property mangler rename a name that is actually
// observable?** A false positive there is silent. The bundle runs, the
// tests pass, and one `JSON.stringify` somewhere returns `{"a":1}`
// instead of `{"count":1}`.
//
// So the grammar is weighted toward the constructs the safety analysis
// has to reason about, and the observation is weighted toward
// name-revealing operations. Concretely, every one of these appears with
// deliberate frequency:
//
//   * computed-key READS (`holder[k]`) — the analysis cannot predict the
//     key, so it must reserve everything reachable. This is the rule
//     that was backwards once already: reads are fatal, writes are not.
//   * computed-key WRITES and `delete` — must NOT poison anything.
//   * `in`, spread, `Object.keys` / `values` / `entries` / `assign`,
//     `JSON.stringify`, `structuredClone`, `for...in` — each turns a
//     property NAME into a value, so each is a sink.
//   * classes with methods, fields, statics, accessors and `#private`
//     fields — a native method sits on the prototype and is NOT own
//     enumerable, so `Object.keys` cannot see it; a `#private` field is
//     lexically unreachable from outside. Both are places where the
//     analysis is allowed to be aggressive, which is exactly where an
//     off-by-one in the reasoning shows up.
//   * interfaces and type aliases that declare property names — the
//     input to `--reserve-typed-props`.
//   * destructuring with renames and computed keys — a rename site the
//     mangler has to rewrite in two places at once.

import { size } from "./fuzz-ir.mjs";

// ---------------------------------------------------------------
// Deterministic RNG
// ---------------------------------------------------------------

// SplitMix32. Small, seedable from an integer, and good enough that
// nearby seeds produce unrelated programs — which matters because the
// campaign walks seeds consecutively.
function makeRng(seed) {
  let state = (seed ^ 0x9e3779b9) >>> 0;
  return function next() {
    state = (state + 0x9e3779b9) >>> 0;
    let z = state;
    z = ((z ^ (z >>> 16)) * 0x21f0aaad) >>> 0;
    z = ((z ^ (z >>> 15)) * 0x735a2d97) >>> 0;
    return ((z ^ (z >>> 15)) >>> 0) / 0x100000000;
  };
}

// Names the fixed prelude establishes. Kept here so the generator never
// emits a reference to something undeclared.
const NUMERIC_VARS = ["a", "b", "c", "x", "y", "z"];
const OBJ_PROPS = ["p", "q", "r"];
const BAG_PROPS = ["alpha", "beta", "gamma"];

const BIN_OPS = [
  "+", "-", "*", "%", "&", "|", "^", "<<", ">>", ">>>",
  "<", "<=", ">", ">=", "==", "===", "!=", "!==",
];
const LOGICAL_OPS = ["&&", "||", "??"];
const UNARY_OPS = ["+", "-", "!", "~", "void", "typeof"];
const ASSIGN_OPS = ["=", "+=", "-=", "*=", "|=", "^=", "&&=", "||=", "??="];

const PRIMITIVES = [
  "-3", "-1", "0", "1", "2", "3", "10", "42",
  "true", "false", "null", "undefined", "NaN", "Infinity",
  "''", "'x'", "'alpha'", "0.5",
];

export class Generator {
  constructor(seed, options = {}) {
    this.rng = makeRng(seed >>> 0);
    this.seed = seed;
    this.shape = options.shape ?? (this.chance(0.35) ? "export" : "sink");
    this.nextVar = 0;
    this.nextBrake = 0;
    this.nextEffect = 0;
    // Property names this program invented. The observation draws from
    // these, so a rename of one is visible.
    this.ownProps = [];
    this.classNames = [];
    // Instance-reachable and constructor-reachable members, kept apart.
    // A `static` method is NOT on the instance, so `new C().m()` throws
    // "not a function" — in the ORIGINAL program, which made the seed a
    // skip rather than a test. 18 of 120 seeds were being wasted that
    // way. className -> [prop]
    this.instanceMembers = new Map();
    this.staticMembers = new Map();
    this.funcNames = [];
    this.typeNames = [];
    // Reader functions the name-resolution group declared. Exported in
    // the "export" shape so the observation reaches them from outside
    // the module, the same way it reaches the generated classes.
    this.shadowFnNames = [];
  }

  // --- RNG helpers ------------------------------------------------

  chance(p) {
    return this.rng() < p;
  }

  int(min, maxExclusive) {
    return min + Math.floor(this.rng() * (maxExclusive - min));
  }

  pick(choices) {
    return choices[this.int(0, choices.length)];
  }

  freshVar() {
    return `v${this.nextVar++}`;
  }

  freshBrake() {
    return `brake${this.nextBrake++}`;
  }

  freshEffect() {
    return this.nextEffect++;
  }

  // --- Program ----------------------------------------------------

  program() {
    const types = [];
    const decls = [];

    // Interfaces / aliases first: they contribute property names that
    // `--reserve-typed-props` is supposed to protect, and a type name
    // the later declarations can annotate with.
    const ifaceCount = this.int(0, 3);
    for (let i = 0; i < ifaceCount; i++) {
      const name = `I${i}`;
      const fields = [];
      const fieldCount = this.int(1, 4);
      for (let f = 0; f < fieldCount; f++) {
        const prop = `f${i}${f}`;
        this.ownProps.push(prop);
        fields.push({ name: prop, type: this.pick(["number", "string", "boolean"]) });
      }
      types.push({ k: "iface", name, fields });
      this.typeNames.push(name);
    }
    if (this.chance(0.4)) {
      const name = `A${types.length}`;
      types.push({
        k: "alias",
        name,
        body: this.pick([
          "Record<string, number>",
          "{ [key: string]: number }",
          "number[]",
          "string | number",
        ]),
      });
      this.typeNames.push(name);
    }

    // Classes. Two at most: more adds compile time without adding
    // reasoning the analysis has not already been asked for.
    const classCount = this.int(0, 3);
    for (let i = 0; i < classCount; i++) {
      decls.push(this.classDecl(`C${i}`));
    }
    // One long-lived instance per class that has a getter, so a getter
    // read can be spelled off a BINDING.
    //
    // `new C().g` was never affected by the bug this exists to catch:
    // `is_pure_value(New(...))` is false, so the read was impure by way
    // of its receiver and nothing dropped it. The bug needed a receiver
    // that IS pure — a plain variable — which is also how real code
    // reads a getter. Emitting only the `new` form is why 300 seeds
    // reported nothing with the bug present.
    this.getterInstances = [];
    for (const decl of decls) {
      if (decl.k !== "class") continue;
      const getter = `${decl.name.toLowerCase()}g`;
      if (!(decl.members ?? []).some((m) => m.k === "getter" && m.name === getter)) {
        continue;
      }
      const inst = `${decl.name.toLowerCase()}Inst`;
      decls.push({ k: "raw", text: `const ${inst} = new ${decl.name}();\n` });
      this.getterInstances.push({ inst, getter });
    }

    // Functions, with the shared call budget guard printed for them.
    const funcCount = this.int(1, 3);
    for (let i = 0; i < funcCount; i++) {
      const name = `f${i}`;
      this.funcNames.push(name);
      decls.push({
        k: "func",
        name,
        params: ["p0", "p1"],
        // Announcing the invocation is what makes a DROPPED call
        // visible, but it also makes the function impure, which stops
        // the DCE from ever removing it. Both paths matter, so only
        // some functions announce themselves.
        entryId: this.chance(0.7) ? this.freshEffect() : undefined,
        body: this.statements(this.int(1, 3), 2, { inFunction: true, loopDepth: 0 }),
      });
    }
    // The last function always returns something, so calls to it are
    // value-producing wherever the expression grammar uses them.
    for (const decl of decls) {
      if (decl.k === "func") {
        decl.body.push({ k: "return", expr: this.expr(2) });
      }
    }

    // The name-resolution group. One raw decl per shape so the shrinker
    // can drop the ones that are not implicated.
    const shadowReaders = [];
    const groupCount = this.int(0, 3);
    for (let i = 0; i < groupCount; i++) {
      const group = this.shadowGroup(i);
      decls.push({ k: "raw", text: group.text });
      for (const reader of group.readers) shadowReaders.push(reader);
      for (const fn of group.names) this.shadowFnNames.push(fn);
    }

    const body = this.statements(this.int(3, 7), 3, { inFunction: false, loopDepth: 0 });

    const program = {
      seed: this.seed,
      shape: this.shape,
      types,
      decls,
      body,
      observe: [],
      exports: [],
    };
    program.observe = this.observations();
    // The group's readers have to be OBSERVED or the whole thing is dead
    // code: treeshake deletes it, and a pass that would have rewritten it
    // wrongly never gets the chance. `raw` for the same reason the decls
    // are — these are calls with a fixed shape, not grammar.
    for (const reader of shadowReaders) {
      program.observe.push({ k: "raw", text: reader });
    }
    if (this.shape === "export") program.exports = this.exportList(decls);
    return program;
  }

  /// The name-resolution group: declarations the optimizer rewrites BY
  /// NAME, each read once through the name it declares and once through a
  /// scope that re-binds that name.
  ///
  /// The rest of this generator aims at the property mangler. These six
  /// passes are a different question — they key a bundle-wide table on an
  /// identifier and substitute at every mention of it — and the grammar
  /// had no shape that reached any of them, nor any shadowing at all:
  /// `freshVar` hands out `v0`, `v1`, … so two bindings never share a
  /// name. Five of the six were wrong for exactly that reason, and all
  /// five were found by reading their source rather than by fuzzing.
  ///
  /// Each shape gets:
  ///
  ///   * an outer declaration the pass wants to rewrite;
  ///   * `shadowed`, a reader whose scope re-binds the name, which must
  ///     read the INNER binding;
  ///   * `direct`, a reader that does not shadow, which must still be
  ///     optimized — otherwise "narrow the table" and "switch the pass
  ///     off" would look the same from out here.
  ///
  /// The shadowing forms rotate over the four that behave differently:
  /// an inner `const` (a block declares it), a parameter (no block
  /// declares it — the case a block-level check cannot see), a `catch`
  /// binding, and a loop variable.
  shadowGroup(index) {
    const tag = `s${index}`;
    const shadow = this.int(0, 4);
    /// Wrap `body` in a scope that re-binds `name` with `init`.
    const shadowed = (name, init, body) => {
      switch (shadow) {
        case 0:
          return `function ${tag}Shadowed() {\n  const ${name} = ${init};\n  return ${body};\n}\n`;
        case 1:
          return `function ${tag}Shadowed(${name}: any) {\n  return ${body};\n}\n`;
        case 2:
          return (
            `function ${tag}Shadowed() {\n` +
            `  try { throw ${init}; } catch (${name}) { return ${body}; }\n` +
            `}\n`
          );
        default:
          return (
            `function ${tag}Shadowed() {\n` +
            `  for (const ${name} of [${init}]) { return ${body}; }\n` +
            `  return 0;\n` +
            `}\n`
          );
      }
    };
    /// The argument the shadowed reader needs when the shadow is a
    /// parameter, and nothing otherwise.
    const shadowArg = (init) => (shadow === 1 ? init : "");

    switch (this.int(0, 6)) {
      // as_const_inline: `NAME[i]` folds to the element.
      case 0: {
        const name = `${tag}Arr`;
        return {
          text:
            `const ${name} = ['out0', 'out1'];\n` +
            shadowed(name, `['in0', 'in1']`, `${name}[0]`) +
            `function ${tag}Direct() { return ${name}[1]; }\n`,
          readers: [`${tag}Shadowed(${shadowArg(`['in0', 'in1']`)})`, `${tag}Direct()`],
          names: [`${tag}Shadowed`, `${tag}Direct`],
        };
      }
      // as_const_inline, object form: `NAME.k` folds to the value.
      case 1: {
        const name = `${tag}Obj`;
        return {
          text:
            `const ${name} = { k: 11 };\n` +
            shadowed(name, `{ k: 99 }`, `${name}.k`) +
            `function ${tag}Direct() { return ${name}.k; }\n`,
          readers: [`${tag}Shadowed(${shadowArg(`{ k: 99 }`)})`, `${tag}Direct()`],
          names: [`${tag}Shadowed`, `${tag}Direct`],
        };
      }
      // const_scalar_inline: the literal is substituted at every read.
      case 2: {
        const name = `${tag}K`;
        return {
          text:
            `const ${name} = 5;\n` +
            shadowed(name, `9`, `${name} * 2`) +
            `function ${tag}Direct() { return ${name} * 2; }\n`,
          readers: [`${tag}Shadowed(${shadowArg("9")})`, `${tag}Direct()`],
          names: [`${tag}Shadowed`, `${tag}Direct`],
        };
      }
      // const_enum_inline: `E.M` folds to the member's value. This one
      // is rewritten under plain `--bundle`, before any optimization
      // flag, so it is the shape most worth generating.
      case 3: {
        const name = `${tag}E`;
        return {
          text:
            `const enum ${name} { M = 3 }\n` +
            shadowed(name, `{ M: 77 }`, `${name}.M`) +
            `function ${tag}Direct() { return ${name}.M; }\n`,
          readers: [`${tag}Shadowed(${shadowArg("{ M: 77 }")})`, `${tag}Direct()`],
          names: [`${tag}Shadowed`, `${tag}Direct`],
        };
      }
      // predicate_inline: a `x is T` guard's body is substituted at the
      // call site. The shadow has to be CALLABLE, so the parameter form
      // takes a function and the others declare one.
      case 4: {
        const name = `${tag}Guard`;
        const inner =
          shadow === 1
            ? `function ${tag}Shadowed(${name}: (n: number) => boolean) { return ${name}(4); }\n`
            : shadow === 0
              ? `function ${tag}Shadowed() {\n  const ${name} = (n: number) => n === 4;\n  return ${name}(4);\n}\n`
              : shadow === 2
                ? `function ${tag}Shadowed() {\n  try { throw (n: number) => n === 4; } catch (${name}: any) { return ${name}(4); }\n}\n`
                : `function ${tag}Shadowed() {\n  for (const ${name} of [(n: number) => n === 4]) { return ${name}(4); }\n  return false;\n}\n`;
        return {
          text:
            `function ${name}(v: number): v is number { return !v; }\n` +
            inner +
            `function ${tag}Direct() { return ${name}(0); }\n`,
          readers: [
            `${tag}Shadowed(${shadow === 1 ? `(n: number) => n === 4` : ""})`,
            `${tag}Direct()`,
          ],
          names: [`${tag}Shadowed`, `${tag}Direct`],
        };
      }
      // switch_fold: a literal-union dispatcher is specialized per
      // argument. Same callability requirement as the guard.
      default: {
        const name = `${tag}Dispatch`;
        const inner =
          shadow === 1
            ? `function ${tag}Shadowed(${name}: (k: 'a') => number) { return ${name}('a'); }\n`
            : shadow === 0
              ? `function ${tag}Shadowed() {\n  const ${name} = (k: 'a') => 42;\n  return ${name}('a');\n}\n`
              : shadow === 2
                ? `function ${tag}Shadowed() {\n  try { throw (k: 'a') => 42; } catch (${name}: any) { return ${name}('a'); }\n}\n`
                : `function ${tag}Shadowed() {\n  for (const ${name} of [(k: 'a') => 42]) { return ${name}('a'); }\n  return 0;\n}\n`;
        return {
          text:
            `function ${name}(k: 'a' | 'b'): number {\n` +
            `  switch (k) { case 'a': return 1; case 'b': return 2; }\n` +
            `}\n` +
            inner +
            `function ${tag}Direct() { return ${name}('b'); }\n`,
          readers: [
            `${tag}Shadowed(${shadow === 1 ? `(k: 'a') => 42` : ""})`,
            `${tag}Direct()`,
          ],
          names: [`${tag}Shadowed`, `${tag}Direct`],
        };
      }
    }
  }

  /// What the module exports. Only relevant to the "export" shape, where
  /// these names are the package ABI and must survive mangling.
  exportList(decls) {
    const candidates = decls.filter((d) => d.k === "class" || d.k === "func").map((d) => d.name);
    if (candidates.length === 0) return this.shadowFnNames.slice();
    const count = this.int(1, candidates.length + 1);
    // Every group reader is exported unconditionally. In the "export"
    // shape the epilogue is just `export const __trace = trace`, so a
    // reader that is not exported is unreachable and gets deleted —
    // which would make the group generate itself and prove nothing.
    return [...candidates.slice(0, count), ...this.shadowFnNames];
  }

  classDecl(name) {
    this.classNames.push(name);
    const members = [];
    const instance = [];
    const statics = [];
    this.instanceMembers.set(name, instance);
    this.staticMembers.set(name, statics);
    const fieldCount = this.int(1, 3);
    for (let i = 0; i < fieldCount; i++) {
      const prop = `${name.toLowerCase()}f${i}`;
      this.ownProps.push(prop);
      members.push({
        k: "field",
        name: prop,
        init: { k: "lit", value: this.pick(["0", "1", "'s'", "true"]) },
        static: false,
      });
      instance.push({ prop, callable: false });
    }
    // A `#private` field is unreachable from outside the class body by
    // construction, so it is the one member a mangler may always rename.
    if (this.chance(0.5)) {
      members.push({ k: "private", name: "secret", init: { k: "lit", value: "7" } });
    }
    const methodCount = this.int(1, 3);
    for (let i = 0; i < methodCount; i++) {
      const prop = `${name.toLowerCase()}m${i}`;
      this.ownProps.push(prop);
      const isStatic = this.chance(0.25);
      members.push({
        k: "method",
        name: prop,
        params: ["q0"],
        entryId: this.chance(0.7) ? this.freshEffect() : undefined,
        body: [{ k: "return", expr: this.expr(1) }],
        static: isStatic,
      });
      (isStatic ? statics : instance).push({ prop, callable: true });
    }
    if (this.chance(0.3)) {
      const prop = `${name.toLowerCase()}g`;
      this.ownProps.push(prop);
      members.push({
        k: "getter",
        name: prop,
        // A getter that announces itself is how "the getter never ran"
        // becomes visible, and that is the ONLY thing a getter is here
        // to detect — so it always announces. It used to do so 70% of
        // the time, and a silent getter is indistinguishable from a
        // field: the read can be dropped and nothing in the observation
        // moves. `is_pure_value` called a property read pure whenever
        // its receiver was, so four fold rules dropped getter bodies
        // outright, and 8000 comparisons never reported it.
        entryId: this.freshEffect(),
        body: [{ k: "return", expr: this.expr(1) }],
        static: false,
      });
      instance.push({ prop, callable: false });
    }
    return { k: "class", name, members };
  }

  // --- Observation ------------------------------------------------

  /// What the program prints. This is the whole comparison, so it has to
  /// include the name-revealing forms: a value-only observation would
  /// pass no matter how the properties were renamed.
  observations() {
    const out = [
      { k: "var", name: "a" },
      { k: "var", name: "b" },
      { k: "var", name: "c" },
      { k: "var", name: "trace" },
      { k: "var", name: "callBudget" },
      // Names as values. If the mangler renames `alpha` and this is
      // reachable, the diff is immediate.
      { k: "sink", sink: "JSON.stringify", args: [{ k: "var", name: "bag" }] },
      {
        k: "call",
        callee: {
          k: "member",
          obj: { k: "sink", sink: "Object.keys", args: [{ k: "var", name: "obj" }] },
          prop: "sort",
        },
        args: [],
      },
    ];
    // A live instance's own enumerable keys. Class METHODS are on the
    // prototype and non-enumerable, so they must NOT show up here — this
    // observation is what distinguishes "renamed a method" (invisible to
    // Object.keys) from "renamed a field" (visible).
    for (const className of this.classNames) {
      out.push({
        k: "sink",
        sink: "JSON.stringify",
        args: [{ k: "new", callee: { k: "var", name: className }, args: [] }],
      });
      if (this.chance(0.5)) {
        out.push({
          k: "call",
          callee: {
            k: "member",
            obj: {
              k: "sink",
              sink: "Object.keys",
              args: [{ k: "new", callee: { k: "var", name: className }, args: [] }],
            },
            prop: "sort",
          },
          args: [],
        });
      }
    }
    if (this.chance(0.5)) {
      out.push({
        k: "sink",
        sink: "JSON.stringify",
        args: [{ k: "object", props: [{ key: "wrapped", value: { k: "var", name: "obj" } }] }],
      });
    }
    return out;
  }

  // --- Statements -------------------------------------------------

  statements(count, depth, ctx) {
    const out = [];
    for (let i = 0; i < count; i++) out.push(this.stmt(depth, ctx));
    return out;
  }

  stmt(depth, ctx) {
    if (depth <= 0) return this.simpleStmt();
    switch (this.int(0, 17)) {
      case 0:
      case 1:
      case 2:
      case 3:
        return this.simpleStmt();
      case 4:
        return {
          k: "if",
          test: this.expr(2),
          then: this.statements(this.int(1, 3), depth - 1, ctx),
          else_: this.chance(0.5) ? this.statements(1, depth - 1, ctx) : null,
        };
      case 5:
        return { k: "block", body: this.statements(this.int(1, 3), depth - 1, ctx) };
      case 6:
        return {
          k: "while",
          brake: this.freshBrake(),
          test: this.expr(2),
          body: this.statements(this.int(1, 3), depth - 1, { ...ctx, loopDepth: ctx.loopDepth + 1 }),
        };
      case 7:
        return {
          k: "for",
          brake: this.freshBrake(),
          test: this.expr(2),
          body: this.statements(this.int(1, 3), depth - 1, { ...ctx, loopDepth: ctx.loopDepth + 1 }),
        };
      case 8:
        return {
          k: "dowhile",
          brake: this.freshBrake(),
          test: this.expr(2),
          body: this.statements(1, depth - 1, { ...ctx, loopDepth: ctx.loopDepth + 1 }),
        };
      // `for...in` enumerates own enumerable KEYS. A renamed field
      // changes the iteration, so this is a sink in loop clothing.
      case 9: {
        const name = this.freshVar();
        return {
          k: "forin",
          name,
          object: this.pick([
            { k: "var", name: "bag" },
            { k: "var", name: "obj" },
          ]),
          body: [
            {
              k: "expr",
              expr: {
                k: "assign",
                op: "+=",
                target: { k: "var", name: "c" },
                value: {
                  k: "member",
                  obj: { k: "call", callee: { k: "var", name: "String" }, args: [{ k: "var", name }] },
                  prop: "length",
                },
              },
            },
          ],
        };
      }
      case 10: {
        const name = this.freshVar();
        return {
          k: "forof",
          name,
          object: { k: "var", name: "arr" },
          body: this.statements(1, depth - 1, { ...ctx, loopDepth: ctx.loopDepth + 1 }),
        };
      }
      case 11:
        return {
          k: "switch",
          disc: this.expr(2),
          cases: [
            { test: { k: "lit", value: "0" }, body: this.statements(1, depth - 1, ctx) },
            { test: { k: "lit", value: "1" }, body: this.statements(1, depth - 1, ctx) },
            { test: null, body: this.statements(1, depth - 1, ctx) },
          ],
        };
      case 12:
        return {
          k: "try",
          test: this.expr(1),
          thrown: this.expr(1),
          body: this.statements(1, depth - 1, ctx),
          handler: this.statements(1, depth - 1, ctx),
          traceId: this.freshEffect(),
        };
      case 13:
        if (ctx.inFunction) return { k: "return", expr: this.expr(2) };
        return this.simpleStmt();
      case 14:
        if (ctx.loopDepth > 0) return this.chance(0.5) ? { k: "break" } : { k: "continue" };
        return this.simpleStmt();
      // THE shape that broke the minified TypeScript compiler: a call
      // whose result is bound to a variable read only in a position that
      // is not always evaluated. The single-use inliner deleted the
      // binding and moved the call into the `?` branch, and the branch
      // was not taken, so the call never happened.
      //
      // The value comparison could not see it — nobody reads the value.
      // The trace can: the callee announces its own invocation.
      case 15:
        return this.effectBindStmt(depth, ctx);
      // A computed-key DELETE. Harmless to the analysis — it observes no
      // name — and the fuzzer's job is to keep proving that, because the
      // conservative reading of `delete` reserved everything.
      default:
        return {
          k: "delete",
          target: {
            k: "index",
            obj: { k: "var", name: "obj" },
            index: { k: "lit", value: `'${this.pick(OBJ_PROPS)}'` },
          },
        };
    }
  }

  /// `let v = <effectful call>;` followed by a use of `v` that is only
  /// SOMETIMES evaluated.
  ///
  /// Three guard shapes, because a minifier's reasoning differs across
  /// them: a ternary branch, the right of a `&&`, and an `if` body. The
  /// condition is built from the prelude's mutable counters so it is not
  /// a literal the folder can settle — and it is written to be false
  /// most of the time, since a guard that is always taken proves
  /// nothing.
  effectBindStmt(depth, ctx) {
    const name = this.freshVar();
    const call = {
      k: "call",
      callee: { k: "var", name: this.pick(this.funcNames.length ? this.funcNames : ["f0"]) },
      args: [this.expr(1), this.expr(1)],
    };
    const test = {
      k: "bin",
      op: this.pick([">", "<", "===", "!=="]),
      left: { k: "var", name: this.pick(NUMERIC_VARS) },
      right: { k: "lit", value: String(this.int(0, 200)) },
    };
    const use = { k: "var", name };
    let guarded;
    switch (this.int(0, 3)) {
      case 0:
        guarded = {
          k: "expr",
          expr: {
            k: "assign",
            op: "=",
            target: { k: "member", obj: { k: "var", name: "obj" }, prop: this.pick(OBJ_PROPS) },
            value: { k: "cond", test, then: use, else_: { k: "lit", value: "0" } },
          },
        };
        break;
      case 1:
        guarded = {
          k: "expr",
          expr: {
            k: "assign",
            op: "=",
            target: { k: "var", name: "c" },
            value: { k: "logical", op: "&&", left: test, right: use },
          },
        };
        break;
      default:
        guarded = {
          k: "if",
          test,
          then: [
            {
              k: "expr",
              expr: { k: "assign", op: "=", target: { k: "var", name: "c" }, value: use },
            },
          ],
        };
        break;
    }
    // A block, because that is where the real case lived: inside a
    // function body, where the declaration and its single use are
    // adjacent statements in the same scope.
    return { k: "block", body: [{ k: "decl", kind: "let", name, init: call }, guarded] };
  }

  /// A property read whose VALUE IS THROWN AWAY.
  ///
  /// This is the position four fold rules dropped a getter's body from,
  /// and the generator could not reach it. `expr(3)` almost never
  /// bottoms out at a bare member read — it wraps one in a binary op, an
  /// assignment or a call, all of which USE the value, and a used value
  /// keeps the read alive. 300 seeds with the bug present reported
  /// nothing.
  ///
  /// So the discarded position is emitted directly, in the four
  /// spellings that were wrong: the bare statement, `void EXPR`, the
  /// left of a discarded comma, and an array literal whose `.length` is
  /// taken. `expr(3)` covers reads whose value is used; this covers the
  /// reads whose value is not, and only the second kind is droppable.
  discardedReadStmt() {
    // Prefer a getter: it is the only member whose read has an effect,
    // so it is the only one that can show the read was dropped. Falls
    // back to the prelude's plain object, which at least exercises the
    // rule on a shape whose purity really is provable.
    let read = { k: "member", obj: { k: "var", name: "bag" }, prop: this.pick(BAG_PROPS) };
    const instances = this.getterInstances ?? [];
    if (instances.length > 0) {
      const { inst, getter } = this.pick(instances);
      read = { k: "member", obj: { k: "var", name: inst }, prop: getter };
    }
    switch (this.int(0, 4)) {
      case 0:
        return { k: "expr", expr: read };
      case 1:
        return { k: "expr", expr: { k: "unary", op: "void", arg: read } };
      case 2:
        return {
          k: "expr",
          expr: { k: "seq", left: read, right: { k: "lit", value: "9" } },
        };
      default:
        return {
          k: "decl",
          kind: "let",
          name: this.freshVar(),
          init: {
            k: "member",
            obj: { k: "array", items: [read, { k: "lit", value: "1" }] },
            prop: "length",
          },
        };
    }
  }

  simpleStmt() {
    const roll = this.int(0, 11);
    if (roll === 10) {
      return this.discardedReadStmt();
    }
    if (roll < 2) {
      const name = this.freshVar();
      return { k: "decl", kind: "let", name, init: this.expr(2) };
    }
    // Destructuring with a rename, and sometimes a computed key. Both
    // are rename sites the mangler has to rewrite consistently — the
    // computed-key form in an object pattern was a real bug once.
    if (roll === 2) {
      const prop = this.pick(BAG_PROPS);
      const local = this.freshVar();
      return {
        k: "destructure",
        pattern: this.chance(0.5) ? `{ ${prop}: ${local} }` : `{ ${prop}: ${local} = 9 }`,
        init: { k: "var", name: "bag" },
      };
    }
    if (roll === 3) {
      const local = this.freshVar();
      return {
        k: "destructure",
        pattern: `{ [keys[0]]: ${local} }`,
        init: { k: "var", name: "bag" },
      };
    }
    // A computed-key WRITE. Distinct from a read: writing under an
    // unpredictable key stores a value, it does not reveal a name.
    if (roll === 4) {
      return {
        k: "expr",
        expr: {
          k: "assign",
          op: "=",
          target: {
            k: "index",
            obj: { k: "var", name: "obj" },
            index: this.chance(0.5)
              ? { k: "index", obj: { k: "var", name: "keys" }, index: { k: "lit", value: "0" } }
              : { k: "lit", value: `'${this.pick(OBJ_PROPS)}'` },
          },
          value: this.expr(1),
        },
      };
    }
    return { k: "expr", expr: this.expr(3) };
  }

  // --- Expressions ------------------------------------------------

  expr(depth) {
    if (depth <= 0) return this.primary();
    switch (this.int(0, 20)) {
      case 0:
      case 1:
      case 2:
        return this.primary();
      case 3:
        return { k: "bin", op: this.pick(BIN_OPS), left: this.expr(depth - 1), right: this.expr(depth - 1) };
      case 4:
        return {
          k: "logical",
          op: this.pick(LOGICAL_OPS),
          left: this.expr(depth - 1),
          right: this.expr(depth - 1),
        };
      case 5:
        return {
          k: "cond",
          test: this.expr(depth - 1),
          then: this.expr(depth - 1),
          else_: this.expr(depth - 1),
        };
      case 6:
        return { k: "unary", op: this.pick(UNARY_OPS), arg: this.expr(depth - 1) };
      case 7:
        return {
          k: "assign",
          op: this.pick(ASSIGN_OPS),
          target: this.mutableTarget(),
          value: this.expr(depth - 1),
        };
      case 8:
        return {
          k: "update",
          op: this.chance(0.5) ? "++" : "--",
          target: { k: "var", name: this.pick(NUMERIC_VARS) },
          prefix: this.chance(0.5),
        };
      // An ordered side-effect marker. Compression that reorders or
      // drops an effect shows up in `trace` even when the values agree.
      case 9:
        return { k: "trace", id: this.freshEffect(), value: this.expr(depth - 1) };
      case 10:
        return { k: "seq", left: this.expr(depth - 1), right: this.expr(depth - 1) };
      // THE case that matters: a computed-key READ under a key the
      // analysis cannot predict. Everything reachable from `bag` has to
      // stay reserved, because this expression can observe any of it.
      case 11:
        return {
          k: "index",
          obj: { k: "var", name: this.chance(0.5) ? "bag" : "obj" },
          index: this.pick([
            { k: "index", obj: { k: "var", name: "keys" }, index: { k: "lit", value: "0" } },
            { k: "index", obj: { k: "var", name: "keys" }, index: { k: "lit", value: "1" } },
            { k: "var", name: "dynamicKey" },
            { k: "lit", value: `'${this.pick(BAG_PROPS)}'` },
          ]),
          optional: this.chance(0.2),
        };
      case 12:
        return {
          k: "sink",
          sink: this.pick([
            "Object.keys",
            "Object.values",
            "Object.entries",
            "JSON.stringify",
            "structuredClone",
          ]),
          args: [this.pick([{ k: "var", name: "bag" }, { k: "var", name: "obj" }])],
        };
      // Spread copies every own enumerable property, names included.
      case 13:
        return {
          k: "object",
          props: [
            { spread: true, value: { k: "var", name: this.chance(0.5) ? "bag" : "obj" } },
            { key: this.freshProp(), value: this.expr(depth - 1) },
          ],
        };
      case 14:
        return {
          k: "bin",
          op: "in",
          left: { k: "lit", value: `'${this.pick(BAG_PROPS)}'` },
          right: { k: "var", name: "bag" },
        };
      case 15: {
        if (this.funcNames.length === 0) return this.primary();
        return {
          k: "call",
          callee: { k: "var", name: this.pick(this.funcNames) },
          args: [this.primary(), this.primary()],
        };
      }
      case 16: {
        if (this.classNames.length === 0) return this.primary();
        const className = this.pick(this.classNames);
        // Reach a static through the constructor and everything else
        // through an instance — the distinction the class body drew.
        const onStatic = this.chance(0.3);
        const members = (onStatic ? this.staticMembers : this.instanceMembers).get(className) ?? [];
        const receiver = onStatic
          ? { k: "var", name: className }
          : { k: "new", callee: { k: "var", name: className }, args: [] };
        // With no member to read, the receiver itself is the value —
        // and a BARE CONSTRUCTOR is the one value in this grammar whose
        // string coercion is its own source text. `bag.gamma += C1`
        // makes a string containing `class C1 { c1f0 = true; }`,
        // minification legitimately reformats that, and the harness
        // reported a mismatch about nothing. (`encode` already refuses
        // to record a function's source for exactly this reason; by the
        // time `+=` has run it is an ordinary string and the observer
        // cannot tell.) An instance coerces to `[object Object]`, which
        // is stable, so fall back to that. Class values still reach
        // sinks — through `new C()`, and through the exported class in
        // the `export` shape.
        if (members.length === 0) {
          return { k: "new", callee: { k: "var", name: className }, args: [] };
        }
        const member = this.pick(members);
        const target = { k: "member", obj: receiver, prop: member.prop };
        // A method reference has to be called to produce a value.
        return member.callable
          ? { k: "call", callee: target, args: [{ k: "lit", value: "1" }] }
          : target;
      }
      case 17: {
        const key = this.freshProp();
        return {
          k: "member",
          obj: { k: "object", props: [{ key, value: this.expr(depth - 1) }] },
          prop: key,
        };
      }
      case 18:
        return {
          k: "template",
          quasis: ["k", ""],
          exprs: [this.expr(depth - 1)],
        };
      default:
        return {
          k: "member",
          obj: { k: "array", items: [this.expr(depth - 1), this.expr(depth - 1)] },
          prop: "length",
        };
    }
  }

  freshProp() {
    const prop = `g${this.ownProps.length}`;
    this.ownProps.push(prop);
    return prop;
  }

  primary() {
    if (this.chance(0.55)) return { k: "lit", value: this.pick(PRIMITIVES) };
    const roll = this.int(0, 5);
    if (roll === 0) return { k: "var", name: this.pick(NUMERIC_VARS) };
    if (roll === 1) return { k: "member", obj: { k: "var", name: "obj" }, prop: this.pick(OBJ_PROPS) };
    if (roll === 2) return { k: "member", obj: { k: "var", name: "bag" }, prop: this.pick(BAG_PROPS) };
    if (roll === 3) {
      return {
        k: "index",
        obj: { k: "var", name: "arr" },
        index: { k: "lit", value: String(this.int(0, 3)) },
      };
    }
    return { k: "var", name: this.pick(NUMERIC_VARS) };
  }

  mutableTarget() {
    const roll = this.int(0, 4);
    if (roll === 0) return { k: "var", name: this.pick(NUMERIC_VARS) };
    if (roll === 1) return { k: "member", obj: { k: "var", name: "obj" }, prop: this.pick(OBJ_PROPS) };
    if (roll === 2) return { k: "member", obj: { k: "var", name: "bag" }, prop: this.pick(BAG_PROPS) };
    return {
      k: "index",
      obj: { k: "var", name: "arr" },
      index: { k: "lit", value: String(this.int(0, 3)) },
    };
  }
}

/// Generate the IR for one seed. Deterministic: the same seed and the
/// same generator version always produce the same tree.
export function generate(seed, options = {}) {
  const program = new Generator(seed, options).program();
  program.nodeCount = size(program);
  return program;
}
