import { publish } from "ext-bus";

// The value that crosses the boundary carries a declared shape. A
// foreign callee can only legally read `topic` / `body` — anything else
// would already be a type error on the consumer's side — so those two
// names are the whole reservation.
interface Envelope {
  topic: string;
  body: string;
}

// Bookkeeping that never leaves. Before named types were resolved, the
// crossing above widened to the wildcard and dragged these along with
// it: the annotation an ordinary TypeScript codebase writes did
// nothing, while an inline object type worked.
interface Ledger {
  pendingCount: number;
  lastTopic: string;
}

const ledger: Ledger = { pendingCount: 0, lastTopic: "" };

export function send(topic: string, body: string): number {
  ledger.pendingCount = ledger.pendingCount + 1;
  ledger.lastTopic = topic;
  const envelope: Envelope = { topic, body };
  publish(envelope);
  return ledger.pendingCount;
}

export function lastTopicSeen(): string {
  return ledger.lastTopic;
}
