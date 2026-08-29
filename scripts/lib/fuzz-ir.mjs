// The intermediate representation the mangle fuzzer generates, prints,
// and shrinks.
//
// Why an IR at all. The fuzzer this is modelled on
// (https://github.com/oxc-project/oxc/pull/25594, itself modelled on
// Terser's `ufuzz`) builds source text directly from a seeded RNG. That
// is enough to FIND a miscompilation and useless for explaining one: the
// only handle on a failure is its seed, so the artifact is a
// hundred-line program where four lines matter, and reducing it is a
// person's afternoon. Every generated construct here is a plain JSON
// node instead, which buys three things:
//
//   * shrinking — `shrinkCandidates` proposes smaller trees, and the
//     campaign keeps whichever ones still fail (see `fuzz-shrink.mjs`)
//   * a stable artifact — the failing tree is written next to the
//     source, so a regression test can be generated from it without
//     re-running the seed under the same generator version
//   * printing decisions in one place — the same tree can be printed as
//     the module under test and as the observation epilogue
//
// The IR is deliberately not a TypeScript AST. It carries only what the
// generator can produce, which is the subset that stresses the property
// mangler's proof obligations.

// ---------------------------------------------------------------
// Node shapes
// ---------------------------------------------------------------
//
// Expressions
//   { k: "lit",      value }                     // printed verbatim
//   { k: "var",      name }
//   { k: "this" }
//   { k: "member",   obj, prop, optional? }      // o.p / o?.p
//   { k: "index",    obj, index, optional? }     // o[e] / o?.[e]
//   { k: "bin",      op, left, right }
//   { k: "logical",  op, left, right }
//   { k: "cond",     test, then, else_ }
//   { k: "unary",    op, arg }
//   { k: "assign",   op, target, value }         // target is member/index/var
//   { k: "update",   op, target, prefix }
//   { k: "call",     callee, args }
//   { k: "new",      callee, args }
//   { k: "object",   props: [{ key, value, computed?, kind? }] }
//   { k: "array",    items }
//   { k: "spread",   arg }                       // only inside object/array/args
//   { k: "template", quasis, exprs }
//   { k: "seq",      left, right }
//   { k: "trace",    id, value }                 // (trace.push(id), value)
//   { k: "sink",     sink, args }                // Object.keys(...) etc.
//   { k: "arrow",    params, body }              // body is an expression
//
// Statements
//   { k: "expr",     expr }
//   { k: "decl",     kind, name, init, type? }
//   { k: "destructure", pattern, init }
//   { k: "block",    body }
//   { k: "if",       test, then, else_? }
//   { k: "while",    brake, test, body }
//   { k: "dowhile",  brake, test, body }
//   { k: "for",      brake, test, body }
//   { k: "forin",    name, object, body }
//   { k: "forof",    name, object, body }
//   { k: "switch",   disc, cases: [{ test?, body }] }
//   { k: "try",      test, thrown, body, handler, traceId }
//   { k: "return",   expr? }
//   { k: "break" } | { k: "continue" }
//   { k: "delete",   target }
//
// Declarations (program level)
//   { k: "func",     name, params, body, ret? }
//   { k: "class",    name, members, brandField? }
//   { k: "iface",    name, fields }
//   { k: "alias",    name, body }

// ---------------------------------------------------------------
// Printing
// ---------------------------------------------------------------

const INDENT = "  ";

function pad(depth) {
  return INDENT.repeat(depth);
}

/// Property keys the generator invents are always identifier-safe, so
/// this only has to decide between `x.p` and `x["p"]` for the computed
/// forms the IR marks explicitly.
function isIdentName(name) {
  return /^[A-Za-z_$][\w$]*$/.test(name);
}

export function printExpr(node) {
  switch (node.k) {
    // Verbatim expression text; see the `raw` declaration arm.
    case "raw":
      return node.text;
    case "lit":
      return node.value;
    case "var":
      return node.name;
    case "this":
      return "this";
    case "member":
      return `${printExpr(node.obj)}${node.optional ? "?." : "."}${node.prop}`;
    case "index":
      return `${printExpr(node.obj)}${node.optional ? "?." : ""}[${printExpr(node.index)}]`;
    case "bin":
      return `(${printExpr(node.left)} ${node.op} ${printExpr(node.right)})`;
    case "logical":
      return `(${printExpr(node.left)} ${node.op} ${printExpr(node.right)})`;
    case "cond":
      return `(${printExpr(node.test)} ? ${printExpr(node.then)} : ${printExpr(node.else_)})`;
    case "unary":
      // `void`, `typeof` and `delete` need the space; the symbol
      // operators do not but a space never changes the parse.
      return `(${node.op} ${printExpr(node.arg)})`;
    case "assign":
      return `(${printExpr(node.target)} ${node.op} ${printExpr(node.value)})`;
    case "update":
      return node.prefix
        ? `(${node.op}${printExpr(node.target)})`
        : `(${printExpr(node.target)}${node.op})`;
    case "call":
      return `${printExpr(node.callee)}(${node.args.map(printExpr).join(", ")})`;
    case "new":
      return `new ${printExpr(node.callee)}(${node.args.map(printExpr).join(", ")})`;
    case "object":
      return `{ ${node.props.map(printProp).join(", ")} }`;
    case "array":
      return `[${node.items.map(printExpr).join(", ")}]`;
    case "spread":
      return `...${printExpr(node.arg)}`;
    case "template":
      return printTemplate(node);
    case "seq":
      return `(${printExpr(node.left)}, ${printExpr(node.right)})`;
    case "trace":
      return `(trace.push(${node.id}), ${printExpr(node.value)})`;
    case "sink":
      return `${node.sink}(${node.args.map(printExpr).join(", ")})`;
    case "arrow":
      return `((${node.params.join(", ")}) => ${printExpr(node.body)})`;
    default:
      throw new Error(`fuzz-ir: cannot print expression ${node.k}`);
  }
}

function printProp(prop) {
  if (prop.kind === "get") return `get ${prop.key}() { return ${printExpr(prop.value)}; }`;
  if (prop.computed) return `[${printExpr(prop.keyExpr)}]: ${printExpr(prop.value)}`;
  if (prop.k === "spread" || prop.spread) return `...${printExpr(prop.value)}`;
  const key = isIdentName(prop.key) ? prop.key : JSON.stringify(prop.key);
  return `${key}: ${printExpr(prop.value)}`;
}

function printTemplate(node) {
  let out = "`";
  for (let i = 0; i < node.quasis.length; i++) {
    out += node.quasis[i];
    if (i < node.exprs.length) out += `\${${printExpr(node.exprs[i])}}`;
  }
  return `${out}\``;
}

export function printStmt(node, depth = 0) {
  const p = pad(depth);
  switch (node.k) {
    case "expr": {
      const text = printExpr(node.expr);
      // At statement position a leading `{` opens a BLOCK, so
      // `{ ...bag, g: 1 };` is a syntax error rather than an object
      // literal — as it is in every JS engine, which made these look
      // like mtsc parser bugs until Node rejected them too. Same for a
      // leading `function` or `class`, which would be declarations.
      // Parens alone are not enough, because a leading `{` can also be
      // nested INSIDE them and something downstream may re-print the
      // program with the parens gone. Node 22's
      // `--experimental-transform-types` — the reference leg — does
      // exactly that. Given
      //
      //     (({ ...obj, g: 1 } ? 1 : 2), (a--));
      //
      // it emits `{ ...obj, g: 1 } ? 1 : 2, a--;`, so the `{` opens a
      // block and the `...obj` inside is read as a rest parameter of the
      // module wrapper: "Rest parameter must be last formal parameter",
      // on a program that is valid as written. Reproducible in four
      // lines on Node v22.22.2, and nothing to do with mtsc, which
      // compiles it correctly. It cost 23 of 6019 seeds their oracle,
      // was reported as `[no-oracle] original threw SyntaxError`, and
      // reads exactly like a generator defect.
      //
      // `void` is what survives that re-printing. A leading `0,` does
      // NOT: SWC drops a constant first operand of a discarded comma
      // and puts the `{` right back at the front. `void` is a unary
      // operator rather than a discardable operand, so it stays, and
      // for an expression statement whose value is already thrown away
      // it changes nothing. All three legs still run the same source.
      const bare = text.replace(/^\(+/, "");
      if (/^[{]/.test(bare)) return `${p}void (${text});\n`;
      if (/^(function|class)\b/.test(bare)) return `${p}(${text});\n`;
      return `${p}${text};\n`;
    }
    case "decl": {
      const type = node.type ? `: ${node.type}` : "";
      return `${p}${node.kind} ${node.name}${type} = ${printExpr(node.init)};\n`;
    }
    case "destructure":
      return `${p}const ${node.pattern} = ${printExpr(node.init)};\n`;
    case "block":
      return `${p}{\n${printBody(node.body, depth + 1)}${p}}\n`;
    case "if": {
      let out = `${p}if (${printExpr(node.test)}) {\n${printBody(node.then, depth + 1)}${p}}`;
      if (node.else_) out += ` else {\n${printBody(node.else_, depth + 1)}${p}}`;
      return `${out}\n`;
    }
    // Every loop is bounded by its own brake counter, so a generated
    // program terminates without the oracle having to rely on the vm
    // timeout. A timed-out original is a SKIPPED seed, and a generator
    // that produced many of them would quietly stop testing anything.
    case "while":
      return (
        `${p}let ${node.brake} = 4;\n` +
        `${p}while (--${node.brake} > 0 && (${printExpr(node.test)})) {\n` +
        `${printBody(node.body, depth + 1)}${p}}\n`
      );
    case "dowhile":
      return (
        `${p}let ${node.brake} = 4;\n` +
        `${p}do {\n${printBody(node.body, depth + 1)}${p}} ` +
        `while (--${node.brake} > 0 && (${printExpr(node.test)}));\n`
      );
    case "for":
      return (
        `${p}for (let ${node.brake} = 4; ${node.brake}-- > 0 && (${printExpr(node.test)}); ) {\n` +
        `${printBody(node.body, depth + 1)}${p}}\n`
      );
    // `for...in` is a name-observing construct: it yields own enumerable
    // KEYS, so a renamed property changes what the loop sees.
    case "forin":
      return (
        `${p}for (const ${node.name} in ${printExpr(node.object)}) {\n` +
        `${printBody(node.body, depth + 1)}${p}}\n`
      );
    case "forof":
      return (
        `${p}for (const ${node.name} of ${printExpr(node.object)}) {\n` +
        `${printBody(node.body, depth + 1)}${p}}\n`
      );
    case "switch": {
      let out = `${p}switch (${printExpr(node.disc)}) {\n`;
      for (const c of node.cases) {
        out += c.test ? `${p}case ${printExpr(c.test)}:\n` : `${p}default:\n`;
        out += printBody(c.body, depth + 1);
        if (c.test) out += `${pad(depth + 1)}break;\n`;
      }
      return `${out}${p}}\n`;
    }
    case "try":
      return (
        `${p}try {\n` +
        `${pad(depth + 1)}if (${printExpr(node.test)}) throw ${printExpr(node.thrown)};\n` +
        `${printBody(node.body, depth + 1)}${p}} catch (caught) {\n` +
        `${pad(depth + 1)}trace.push(${node.traceId});\n` +
        `${printBody(node.handler, depth + 1)}${p}}\n`
      );
    case "return":
      return node.expr ? `${p}return ${printExpr(node.expr)};\n` : `${p}return;\n`;
    case "break":
      return `${p}break;\n`;
    case "continue":
      return `${p}continue;\n`;
    case "delete":
      return `${p}delete ${printExpr(node.target)};\n`;
    default:
      throw new Error(`fuzz-ir: cannot print statement ${node.k}`);
  }
}

function printBody(body, depth) {
  // An emptied block still has to parse. Shrinking removes statements
  // one at a time and will reach zero.
  if (body.length === 0) return `${pad(depth)};\n`;
  return body.map((s) => printStmt(s, depth)).join("");
}

/// Record that this callable ran.
///
/// The oracle used to compare only VALUES, and a call whose result
/// nobody reads is invisible to that. It is also precisely the shape
/// that broke the minified TypeScript compiler: a call whose only job
/// was to attach a symbol to a node, bound to a variable that was read
/// under a condition that happened to be false. The value comparison
/// agreed; the module simply never got its symbol.
///
/// So every generated callable announces its own invocation. A dropped
/// call, a duplicated call, and a reordered call are now all differences
/// in `trace`, whatever the values do.
function entryTrace(id, depth) {
  if (id === undefined) return "";
  return `${pad(depth)}trace.push(${id});\n`;
}

function printClassMember(member, depth) {
  const p = pad(depth);
  const staticPrefix = member.static ? "static " : "";
  switch (member.k) {
    case "field":
      return `${p}${staticPrefix}${member.name}${member.type ? `: ${member.type}` : ""} = ${printExpr(member.init)};\n`;
    // A `#private` field is the only lexically-guaranteed own member of a
    // class: nothing outside the class body can name it, so a rename of
    // it is unobservable and the analysis is allowed to be aggressive.
    // Generating them keeps that path exercised.
    case "private":
      return `${p}#${member.name} = ${printExpr(member.init)};\n`;
    case "method":
      return (
        `${p}${staticPrefix}${member.name}(${member.params.join(", ")}) {\n` +
        entryTrace(member.entryId, depth + 1) +
        `${printBody(member.body, depth + 1)}${p}}\n`
      );
    case "getter":
      return (
        `${p}${staticPrefix}get ${member.name}() {\n` +
        entryTrace(member.entryId, depth + 1) +
        `${printBody(member.body, depth + 1)}${p}}\n`
      );
    default:
      throw new Error(`fuzz-ir: cannot print class member ${member.k}`);
  }
}

function printDecl(decl) {
  switch (decl.k) {
    case "func": {
      const params = decl.params.join(", ");
      // The shared call budget. Without it, two generated functions
      // calling each other recurse until the stack dies, and a crashed
      // original is a skipped seed rather than a tested one.
      const guard = `${INDENT}if (--callBudget < 0) return 0;\n`;
      return (
        `function ${decl.name}(${params})${decl.ret ? `: ${decl.ret}` : ""} {\n` +
        guard +
        entryTrace(decl.entryId, 1) +
        printBody(decl.body, 1) +
        `}\n`
      );
    }
    case "class":
      return (
        `class ${decl.name}${decl.extends ? ` extends ${decl.extends}` : ""} {\n` +
        decl.members.map((m) => printClassMember(m, 1)).join("") +
        `}\n`
      );
    case "iface":
      return (
        `interface ${decl.name} {\n` +
        decl.fields.map((f) => `${INDENT}${f.name}: ${f.type};\n`).join("") +
        `}\n`
      );
    case "alias":
      return `type ${decl.name} = ${decl.body};\n`;
    // Verbatim TypeScript, emitted as one atom.
    //
    // Used by the name-resolution group (`shadowGroup` in
    // `fuzz-generate.mjs`), whose shapes are `const enum`, a type-guard
    // signature, a literal-union `switch` dispatcher and so on — six
    // constructs that the expression grammar has no nodes for and that
    // would each need a printer arm to gain nothing, since the group's
    // whole point is a fixed shape with a fresh NAME.
    //
    // The cost is real and bounded: the shrinker cannot reduce inside a
    // raw node, only drop it. Each shape is therefore its own raw decl,
    // so a reduction can drop five of six and leave the one that fails.
    case "raw":
      return decl.text;
    default:
      throw new Error(`fuzz-ir: cannot print declaration ${decl.k}`);
  }
}

// ---------------------------------------------------------------
// Whole program
// ---------------------------------------------------------------

/// Print the module under test.
///
/// The prelude is fixed so that every generated program has the same
/// mutable surface to work on, and the epilogue is the ONLY thing the
/// oracle compares. Both sides of the comparison run the same epilogue,
/// so a difference is a difference in the program's behaviour.
///
/// `shape` decides which door the names escape through:
///
///   "sink"    nothing is exported, so the mangler may rename every
///             property it cannot prove observable. Observation happens
///             through sinks inside the module — `JSON.stringify`,
///             `Object.keys`, a `for...in` — which is precisely the
///             half of the safety argument that `mangle_safety.mbt`
///             owns.
///   "export"  the module exports part of its surface, so those names
///             are ABI and must survive. Observation happens from
///             outside, in the runner.
export function printProgram(program) {
  const out = [];
  out.push("// generated by scripts/fuzz_mangle.mjs — do not edit\n");
  for (const decl of program.types) out.push(printDecl(decl));
  out.push("let callBudget = 12;\n");
  out.push("const trace: number[] = [];\n");
  out.push(
    "let a = 100, b = 10, c = 0, x = 1, y = 2, z = 3;\n" +
      "const obj: Record<string, number> = { p: 0, q: 1, r: 2 };\n" +
      "const arr = [0, 1, 2];\n" +
      "const bag = { alpha: 1, beta: 2, gamma: 3 };\n" +
      "const keys = ['alpha', 'beta'];\n" +
      // A key the analysis cannot fold to a literal. `keys[0]` is
      // resolvable in principle; this one is not, which is what forces
      // the conservative branch of the computed-read rule.
      "const dynamicKey = keys[arr[0]];\n",
  );
  for (const decl of program.decls) out.push(printDecl(decl));
  out.push(printBody(program.body, 0));
  out.push(printObservation(program));
  if (program.shape === "export" && program.exports.length > 0) {
    out.push(`export { ${program.exports.join(", ")} };\n`);
  }
  return out.join("");
}

/// The observation epilogue. `report` is a plain function so that the
/// values reaching it are a value-flow the analysis has to account for.
function printObservation(program) {
  if (program.shape === "export") {
    // The runner observes the export surface from outside, so the module
    // only has to leave the trace reachable.
    return `export const __trace = trace;\n`;
  }
  const items = program.observe.map(printExpr).join(",\n  ");
  return `console.log([\n  ${items}\n]);\n`;
}

// ---------------------------------------------------------------
// Size and traversal
// ---------------------------------------------------------------

/// Node count, used as the shrinker's objective. Cheaper and steadier
/// than source length: a rename would change the length and not the
/// structure.
export function size(value) {
  if (Array.isArray(value)) {
    let total = 0;
    for (const item of value) total += size(item);
    return total;
  }
  if (value && typeof value === "object") {
    let total = value.k ? 1 : 0;
    for (const key of Object.keys(value)) {
      if (key === "k") continue;
      total += size(value[key]);
    }
    return total;
  }
  return 0;
}

export function clone(value) {
  return structuredClone(value);
}
