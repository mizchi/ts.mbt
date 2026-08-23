import type { RawEvent } from "./domain.js";

interface FieldProblem {
  fieldName: string;
  problemText: string;
}

export interface ValidationOutcome {
  accepted: RawEvent[];
  problems: FieldProblem[];
}

function isNonEmptyString(v: unknown): boolean {
  return typeof v === "string" && (v as string).length > 0;
}

export function validateEvents(rows: unknown[]): ValidationOutcome {
  const accepted: RawEvent[] = [];
  const problems: FieldProblem[] = [];
  for (const row of rows) {
    if (typeof row !== "object" || row === null) {
      problems.push({ fieldName: "row", problemText: "not an object" });
      continue;
    }
    const candidate = row as Record<string, unknown>;
    let bad = false;
    for (const key of ["eventId", "actorHandle", "eventKind"]) {
      if (!isNonEmptyString(candidate[key])) {
        problems.push({ fieldName: key, problemText: "missing or empty" });
        bad = true;
      }
    }
    if (typeof candidate.payloadBytes !== "number" || candidate.payloadBytes < 0) {
      problems.push({ fieldName: "payloadBytes", problemText: "not a non-negative number" });
      bad = true;
    }
    if (typeof candidate.occurredAtMs !== "number") {
      problems.push({ fieldName: "occurredAtMs", problemText: "not a number" });
      bad = true;
    }
    if (bad) {
      continue;
    }
    accepted.push({
      eventId: candidate.eventId as string,
      actorHandle: candidate.actorHandle as string,
      eventKind: candidate.eventKind as string,
      payloadBytes: candidate.payloadBytes as number,
      occurredAtMs: candidate.occurredAtMs as number,
    });
  }
  return { accepted, problems };
}
