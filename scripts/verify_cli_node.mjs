#!/usr/bin/env node
// Does the CLI behave the same on Node as it does natively?
//
// The CLI is a native executable first, and it now also builds for the
// `js` backend so `mtsc` can run under Node. That is only worth
// shipping if the two AGREE, so this is a differential: every case runs
// through both binaries, in the same temp directory, with the same
// relative arguments, and stdout plus the exit code must match.
//
// The native binary is a genuine independent oracle here — same source,
// a different backend and a different runtime for every syscall the CLI
// makes (`mizchi/x/fs` goes through `node:fs/promises` on `js` and
// through C on native, `@env.args()` reads `process.argv` on one and
// the C runtime's argv on the other). A JS-only self-comparison would
// have caught none of the three bugs this harness exists for.
//
// Those three are worth naming, because each was silent:
//
//   1. `@env.args()` returns `process.argv` VERBATIM on `js`, which has
//      TWO leading entries (the Node executable and the script) where
//      the native runtime has one. The CLI read index 1 as the first
//      user argument, so under Node it took its own 19 MB bundle as an
//      input file and reported `ParseError("Unexpected token: Gt")`
//      against itself — turning `mtsc ok.ts --noEmit` on a clean file
//      into exit 1.
//   2. `--watch`'s mtime probe first used `require("node:fs")`. The
//      bundle is a `.js` IIFE under a `package.json` saying
//      `"type": "module"`, so Node loads it as ESM, where `require` is
//      not defined — and the `catch` turned that into "no stamp" for
//      every file, which compares equal to the previous "no stamp" and
//      so never detects a change. `--watch` would have polled forever
//      in silence.
//   3. `@async_fs.mtime` does not exist on `js` at all, which is why
//      the CLI could not build for the backend in the first place.
//
// Case 2 is why the watch round trip is in here rather than left to a
// smoke test: it is the one failure that looks exactly like success.
//
//   node scripts/verify_cli_node.mjs
//   node scripts/verify_cli_node.mjs --verbose

import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const VERBOSE = process.argv.includes("--verbose");
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/**
 * Release before debug, and the choice is PRINTED.
 *
 * `moon build --target native` produces a DEBUG binary, and this repo
 * has already lost an hour to a hand probe that measured a stale
 * release build. Saying which file is under test is the cheap half of
 * not repeating that.
 */
function pickBinary(kind) {
  const candidates = kind === "js"
    ? ["_build/js/release/build/cmd/mtsc/mtsc.js", "_build/js/debug/build/cmd/mtsc/mtsc.js"]
    : ["_build/native/release/build/cmd/mtsc/mtsc.exe", "_build/native/debug/build/cmd/mtsc/mtsc.exe"];
  for (const candidate of candidates) {
    const path = join(ROOT, candidate);
    if (existsSync(path)) return path;
  }
  throw new Error(
    `no ${kind} CLI found. Build it:\n` +
      `  moon build --target ${kind === "js" ? "js" : "native"} --release\n` +
      `looked for:\n  ${candidates.join("\n  ")}`,
  );
}

const NATIVE = pickBinary("native");
const JS = pickBinary("js");
console.log(`native: ${NATIVE.slice(ROOT.length + 1)}`);
console.log(`js:     ${JS.slice(ROOT.length + 1)}\n`);

let passed = 0;
const failures = [];

/** Run one binary and capture everything that could differ. */
function run(which, args, cwd) {
  const [file, argv] = which === "js" ? ["node", [JS, ...args]] : [NATIVE, args];
  try {
    const stdout = execFileSync(file, argv, {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return { stdout, code: 0 };
  } catch (error) {
    // A non-zero exit is an ordinary outcome here — `mtsc` exits 1 on
    // diagnostics — so it must not be reported as a harness failure.
    return { stdout: error.stdout ?? "", code: error.status ?? -1 };
  }
}

/**
 * A case is a name, the files it needs, and the argv.
 *
 * Arguments stay RELATIVE and both binaries run with the same cwd, so
 * the outputs contain no absolute path that could differ between them
 * and there is nothing to normalize away — a normalizer is a place for
 * a real difference to hide.
 */
const CASES = [
  {
    name: "--version",
    files: {},
    args: ["--version"],
  },
  {
    name: "--help",
    files: {},
    args: ["--help"],
  },
  {
    name: "clean file, --noEmit (must be silent and exit 0)",
    files: { "ok.ts": "export const ok: number = 1;\n" },
    args: ["ok.ts", "--noEmit"],
  },
  {
    name: "type error, --noEmit (must report and exit 1)",
    files: { "bad.ts": "export const bad: string = 1;\n" },
    args: ["bad.ts", "--noEmit"],
  },
  {
    name: "syntax error, --noEmit",
    files: { "broken.ts": "export const broken: =\n" },
    args: ["broken.ts", "--noEmit"],
  },
  {
    name: "cross-module type error, --bundle --noEmit",
    files: {
      "entry.ts": 'import { score } from "./score";\nexport const label: string = score;\n',
      "score.ts": "export const score: number = 1;\n",
    },
    args: ["entry.ts", "--bundle", "--noEmit"],
  },
  {
    name: "clean program, --bundle --noEmit",
    files: {
      "entry.ts": 'import { score } from "./score";\nexport const label: number = score;\n',
      "score.ts": "export const score: number = 1;\n",
    },
    args: ["entry.ts", "--bundle", "--noEmit"],
  },
  {
    name: "emit to stdout",
    files: { "ok.ts": "export const ok: number = 1;\n" },
    args: ["ok.ts"],
  },
  {
    name: "emit a bundle to a file",
    files: {
      "entry.ts": 'import { score } from "./score";\nexport const total = score + 1;\n',
      "score.ts": "export const score: number = 1;\n",
    },
    args: ["entry.ts", "--bundle", "--outfile", "out.js"],
    // The emitted FILE is part of the observation, not just stdout: a
    // backend whose `write_file` silently did nothing would otherwise
    // pass on an empty stdout match.
    reads: ["out.js"],
  },
  {
    name: "TypeScript lowerings survive the emit",
    files: {
      "low.ts": [
        "enum Color { Red, Green }",
        "class Counter { #n = 0; bump(): number { return ++this.#n; } }",
        "export const used = [Color.Green, new Counter().bump()];",
      ].join("\n") + "\n",
    },
    args: ["low.ts", "--bundle", "--outfile", "low.js"],
    reads: ["low.js"],
  },
  {
    name: "check verb on a clean file",
    files: { "ok.ts": "export const ok: number = 1;\n" },
    args: ["check", "ok.ts"],
  },
  {
    name: "check verb on a type error",
    files: { "bad.ts": "function f(n: number): string { return n; }\n" },
    args: ["check", "bad.ts"],
  },
  {
    name: "an unknown option is rejected",
    files: { "ok.ts": "export const ok: number = 1;\n" },
    args: ["ok.ts", "--definitelyNotAnOption"],
  },
  {
    name: "an accepted-but-unhonoured tsc flag is reported, not refused",
    files: { "ok.ts": "export const ok: number = 1;\n" },
    args: ["ok.ts", "--noEmit", "--target", "es2020", "--strict"],
  },
  {
    name: "a missing entry file",
    files: {},
    args: ["nope.ts", "--noEmit"],
    // The one case where byte-identical stdout is the WRONG assertion,
    // and it is a difference in the dependency rather than in mtsc:
    // `mizchi/x/fs` surfaces the OS error, and the two backends get it
    // from different places —
    //   native: `@fs.open(): "nope.ts": No such file or directory`
    //   js:     `ENOENT: no such file or directory, open 'nope.ts'`
    // Normalizing that away would be a normalizer wide enough to hide a
    // real difference, so instead the case states what must be true of
    // BOTH: each reports a read error naming the file it was given, and
    // the exit codes still have to match exactly, which is the part
    // that says the CLI treated the failure the same way.
    divergentStdout: {
      reason: "mizchi/x/fs relays the OS error text, which differs per backend",
      // Capitalization differs too (`No such` / `no such`), so the
      // shared needle stops before it.
      bothContain: ["mtsc: read error nope.ts", "such file or directory"],
    },
  },
  {
    // The `bridge` / `pkg` verbs route through `mizchi/ts` — a whole
    // package the compile path never touches, and the one holding the
    // other per-target split in this repo
    // (`publish_staged_bridge_file`, atomic rename on native against
    // read + write + remove on `js`). Without a case here the root
    // package's JS arm ships unexercised.
    name: "pkg decl: TypeScript declarations from a .mbti",
    files: {
      "in.mbti": [
        'package "demo/lib"',
        "",
        "// Values",
        "pub fn add(Int, Int) -> Int",
        "",
        "pub fn label(String) -> String",
        "",
        "// Types and methods",
        "pub(all) struct Point {",
        "  x : Int",
        "  y : Int",
        "}",
        "",
      ].join("\n"),
    },
    args: ["pkg", "decl", "in.mbti", "out.d.ts"],
    reads: ["out.d.ts"],
  },
  {
    name: "bridge decl: MoonBit stubs from a .d.ts",
    files: {
      "api.d.ts": [
        "export declare function add(a: number, b: number): number;",
        "export interface Point { x: number; y: number }",
        "export declare const origin: Point;",
        "",
      ].join("\n"),
    },
    args: ["bridge", "decl", "api.d.ts", "bridge.mbt"],
    reads: ["bridge.mbt"],
  },
  {
    // The path that actually calls `publish_staged_bridge_file`: it
    // stages every generated file and then publishes each one, which is
    // the split above. A backend that lost a file in the publish step
    // shows up here and nowhere else.
    name: "bridge package: a whole generated package directory",
    files: {
      "api.d.ts": [
        "export declare function add(a: number, b: number): number;",
        "export interface Point { x: number; y: number }",
        "",
      ].join("\n"),
    },
    args: ["bridge", "package", "api.d.ts", "demo-api", "out"],
    reads: ["out/bridge.mbt", "out/bridge.mbti", "out/bridge.js", "out/moon.pkg"],
  },
  {
    name: "-p on a tsconfig project",
    files: {
      "tsconfig.json": JSON.stringify({ compilerOptions: { noEmit: true }, include: ["src"] }, null, 2),
      "src/a.ts": "export const a: string = 1;\n",
    },
    args: ["-p", "."],
  },
];

for (const testCase of CASES) {
  const root = mkdtempSync(join(tmpdir(), "mtsc-cli-"));
  try {
    for (const [name, contents] of Object.entries(testCase.files)) {
      const target = join(root, name);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, contents, "utf8");
    }
    const nativeRun = run("native", testCase.args, root);
    // A fresh directory per backend, so one cannot see the other's
    // emitted output — otherwise the second run could read a file the
    // first wrote and the comparison would be of one backend twice.
    const jsRoot = mkdtempSync(join(tmpdir(), "mtsc-cli-js-"));
    for (const [name, contents] of Object.entries(testCase.files)) {
      const target = join(jsRoot, name);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, contents, "utf8");
    }
    const jsRun = run("js", testCase.args, jsRoot);

    const problems = [];
    if (testCase.divergentStdout) {
      // A declared divergence still has to be a divergence: if the two
      // outputs have become identical, the reason no longer applies and
      // the case should go back to the exact comparison rather than
      // keep a looser one nobody rechecks.
      if (nativeRun.stdout === jsRun.stdout) {
        problems.push(
          `stdout no longer differs — drop divergentStdout ` +
            `(${testCase.divergentStdout.reason})`,
        );
      }
      for (const needle of testCase.divergentStdout.bothContain) {
        if (!nativeRun.stdout.includes(needle)) {
          problems.push(`native stdout lacks ${JSON.stringify(needle)}`);
        }
        if (!jsRun.stdout.includes(needle)) {
          problems.push(`js stdout lacks ${JSON.stringify(needle)}`);
        }
      }
    } else if (nativeRun.stdout !== jsRun.stdout) {
      problems.push(
        `stdout differs\n--- native ---\n${nativeRun.stdout}--- js ---\n${jsRun.stdout}`,
      );
    }
    if (nativeRun.code !== jsRun.code) {
      problems.push(`exit code differs: native ${nativeRun.code}, js ${jsRun.code}`);
    }
    for (const artifact of testCase.reads ?? []) {
      const readOne = (base) => {
        const path = join(base, artifact);
        return existsSync(path) ? readFileSync(path, "utf8") : null;
      };
      const a = readOne(root);
      const b = readOne(jsRoot);
      if (a !== b) {
        problems.push(
          `emitted ${artifact} differs\n--- native ---\n${a}\n--- js ---\n${b}`,
        );
      } else if (a === null) {
        problems.push(`neither backend emitted ${artifact}`);
      }
    }
    rmSync(jsRoot, { recursive: true, force: true });

    if (problems.length === 0) {
      passed += 1;
      if (VERBOSE) console.log(`  ok   ${testCase.name}`);
    } else {
      failures.push(testCase.name);
      console.log(`  FAIL ${testCase.name}`);
      for (const problem of problems) {
        console.log(`       ${problem.replace(/\n/g, "\n       ")}`);
      }
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------------------
// `--watch`
// ---------------------------------------------------------------------------

/**
 * Drive a watcher through clean -> broken -> clean and collect its log.
 *
 * This is the case that cannot be checked by comparing one run's
 * output, because the failure mode is SILENCE: with the mtime probe
 * broken, every stamp is "unreadable", which compares equal to the
 * previous "unreadable", so the watcher sits there reporting nothing
 * and looks exactly like a watcher with nothing to do. What proves it
 * works is a rebuild that was CAUSED by an edit.
 */
function watchRoundTrip(which) {
  const root = mkdtempSync(join(tmpdir(), "mtsc-watch-"));
  const file = join(root, "watched.ts");
  writeFileSync(file, "export const w: number = 1;\n", "utf8");
  const [command, argv] = which === "js"
    ? ["node", [JS, "watched.ts", "--noEmit", "--watch"]]
    : [NATIVE, ["watched.ts", "--noEmit", "--watch"]];
  const child = spawn(command, argv, { cwd: root, stdio: ["ignore", "pipe", "pipe"] });
  let log = "";
  child.stdout.on("data", (chunk) => { log += chunk.toString(); });
  child.stderr.on("data", (chunk) => { log += chunk.toString(); });

  const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
  return (async () => {
    try {
      // Each step waits several poll intervals (the loop polls every
      // 300 ms), so a pass is not a race the harness happened to win.
      await sleep(4000);
      writeFileSync(file, "export const w: string = 1;\n", "utf8");
      await sleep(4000);
      writeFileSync(file, "export const w: number = 1;\n", "utf8");
      await sleep(4000);
      return log;
    } finally {
      child.kill();
      rmSync(root, { recursive: true, force: true });
    }
  })();
}

for (const which of ["native", "js"]) {
  const name = `--watch round trip (${which})`;
  const log = await watchRoundTrip(which);
  const problems = [];
  if (!log.includes("Found 0 errors. Watching for file changes.")) {
    problems.push("no initial clean report");
  }
  // The edit has to be what triggers the rebuild.
  if (!log.includes("file change detected")) {
    problems.push("the edit did not trigger a rebuild — the mtime probe is not working");
  }
  if (!log.includes("expected `string` but got `number`")) {
    problems.push("the introduced type error was never reported");
  }
  if (!log.includes("Found errors in 1 file.")) {
    problems.push("no error summary after the edit");
  }
  // And reverting has to clear it, so the watcher is re-reading rather
  // than latching on the first change it saw.
  if (log.lastIndexOf("Found 0 errors.") <= log.indexOf("Found errors in 1 file.")) {
    problems.push("reverting the edit did not produce a clean report");
  }
  if (problems.length === 0) {
    passed += 1;
    if (VERBOSE) console.log(`  ok   ${name}`);
  } else {
    failures.push(name);
    console.log(`  FAIL ${name}`);
    for (const problem of problems) console.log(`       ${problem}`);
    console.log(`       --- log ---\n       ${log.replace(/\n/g, "\n       ")}`);
  }
}

console.log(`\ncli on node: ${passed} passed, ${failures.length} failed`);
if (failures.length > 0) process.exit(1);
