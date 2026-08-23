import type { ActorProfile, KindSummary, RawEvent } from "./domain.js";

interface KindAccumulator {
  eventKind: string;
  occurrences: number;
  byteTotal: number;
  peakBytes: number;
}

export interface IndexedWindow {
  profiles: ActorProfile[];
  kinds: KindSummary[];
  windowStartMs: number;
  windowEndMs: number;
}

export function indexEvents(events: RawEvent[]): IndexedWindow {
  const byActor = new Map<string, ActorProfile>();
  const byKind = new Map<string, KindAccumulator>();
  let windowStartMs = Number.MAX_SAFE_INTEGER;
  let windowEndMs = 0;
  for (const ev of events) {
    if (ev.occurredAtMs < windowStartMs) {
      windowStartMs = ev.occurredAtMs;
    }
    if (ev.occurredAtMs > windowEndMs) {
      windowEndMs = ev.occurredAtMs;
    }
    const existing = byActor.get(ev.actorHandle);
    if (existing === undefined) {
      byActor.set(ev.actorHandle, {
        actorHandle: ev.actorHandle,
        displayLabel: ev.actorHandle.replace("@", ""),
        trustScore: 50,
        eventCount: 1,
        totalBytes: ev.payloadBytes,
        firstSeenMs: ev.occurredAtMs,
        lastSeenMs: ev.occurredAtMs,
      });
    } else {
      existing.eventCount = existing.eventCount + 1;
      existing.totalBytes = existing.totalBytes + ev.payloadBytes;
      if (ev.occurredAtMs < existing.firstSeenMs) {
        existing.firstSeenMs = ev.occurredAtMs;
      }
      if (ev.occurredAtMs > existing.lastSeenMs) {
        existing.lastSeenMs = ev.occurredAtMs;
      }
    }
    const kindAcc = byKind.get(ev.eventKind);
    if (kindAcc === undefined) {
      byKind.set(ev.eventKind, {
        eventKind: ev.eventKind,
        occurrences: 1,
        byteTotal: ev.payloadBytes,
        peakBytes: ev.payloadBytes,
      });
    } else {
      kindAcc.occurrences = kindAcc.occurrences + 1;
      kindAcc.byteTotal = kindAcc.byteTotal + ev.payloadBytes;
      if (ev.payloadBytes > kindAcc.peakBytes) {
        kindAcc.peakBytes = ev.payloadBytes;
      }
    }
  }
  const profiles: ActorProfile[] = [];
  for (const p of byActor.values()) {
    profiles.push(p);
  }
  profiles.sort((a, b) => (a.actorHandle < b.actorHandle ? -1 : 1));
  const kinds: KindSummary[] = [];
  for (const k of byKind.values()) {
    kinds.push({
      eventKind: k.eventKind,
      occurrences: k.occurrences,
      averageBytes: Math.round(k.byteTotal / k.occurrences),
      peakBytes: k.peakBytes,
    });
  }
  kinds.sort((a, b) => (a.eventKind < b.eventKind ? -1 : 1));
  return { profiles, kinds, windowStartMs, windowEndMs };
}
