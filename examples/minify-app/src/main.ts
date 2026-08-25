// Application entry: exports nothing. Door 1 (the export surface) is
// empty, which is the case the escape analysis was designed for and the
// case a library can never be.
import type { Report } from "./domain.js";
import { indexEvents } from "./index_store.js";
import { renderReport } from "./render.js";
import { scoreActors } from "./score.js";
import { validateEvents } from "./validate.js";

const sampleRows: unknown[] = [];
const kinds = ["push", "review", "merge", "comment"];
for (let i = 0; i < 400; i++) {
  sampleRows.push({
    eventId: "e" + i,
    actorHandle: "@user" + (i % 17),
    eventKind: kinds[i % kinds.length],
    payloadBytes: 100 + ((i * 37) % 900),
    occurredAtMs: 1700000000000 + i * 250,
  });
}
sampleRows.push({ eventId: "", actorHandle: "@bad", eventKind: "push" });
sampleRows.push(null);

const outcome = validateEvents(sampleRows);
const indexed = indexEvents(outcome.accepted);
const scored = scoreActors(indexed.profiles);
const report: Report = {
  windowStartMs: indexed.windowStartMs,
  windowEndMs: indexed.windowEndMs,
  actorCount: indexed.profiles.length,
  kindBreakdown: indexed.kinds,
  topActors: scored,
  rejectedCount: outcome.problems.length,
};
console.log(renderReport(report));
