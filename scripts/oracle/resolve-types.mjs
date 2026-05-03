// Oracle: resolve TypeScript type aliases via the official TypeScript
// Compiler API. Reads a JSON request payload describing alias names
// (and the .d.ts entry that declares them) from stdin or argv[2], and
// writes a resolved-type cache as JSON to stdout (or argv[3]).
//
// Wire format:
//   request  = { entries: [string, ...], requests: [{ key, alias_name }, ...] }
//   response = { resolutions: [{ key, ok, type?, error? }, ...] }
//
// `type` mirrors the bridge's `TsType` shape in a JSON-friendly form:
//   { kind: "primitive", name: "string" | "number" | "boolean" | "bigint" }
//   { kind: "literal", literal_kind: "string"|"number"|"bigint"|"bool", value: string }
//   { kind: "any" }    | { kind: "void" } | { kind: "null" } | { kind: "undefined" } | { kind: "never" }
//   { kind: "array", element: <type> }
//   { kind: "tuple", items: [<type>, ...] }
//   { kind: "union", parts: [<type>, ...] }
//   { kind: "intersection", parts: [<type>, ...] }
//   { kind: "named", name: string }
//   { kind: "applied", name: string, args: [<type>, ...] }
//   { kind: "func", params: [<type>, ...], return: <type> }
//   { kind: "object", entries: [{ key: <type>, value: <type> }, ...] }
//
// Out-of-scope shapes (mapped, conditional, infer, template literal,
// indexed access, generic param) round-trip as { kind: "unknown_shape",
// printed: string } so the caller can decide whether to widen or fail.

import ts from "typescript";
import fs from "node:fs";
import path from "node:path";

function readJsonStdin() {
  const chunks = [];
  return new Promise((resolve, reject) => {
    process.stdin.on("data", (c) => chunks.push(c));
    process.stdin.on("end", () => {
      try {
        const buf = Buffer.concat(chunks).toString("utf8");
        resolve(JSON.parse(buf));
      } catch (e) {
        reject(e);
      }
    });
    process.stdin.on("error", reject);
  });
}

function loadRequest() {
  const inputPath = process.argv[2];
  if (inputPath && inputPath !== "-") {
    const buf = fs.readFileSync(inputPath, "utf8");
    return Promise.resolve(JSON.parse(buf));
  }
  return readJsonStdin();
}

function buildProgram(entries) {
  const compilerOptions = {
    target: ts.ScriptTarget.ESNext,
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.NodeNext,
    strict: false,
    noEmit: true,
    skipLibCheck: true,
    allowJs: false,
    declaration: false,
    esModuleInterop: true,
    resolveJsonModule: false,
  };
  const program = ts.createProgram(entries, compilerOptions);
  return { program, checker: program.getTypeChecker() };
}

function findAliasSymbol(program, checker, aliasName) {
  for (const sf of program.getSourceFiles()) {
    if (sf.isDeclarationFile === false) continue;
    let found = null;
    sf.forEachChild((node) => {
      if (found) return;
      if (
        ts.isTypeAliasDeclaration(node) &&
        node.name.text === aliasName
      ) {
        found = { kind: "alias", node };
      } else if (
        ts.isInterfaceDeclaration(node) &&
        node.name.text === aliasName
      ) {
        found = { kind: "interface", node };
      } else if (
        ts.isClassDeclaration(node) &&
        node.name &&
        node.name.text === aliasName
      ) {
        found = { kind: "class", node };
      }
    });
    if (found) return { sourceFile: sf, ...found };
  }
  return null;
}

function serializeType(checker, type, depth = 0) {
  if (depth > 6) {
    return { kind: "unknown_shape", printed: checker.typeToString(type) };
  }
  const flags = type.flags;
  if (flags & ts.TypeFlags.String) return { kind: "primitive", name: "string" };
  if (flags & ts.TypeFlags.Number) return { kind: "primitive", name: "number" };
  if (flags & ts.TypeFlags.Boolean) return { kind: "primitive", name: "boolean" };
  if (flags & ts.TypeFlags.BigInt) return { kind: "primitive", name: "bigint" };
  if (flags & ts.TypeFlags.ESSymbol) return { kind: "primitive", name: "symbol" };
  if (flags & ts.TypeFlags.Void) return { kind: "void" };
  if (flags & ts.TypeFlags.Undefined) return { kind: "undefined" };
  if (flags & ts.TypeFlags.Null) return { kind: "null" };
  if (flags & ts.TypeFlags.Any) return { kind: "any" };
  if (flags & ts.TypeFlags.Unknown) return { kind: "any" };
  if (flags & ts.TypeFlags.Never) return { kind: "never" };
  if (flags & ts.TypeFlags.StringLiteral) {
    return { kind: "literal", literal_kind: "string", value: type.value };
  }
  if (flags & ts.TypeFlags.NumberLiteral) {
    return { kind: "literal", literal_kind: "number", value: String(type.value) };
  }
  if (flags & ts.TypeFlags.BigIntLiteral) {
    return {
      kind: "literal",
      literal_kind: "bigint",
      value: `${type.value.negative ? "-" : ""}${type.value.base10Value}`,
    };
  }
  if (flags & ts.TypeFlags.BooleanLiteral) {
    const intrinsicName = type.intrinsicName;
    return {
      kind: "literal",
      literal_kind: "bool",
      value: intrinsicName === "true" ? "true" : "false",
    };
  }
  if (flags & ts.TypeFlags.UniqueESSymbol) {
    return { kind: "primitive", name: "symbol" };
  }
  if (flags & ts.TypeFlags.Union) {
    return {
      kind: "union",
      parts: type.types.map((t) => serializeType(checker, t, depth + 1)),
    };
  }
  if (flags & ts.TypeFlags.Intersection) {
    return {
      kind: "intersection",
      parts: type.types.map((t) => serializeType(checker, t, depth + 1)),
    };
  }
  if (checker.isArrayType?.(type) || checker.isReadonlyArrayType?.(type)) {
    const args = checker.getTypeArguments(type);
    return {
      kind: "array",
      element: args[0]
        ? serializeType(checker, args[0], depth + 1)
        : { kind: "any" },
    };
  }
  if (checker.isTupleType?.(type)) {
    const args = checker.getTypeArguments(type) || [];
    return {
      kind: "tuple",
      items: args.map((t) => serializeType(checker, t, depth + 1)),
    };
  }
  if (flags & ts.TypeFlags.Object) {
    const symbol = type.getSymbol?.();
    if (symbol) {
      const name = symbol.getName?.() ?? symbol.name;
      const objectType = type;
      const typeArgs = checker.getTypeArguments?.(objectType) || [];
      if (
        objectType.objectFlags & ts.ObjectFlags.Reference &&
        typeArgs.length > 0
      ) {
        return {
          kind: "applied",
          name,
          args: typeArgs.map((t) => serializeType(checker, t, depth + 1)),
        };
      }
      if (name && name !== "__type" && name !== "__object") {
        return { kind: "named", name };
      }
    }
    const callSigs = checker.getSignaturesOfType(type, ts.SignatureKind.Call);
    if (callSigs.length === 1 && type.getProperties().length === 0) {
      const sig = callSigs[0];
      const params = sig
        .getParameters()
        .map((p) =>
          serializeType(
            checker,
            checker.getTypeOfSymbolAtLocation(p, p.valueDeclaration ?? sig.declaration ?? p.declarations?.[0]),
            depth + 1
          )
        );
      const returnType = serializeType(
        checker,
        checker.getReturnTypeOfSignature(sig),
        depth + 1
      );
      return { kind: "func", params, return: returnType };
    }
    const props = type.getProperties();
    if (props.length > 0) {
      const entries = [];
      for (const p of props) {
        const decl = p.valueDeclaration ?? p.declarations?.[0];
        if (!decl) continue;
        const propType = checker.getTypeOfSymbolAtLocation(p, decl);
        entries.push({
          key: { kind: "literal", literal_kind: "string", value: p.getName() },
          value: serializeType(checker, propType, depth + 1),
        });
      }
      return { kind: "object", entries };
    }
  }
  return { kind: "unknown_shape", printed: checker.typeToString(type) };
}

async function main() {
  const req = await loadRequest();
  if (!req || !Array.isArray(req.entries) || !Array.isArray(req.requests)) {
    process.stderr.write("invalid request: expected { entries:[], requests:[] }\n");
    process.exit(2);
  }
  const resolvedEntries = req.entries.map((e) => path.resolve(e));
  const { program, checker } = buildProgram(resolvedEntries);
  const resolutions = [];
  for (const r of req.requests) {
    if (typeof r.key !== "string" || typeof r.alias_name !== "string") {
      resolutions.push({ key: String(r.key), ok: false, error: "bad request shape" });
      continue;
    }
    try {
      const found = findAliasSymbol(program, checker, r.alias_name);
      if (!found) {
        resolutions.push({ key: r.key, ok: false, error: "alias not found" });
        continue;
      }
      let type;
      if (found.kind === "alias") {
        type = checker.getTypeFromTypeNode(found.node.type);
      } else if (found.kind === "interface" || found.kind === "class") {
        type = checker.getTypeAtLocation(found.node);
      } else {
        resolutions.push({ key: r.key, ok: false, error: `unsupported kind ${found.kind}` });
        continue;
      }
      const serialized = serializeType(checker, type);
      resolutions.push({ key: r.key, ok: true, type: serialized });
    } catch (err) {
      resolutions.push({ key: r.key, ok: false, error: String(err?.message ?? err) });
    }
  }
  const out = JSON.stringify({ resolutions }, null, 2);
  const outPath = process.argv[3];
  if (outPath && outPath !== "-") {
    fs.writeFileSync(outPath, out);
  } else {
    process.stdout.write(out + "\n");
  }
}

main().catch((e) => {
  process.stderr.write(String(e?.stack ?? e) + "\n");
  process.exit(1);
});
