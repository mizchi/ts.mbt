// Automatic minimization of a failing program.
//
// This is the part the fuzzer it is modelled on does not have. That one
// reports "seed 15979 mismatches" and leaves a hundred-line program for
// a person to cut down by hand; the PR description says so outright
// ("requiring human minimization of failures"). Since the generator here
// produces a tree rather than text, the same loop that found the failure
// can also reduce it.
//
// The algorithm is greedy delta debugging. Propose a set of one-edit
// smaller trees; test each; keep the first that still fails; repeat from
// there until no candidate is accepted or the step budget runs out.
// Greedy rather than full ddmin because every test costs two compiles
// and a Node round-trip — on the order of 50 ms — so the budget, not the
// asymptotics, is what bounds the wall time.
//
// The acceptance test is "still a mismatch", not "the same mismatch".
// That is the standard criterion and it can in principle slide from one
// bug to another; in exchange it reduces far more aggressively. The
// artifact records both the original and the reduced tree, so a slide is
// visible rather than silent.
//
// A candidate that no longer COMPILES is rejected rather than reported.
// Removing a declaration that something still references is the common
// case, and rejecting it is cheaper than tracking references — the
// compiler already knows.

import { clone, size } from "./fuzz-ir.mjs";

// ---------------------------------------------------------------
// Edits
// ---------------------------------------------------------------
//
// Each generator below yields whole programs, already cloned, each one
// exactly one edit away from `program`. Order matters: the edits that
// remove the most are yielded first, so a greedy walk gets small fast.

/// Statement lists reachable from the program, as accessor pairs, so an
/// edit can splice one without knowing where it lives.
function* statementLists(program) {
  const seen = new Set();
  function* walk(container, key) {
    const list = container[key];
    if (!Array.isArray(list) || seen.has(list)) return;
    seen.add(list);
    yield { container, key };
    for (const stmt of list) yield* walkStmt(stmt);
  }
  function* walkStmt(stmt) {
    if (!stmt || typeof stmt !== "object") return;
    for (const key of ["body", "then", "else_", "handler"]) {
      if (Array.isArray(stmt[key])) yield* walk(stmt, key);
    }
    if (Array.isArray(stmt.cases)) {
      for (const c of stmt.cases) yield* walk(c, "body");
    }
  }
  yield* walk(program, "body");
  for (const decl of program.decls) {
    if (Array.isArray(decl.body)) yield* walk(decl, "body");
    if (Array.isArray(decl.members)) {
      for (const member of decl.members) {
        if (Array.isArray(member.body)) yield* walk(member, "body");
      }
    }
  }
}

/// Drop whole runs of statements first (halves, then quarters), then
/// single statements. Chunked removal is what turns a 400-node program
/// into a 40-node one in a handful of steps instead of hundreds.
function* dropStatements(program) {
  const lists = [...statementLists(program)].map(({ container, key }) => ({
    path: pathOf(program, container, key),
    length: container[key].length,
  }));
  for (const { path, length } of lists) {
    if (length === 0) continue;
    for (const chunk of chunkSizes(length)) {
      for (let start = 0; start + chunk <= length; start += chunk) {
        const next = clone(program);
        const list = resolvePath(next, path);
        list.splice(start, chunk);
        yield next;
      }
    }
  }
}

function chunkSizes(length) {
  const sizes = [];
  let chunk = Math.max(1, Math.floor(length / 2));
  while (chunk >= 1) {
    if (!sizes.includes(chunk)) sizes.push(chunk);
    if (chunk === 1) break;
    chunk = Math.floor(chunk / 2);
  }
  return sizes;
}

/// Drop a whole declaration — a class, a function, an interface. Removes
/// the most per step, so it is tried before anything finer.
function* dropDeclarations(program) {
  for (let i = program.decls.length - 1; i >= 0; i--) {
    const next = clone(program);
    next.decls.splice(i, 1);
    if (next.shape === "export") {
      next.exports = next.exports.filter((name) => name !== program.decls[i].name);
    }
    yield next;
  }
  for (let i = program.types.length - 1; i >= 0; i--) {
    const next = clone(program);
    next.types.splice(i, 1);
    yield next;
  }
}

/// Drop one member of one class. A failure that needs a method needs
/// only that method.
function* dropClassMembers(program) {
  for (let d = 0; d < program.decls.length; d++) {
    const decl = program.decls[d];
    if (!Array.isArray(decl.members)) continue;
    for (let m = decl.members.length - 1; m >= 0; m--) {
      const next = clone(program);
      next.decls[d].members.splice(m, 1);
      yield next;
    }
  }
}

/// Drop one observation. A mismatch usually shows in one of them, and
/// removing the rest makes the artifact readable. Never empties the list
/// — an observation-free program compares equal to everything.
function* dropObservations(program) {
  if (program.observe.length <= 1) return;
  for (let i = program.observe.length - 1; i >= 0; i--) {
    const next = clone(program);
    next.observe.splice(i, 1);
    yield next;
  }
}

const LITERAL_REPLACEMENTS = ["0", "1", "'x'", "null"];

/// Replace an expression by one of its own children, then by a literal.
/// Child-first is deliberate: it keeps the interesting operand and drops
/// the wrapper, which is how `(a + (trace.push(3), b))` reduces to `b`
/// without losing the property access that mattered.
function* simplifyExpressions(program) {
  const sites = [...expressionSites(program)];
  // Largest subtrees first: collapsing a big one is worth more.
  sites.sort((left, right) => right.weight - left.weight);
  for (const site of sites) {
    for (const child of expressionChildren(site.node)) {
      const next = clone(program);
      assignPath(next, site.path, clone(child));
      yield next;
    }
    for (const value of LITERAL_REPLACEMENTS) {
      if (site.node.k === "lit" && site.node.value === value) continue;
      const next = clone(program);
      assignPath(next, site.path, { k: "lit", value });
      yield next;
    }
  }
}

const EXPRESSION_KEYS = [
  "expr", "init", "test", "thrown", "disc", "object", "target", "value",
  "left", "right", "then", "else_", "arg", "obj", "index", "callee", "body",
];

/// Every expression position in the program, with its path and subtree
/// size. Statement lists are skipped — `dropStatements` owns those.
function* expressionSites(program) {
  function* walk(node, path) {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) {
      for (let i = 0; i < node.length; i++) yield* walk(node[i], [...path, i]);
      return;
    }
    if (isExpression(node)) {
      yield { node, path, weight: size(node) };
    }
    for (const key of Object.keys(node)) {
      if (key === "k") continue;
      const child = node[key];
      // A statement list is not an expression position.
      if (Array.isArray(child) && child.some((item) => item && isStatement(item))) continue;
      yield* walk(child, [...path, key]);
    }
  }
  yield* walk(program.body, ["body"]);
  yield* walk(program.decls, ["decls"]);
  yield* walk(program.observe, ["observe"]);
}

const STATEMENT_KINDS = new Set([
  "expr", "decl", "destructure", "block", "if", "while", "dowhile", "for",
  "forin", "forof", "switch", "try", "return", "break", "continue", "delete",
]);

const EXPRESSION_KINDS = new Set([
  "lit", "var", "this", "member", "index", "bin", "logical", "cond", "unary",
  "assign", "update", "call", "new", "object", "array", "spread", "template",
  "seq", "trace", "sink", "arrow",
]);

function isStatement(node) {
  return Boolean(node) && typeof node === "object" && STATEMENT_KINDS.has(node.k);
}

function isExpression(node) {
  return Boolean(node) && typeof node === "object" && EXPRESSION_KINDS.has(node.k);
}

function* expressionChildren(node) {
  for (const key of EXPRESSION_KEYS) {
    const child = node[key];
    if (isExpression(child)) yield child;
  }
  for (const key of ["args", "items", "exprs"]) {
    if (!Array.isArray(node[key])) continue;
    for (const child of node[key]) if (isExpression(child)) yield child;
  }
  if (Array.isArray(node.props)) {
    for (const prop of node.props) if (isExpression(prop.value)) yield prop.value;
  }
}

// ---------------------------------------------------------------
// Paths
// ---------------------------------------------------------------

function resolvePath(root, path) {
  let node = root;
  for (const key of path) node = node[key];
  return node;
}

function assignPath(root, path, value) {
  const parent = resolvePath(root, path.slice(0, -1));
  parent[path[path.length - 1]] = value;
}

/// Find the path to `container[key]` by identity. Only used for
/// statement lists, of which there are few.
function pathOf(program, container, key) {
  let found = null;
  function walk(node, path) {
    if (found || !node || typeof node !== "object") return;
    if (node === container) {
      found = [...path, key];
      return;
    }
    if (Array.isArray(node)) {
      for (let i = 0; i < node.length; i++) walk(node[i], [...path, i]);
      return;
    }
    for (const name of Object.keys(node)) {
      if (name === "k") continue;
      walk(node[name], [...path, name]);
    }
  }
  walk(program, []);
  if (!found) throw new Error("fuzz-shrink: statement list not reachable from program");
  return found;
}

// ---------------------------------------------------------------
// The loop
// ---------------------------------------------------------------

const PASSES = [
  dropDeclarations,
  dropStatements,
  dropClassMembers,
  dropObservations,
  simplifyExpressions,
];

/// Reduce `program` while `stillFails` keeps holding.
///
/// `stillFails(candidate)` returns `"fails"` (keep it), `"passes"`
/// (discard), or `"invalid"` (discard; it did not compile). Counting the
/// three separately is what makes a stalled shrink diagnosable: a run
/// that rejected 200 candidates as `invalid` means the edits are
/// breaking references, not that the failure is already minimal.
export function shrink(program, stillFails, options = {}) {
  const budget = options.maxSteps ?? 400;
  let best = clone(program);
  let bestSize = size(best);
  const stats = { steps: 0, accepted: 0, passed: 0, invalid: 0 };

  let improved = true;
  while (improved && stats.steps < budget) {
    improved = false;
    for (const pass of PASSES) {
      for (const candidate of pass(best)) {
        if (stats.steps >= budget) break;
        const candidateSize = size(candidate);
        // An edit that does not shrink is not worth a test.
        if (candidateSize >= bestSize) continue;
        stats.steps += 1;
        const verdict = stillFails(candidate);
        if (verdict === "fails") {
          best = candidate;
          bestSize = candidateSize;
          stats.accepted += 1;
          improved = true;
          break;
        }
        if (verdict === "invalid") stats.invalid += 1;
        else stats.passed += 1;
      }
      if (improved) break;
    }
  }

  return { program: best, stats, from: size(program), to: bestSize };
}
