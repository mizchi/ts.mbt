// Real-library corpus, part 2 — slim but functionally-faithful
// reimplementations of zod / neverthrow / effect-ts shape.
// Each fixture exercises a non-trivial slice of the library's
// public API and confirms baseline/opt parity under node.

// ---------------------------------------------------------------------------
// neverthrow — Result<T, E> with `map`, `mapErr`, `andThen`, `match`
// ---------------------------------------------------------------------------

///|
let neverthrow_lib_source : String =
  #|export abstract class Result<T, E> {
  #|  abstract isOk(): this is Ok<T, E>;
  #|  abstract isErr(): this is Err<T, E>;
  #|  abstract map<U>(fn: (v: T) => U): Result<U, E>;
  #|  abstract mapErr<F>(fn: (e: E) => F): Result<T, F>;
  #|  abstract andThen<U>(fn: (v: T) => Result<U, E>): Result<U, E>;
  #|  abstract match<R>(onOk: (v: T) => R, onErr: (e: E) => R): R;
  #|  abstract unwrapOr(def: T): T;
  #|}
  #|export class Ok<T, E> extends Result<T, E> {
  #|  value: T;
  #|  constructor(value: T) {
  #|    super();
  #|    this.value = value;
  #|  }
  #|  isOk(): this is Ok<T, E> { return true; }
  #|  isErr(): this is Err<T, E> { return false; }
  #|  map<U>(fn: (v: T) => U): Result<U, E> { return new Ok(fn(this.value)); }
  #|  mapErr<F>(_fn: (e: E) => F): Result<T, F> {
  #|    return this as any as Result<T, F>;
  #|  }
  #|  andThen<U>(fn: (v: T) => Result<U, E>): Result<U, E> { return fn(this.value); }
  #|  match<R>(onOk: (v: T) => R, _onErr: (e: E) => R): R { return onOk(this.value); }
  #|  unwrapOr(_def: T): T { return this.value; }
  #|}
  #|export class Err<T, E> extends Result<T, E> {
  #|  error: E;
  #|  constructor(error: E) {
  #|    super();
  #|    this.error = error;
  #|  }
  #|  isOk(): this is Ok<T, E> { return false; }
  #|  isErr(): this is Err<T, E> { return true; }
  #|  map<U>(_fn: (v: T) => U): Result<U, E> {
  #|    return this as any as Result<U, E>;
  #|  }
  #|  mapErr<F>(fn: (e: E) => F): Result<T, F> { return new Err(fn(this.error)); }
  #|  andThen<U>(_fn: (v: T) => Result<U, E>): Result<U, E> {
  #|    return this as any as Result<U, E>;
  #|  }
  #|  match<R>(_onOk: (v: T) => R, onErr: (e: E) => R): R { return onErr(this.error); }
  #|  unwrapOr(def: T): T { return def; }
  #|}
  #|export function ok<T, E>(value: T): Result<T, E> { return new Ok(value); }
  #|export function err<T, E>(error: E): Result<T, E> { return new Err(error); }
  #|

///|
async test "real-lib2: neverthrow Result roundtrip via map / mapErr / andThen / match" {
  let files : Map[String, String] = {}
  files["neverthrow.ts"] = neverthrow_lib_source
  files["entry.ts"] =
    #|import { ok, err, Result } from "./neverthrow";
    #|function parseNum(s: string): Result<number, string> {
    #|  const n = Number(s);
    #|  return Number.isNaN(n) ? err("nan:" + s) : ok(n);
    #|}
    #|const a = parseNum("42").map(n => n * 2).match(v => "v:" + v, e => "e:" + e);
    #|const b = parseNum("nope").mapErr(e => e.toUpperCase()).match(v => "v:" + v, e => "e:" + e);
    #|const c = parseNum("10").andThen(n => n > 100 ? err<number, string>("big") : ok<number, string>(n + 1));
    #|console.log(a);
    #|console.log(b);
    #|console.log(c.match(v => "ok:" + v, e => "err:" + e));
    #|console.log("default:", parseNum("x").unwrapOr(-1));
    #|
  run_differential(
    "real-neverthrow",
    files,
    "entry.ts",
    extra_reserved_props=["value", "error"],
  )
}

// ---------------------------------------------------------------------------
// zod — schema validation with `.parse` + chained refinements
// ---------------------------------------------------------------------------

///|
let zod_lib_source : String =
  #|export class ZodError extends Error {
  #|  issues: Array<{ path: string; message: string }>;
  #|  constructor(issues: Array<{ path: string; message: string }>) {
  #|    super("ZodError: " + issues.length + " issue(s)");
  #|    this.issues = issues;
  #|  }
  #|}
  #|export interface ParseResult<T> {
  #|  ok: boolean;
  #|  data?: T;
  #|  error?: ZodError;
  #|}
  #|export abstract class ZodType<T> {
  #|  abstract _parse(value: unknown, path: string): ParseResult<T>;
  #|  parse(value: unknown): T {
  #|    const r = this._parse(value, "");
  #|    if (r.ok) return r.data as T;
  #|    throw r.error;
  #|  }
  #|  safeParse(value: unknown): ParseResult<T> { return this._parse(value, ""); }
  #|  optional(): ZodOptional<T> { return new ZodOptional(this); }
  #|  array(): ZodArray<T> { return new ZodArray(this); }
  #|}
  #|export class ZodString extends ZodType<string> {
  #|  private _min: number = 0;
  #|  private _max: number = 1000000;
  #|  min(n: number): this { this._min = n; return this; }
  #|  max(n: number): this { this._max = n; return this; }
  #|  _parse(value: unknown, path: string): ParseResult<string> {
  #|    if (typeof value !== "string") {
  #|      return { ok: false, error: new ZodError([{ path, message: "expected string" }]) };
  #|    }
  #|    if (value.length < this._min) {
  #|      return { ok: false, error: new ZodError([{ path, message: "too short" }]) };
  #|    }
  #|    if (value.length > this._max) {
  #|      return { ok: false, error: new ZodError([{ path, message: "too long" }]) };
  #|    }
  #|    return { ok: true, data: value };
  #|  }
  #|}
  #|export class ZodNumber extends ZodType<number> {
  #|  _parse(value: unknown, path: string): ParseResult<number> {
  #|    if (typeof value !== "number") {
  #|      return { ok: false, error: new ZodError([{ path, message: "expected number" }]) };
  #|    }
  #|    return { ok: true, data: value };
  #|  }
  #|}
  #|export class ZodArray<T> extends ZodType<T[]> {
  #|  inner: ZodType<T>;
  #|  constructor(inner: ZodType<T>) { super(); this.inner = inner; }
  #|  _parse(value: unknown, path: string): ParseResult<T[]> {
  #|    if (!Array.isArray(value)) {
  #|      return { ok: false, error: new ZodError([{ path, message: "expected array" }]) };
  #|    }
  #|    const out: T[] = [];
  #|    const issues: Array<{ path: string; message: string }> = [];
  #|    for (let i = 0; i < value.length; i = i + 1) {
  #|      const sub = this.inner._parse(value[i], path + "[" + i + "]");
  #|      if (sub.ok) out.push(sub.data as T);
  #|      else for (const ii of sub.error!.issues) issues.push(ii);
  #|    }
  #|    return issues.length === 0
  #|      ? { ok: true, data: out }
  #|      : { ok: false, error: new ZodError(issues) };
  #|  }
  #|}
  #|export class ZodOptional<T> extends ZodType<T | undefined> {
  #|  inner: ZodType<T>;
  #|  constructor(inner: ZodType<T>) { super(); this.inner = inner; }
  #|  _parse(value: unknown, path: string): ParseResult<T | undefined> {
  #|    if (value === undefined) return { ok: true, data: undefined };
  #|    return this.inner._parse(value, path) as ParseResult<T | undefined>;
  #|  }
  #|}
  #|export class ZodObject<T extends Record<string, any>> extends ZodType<T> {
  #|  shape: Record<string, ZodType<any>>;
  #|  constructor(shape: Record<string, ZodType<any>>) { super(); this.shape = shape; }
  #|  _parse(value: unknown, path: string): ParseResult<T> {
  #|    if (typeof value !== "object" || value === null) {
  #|      return { ok: false, error: new ZodError([{ path, message: "expected object" }]) };
  #|    }
  #|    const out: any = {};
  #|    const issues: Array<{ path: string; message: string }> = [];
  #|    for (const k of Object.keys(this.shape)) {
  #|      const sub = this.shape[k]._parse((value as any)[k], path + "." + k);
  #|      if (sub.ok) out[k] = sub.data;
  #|      else for (const ii of sub.error!.issues) issues.push(ii);
  #|    }
  #|    return issues.length === 0
  #|      ? { ok: true, data: out as T }
  #|      : { ok: false, error: new ZodError(issues) };
  #|  }
  #|}
  #|export const z = {
  #|  string: () => new ZodString(),
  #|  number: () => new ZodNumber(),
  #|  array: <T>(inner: ZodType<T>) => new ZodArray(inner),
  #|  object: <T extends Record<string, any>>(shape: Record<string, ZodType<any>>) => new ZodObject<T>(shape),
  #|};
  #|

///|
async test "real-lib2: zod-like parse + safeParse + nested object" {
  let files : Map[String, String] = {}
  files["zod.ts"] = zod_lib_source
  files["entry.ts"] =
    #|import { z } from "./zod";
    #|const userSchema = z.object<{ name: string; age: number; tags?: string[] }>({
    #|  name: z.string().min(1).max(20),
    #|  age: z.number(),
    #|  tags: z.string().array().optional(),
    #|});
    #|const ok1 = userSchema.safeParse({ name: "alice", age: 30, tags: ["a", "b"] });
    #|console.log("ok1.ok:", ok1.ok, "name:", ok1.data?.name);
    #|const bad1 = userSchema.safeParse({ name: "", age: "thirty" });
    #|console.log("bad1.ok:", bad1.ok, "issues:", bad1.error?.issues.length);
    #|for (const i of bad1.error!.issues) console.log("  " + i.path + ": " + i.message);
    #|const ok2 = userSchema.safeParse({ name: "bob", age: 25 });
    #|console.log("ok2.ok:", ok2.ok, "tags:", ok2.data?.tags === undefined);
    #|try {
    #|  userSchema.parse({ name: "", age: 0 });
    #|  console.log("unreachable");
    #|} catch (e: any) {
    #|  console.log("throw-msg:", e.message);
    #|}
    #|
  run_differential(
    "real-zod",
    files,
    "entry.ts",
    // Schema shape keys + result shape keys cross from user-supplied
    // objects through reflective code (Object.keys), so they must
    // survive mangling.
    extra_reserved_props=[
      "name", "age", "tags", "shape", "inner", "ok", "data",
      "error", "issues", "path", "message", "_min", "_max",
    ],
  )
}

// ---------------------------------------------------------------------------
// effect-tiny — slim effect / pipe / flatMap style
// ---------------------------------------------------------------------------

///|
let effect_lib_source : String =
  #|export type Effect<R, E, A> = {
  #|  __tag: "Effect";
  #|  run: (env: R) => { ok: true; value: A } | { ok: false; error: E };
  #|};
  #|export function succeed<A>(value: A): Effect<unknown, never, A> {
  #|  return { __tag: "Effect", run: () => ({ ok: true, value }) };
  #|}
  #|export function fail<E>(error: E): Effect<unknown, E, never> {
  #|  return { __tag: "Effect", run: () => ({ ok: false, error }) };
  #|}
  #|export function map<R, E, A, B>(
  #|  self: Effect<R, E, A>,
  #|  fn: (a: A) => B,
  #|): Effect<R, E, B> {
  #|  return {
  #|    __tag: "Effect",
  #|    run: (env: R) => {
  #|      const r = self.run(env);
  #|      return r.ok ? { ok: true, value: fn(r.value) } : r;
  #|    },
  #|  };
  #|}
  #|export function flatMap<R, E, A, B, E2>(
  #|  self: Effect<R, E, A>,
  #|  fn: (a: A) => Effect<R, E2, B>,
  #|): Effect<R, E | E2, B> {
  #|  return {
  #|    __tag: "Effect",
  #|    run: (env: R) => {
  #|      const r = self.run(env);
  #|      if (!r.ok) return r as any;
  #|      return fn(r.value).run(env);
  #|    },
  #|  };
  #|}
  #|export function catchAll<R, E, A, E2>(
  #|  self: Effect<R, E, A>,
  #|  recover: (e: E) => Effect<R, E2, A>,
  #|): Effect<R, E2, A> {
  #|  return {
  #|    __tag: "Effect",
  #|    run: (env: R) => {
  #|      const r = self.run(env);
  #|      return r.ok ? r : recover(r.error).run(env);
  #|    },
  #|  };
  #|}
  #|export function runSync<R, E, A>(self: Effect<R, E, A>, env: R) {
  #|  return self.run(env);
  #|}
  #|export function pipe<A, B>(a: A, f1: (a: A) => B): B;
  #|export function pipe<A, B, C>(a: A, f1: (a: A) => B, f2: (b: B) => C): C;
  #|export function pipe<A, B, C, D>(
  #|  a: A,
  #|  f1: (a: A) => B,
  #|  f2: (b: B) => C,
  #|  f3: (c: C) => D,
  #|): D;
  #|export function pipe(a: any, ...fns: Array<(x: any) => any>): any {
  #|  let cur = a;
  #|  for (const f of fns) cur = f(cur);
  #|  return cur;
  #|}
  #|

///|
async test "real-lib2: effect-tiny — succeed / fail / map / flatMap / catchAll / pipe" {
  let files : Map[String, String] = {}
  files["effect.ts"] = effect_lib_source
  files["entry.ts"] =
    #|import { succeed, fail, map, flatMap, catchAll, runSync, pipe } from "./effect";
    #|const ok1 = pipe(
    #|  succeed(5),
    #|  (e) => map(e, (n: number) => n * 2),
    #|  (e) => flatMap(e, (n: number) => n > 5 ? succeed("big:" + n) : fail("small")),
    #|);
    #|console.log("ok1:", JSON.stringify(runSync(ok1, null)));
    #|const bad = pipe(
    #|  fail<string>("boom"),
    #|  (e) => catchAll(e, (msg: string) => succeed("recovered:" + msg)),
    #|);
    #|console.log("bad:", JSON.stringify(runSync(bad, null)));
    #|const chain = pipe(
    #|  succeed(10),
    #|  (e) => flatMap(e, (n: number) => succeed(n + 1)),
    #|  (e) => flatMap(e, (n: number) => succeed(n * 3)),
    #|  (e) => map(e, (n: number) => "v=" + n),
    #|);
    #|console.log("chain:", JSON.stringify(runSync(chain, null)));
    #|
  run_differential(
    "real-effect-tiny",
    files,
    "entry.ts",
    extra_reserved_props=[
      "__tag", "run", "ok", "value", "error",
    ],
  )
}

// ---------------------------------------------------------------------------
// Bench: how does the bundler scale on each real-shape library?
// ---------------------------------------------------------------------------

///|
test "bench bundle: neverthrow library — full opt" (it : @bench.T) {
  let files : Map[String, String] = {}
  files["neverthrow.ts"] = neverthrow_lib_source
  files["entry.ts"] =
    #|import { ok, err } from "./neverthrow";
    #|const a = ok(1).map(n => n * 2);
    #|console.log(a.unwrapOr(-1));
    #|
  let opts = full_opt_bundle_options()
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

///|
test "bench bundle: zod-like library — full opt" (it : @bench.T) {
  let files : Map[String, String] = {}
  files["zod.ts"] = zod_lib_source
  files["entry.ts"] =
    #|import { z } from "./zod";
    #|const s = z.object<{ name: string }>({ name: z.string() });
    #|console.log(s.safeParse({ name: "alice" }).ok);
    #|
  let opts = full_opt_bundle_options()
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

///|
test "bench bundle: effect-tiny library — full opt" (it : @bench.T) {
  let files : Map[String, String] = {}
  files["effect.ts"] = effect_lib_source
  files["entry.ts"] =
    #|import { succeed, map, runSync } from "./effect";
    #|console.log(runSync(map(succeed(5), (n: number) => n * 2), null));
    #|
  let opts = full_opt_bundle_options()
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}
