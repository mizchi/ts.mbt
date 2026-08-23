// Domain shapes. An application declares a lot of these and exports
// none of them — which is the whole point of the measurement.
export interface RawEvent {
  eventId: string;
  actorHandle: string;
  eventKind: string;
  payloadBytes: number;
  occurredAtMs: number;
}

export interface ActorProfile {
  actorHandle: string;
  displayLabel: string;
  trustScore: number;
  eventCount: number;
  totalBytes: number;
  firstSeenMs: number;
  lastSeenMs: number;
}

export interface KindSummary {
  eventKind: string;
  occurrences: number;
  averageBytes: number;
  peakBytes: number;
}

export interface ScoredActor {
  profile: ActorProfile;
  burstFactor: number;
  volumeRank: number;
  flagged: boolean;
}

export interface Report {
  windowStartMs: number;
  windowEndMs: number;
  actorCount: number;
  kindBreakdown: KindSummary[];
  topActors: ScoredActor[];
  rejectedCount: number;
}
