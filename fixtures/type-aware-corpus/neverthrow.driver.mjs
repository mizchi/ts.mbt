// Result / ResultAsync: the combinators, the error channel, and the
// `match` surface. The Ok/Err classes are what the export-surface walk
// blew up on, so this driver exists to prove the memo did not lose any
// of their members.
import { ok, err, okAsync, errAsync, Result, ResultAsync, fromThrowable, fromPromise, safeTry } from "./target.mjs";
const out = [];
const good = ok(2);
const bad = err("nope");
out.push([good.isOk(), good.isErr(), bad.isOk(), bad.isErr()]);
out.push(good.map((n) => n * 3)._unsafeUnwrap());
out.push(bad.mapErr((e) => e + "!").unwrapOr("fallback"));
out.push(good.andThen((n) => (n > 1 ? ok(n + 1) : err("small")))._unsafeUnwrap());
out.push(good.match((v) => "ok:" + v, (e) => "err:" + e));
out.push(bad.match((v) => "ok:" + v, (e) => "err:" + e));
out.push(Result.combine([ok(1), ok(2), ok(3)])._unsafeUnwrap());
out.push(Result.combine([ok(1), err("x"), ok(3)]).isErr());
out.push(Result.combineWithAllErrors([err("a"), err("b")])._unsafeUnwrapErr());
const throwing = fromThrowable((n) => { if (n < 0) throw new Error("neg"); return n; }, (e) => "caught:" + e.message);
out.push(throwing(5)._unsafeUnwrap(), throwing(-1)._unsafeUnwrapErr());
out.push((await okAsync(7).map((n) => n + 1))._unsafeUnwrap());
out.push((await errAsync("bad").mapErr((e) => e.toUpperCase()))._unsafeUnwrapErr());
out.push((await fromPromise(Promise.resolve(1), (e) => e))._unsafeUnwrap());
out.push((await fromPromise(Promise.reject(new Error("r")), (e) => e.message))._unsafeUnwrapErr());
out.push((await safeTry(async function* () { return ok((yield* okAsync(4)) + 1); }))._unsafeUnwrap());
console.log(JSON.stringify(out, null, 1));
