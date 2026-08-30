// ts-pattern, used the way its README's first example uses it.
//
// The usage is copied from the README rather than invented, for the
// reason given in `app-entries/README.md`: an entry I designed would
// be an entry designed to make the passes fire.
//
// Every export is a scalar, so no property name declared here crosses
// the bundle boundary.

import { match, P } from "./src/index.ts";

type State =
  | { status: "idle" }
  | { status: "loading"; startTime: number }
  | { status: "success"; data: string }
  | { status: "error"; error: string };

type Event =
  | { type: "fetch" }
  | { type: "success"; data: string }
  | { type: "error"; error: string }
  | { type: "cancel" };

const now = 1_700_000_000_000;

const reducer = (state: State, event: Event): State =>
  match<[State, Event], State>([state, event])
    .with([{ status: "loading" }, { type: "success" }], ([, e]) => ({
      status: "success",
      data: (e as { data: string }).data,
    }))
    .with([{ status: "loading" }, { type: "error", error: P.select() }], (
      error,
    ) => ({ status: "error", error: error as string }))
    .with([{ status: P.not("loading") }, { type: "fetch" }], () => ({
      status: "loading",
      startTime: now,
    }))
    .with(
      [{ status: "loading", startTime: P.when((t) => t + 2000 < now) }, {
        type: "cancel",
      }],
      () => ({ status: "idle" }),
    )
    .with(P._, () => state)
    .exhaustive();

function label(s: State): string {
  return match(s)
    .with({ status: "idle" }, () => "idle")
    .with({ status: "loading" }, ({ startTime }) => "loading@" + startTime)
    .with({ status: "success" }, ({ data }) => "success:" + data)
    .with({ status: "error" }, ({ error }) => "error:" + error)
    .exhaustive();
}

const trace: string[] = [];
let s: State = { status: "idle" };
for (
  const e of [
    { type: "fetch" },
    { type: "success", data: "payload" },
    { type: "fetch" },
    { type: "error", error: "boom" },
    { type: "cancel" },
  ] as Event[]
) {
  s = reducer(s, e);
  trace.push(label(s));
}

export const log: string = trace.join("|");
export const final: string = s.status;
