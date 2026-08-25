import type { ActorProfile, ScoredActor } from "./domain.js";

interface ScoringWeights {
  volumeWeight: number;
  burstWeight: number;
  trustWeight: number;
  flagThreshold: number;
}

const defaultWeights: ScoringWeights = {
  volumeWeight: 0.5,
  burstWeight: 0.35,
  trustWeight: 0.15,
  flagThreshold: 40,
};

function burstOf(profile: ActorProfile): number {
  const spanMs = profile.lastSeenMs - profile.firstSeenMs;
  if (spanMs <= 0) {
    return profile.eventCount;
  }
  return Math.round((profile.eventCount / (spanMs / 1000)) * 100) / 100;
}

export function scoreActors(profiles: ActorProfile[]): ScoredActor[] {
  const weights = defaultWeights;
  let maxBytes = 1;
  for (const p of profiles) {
    if (p.totalBytes > maxBytes) {
      maxBytes = p.totalBytes;
    }
  }
  const scored: ScoredActor[] = [];
  for (const profile of profiles) {
    const volumeRank = Math.round((profile.totalBytes / maxBytes) * 100);
    const burstFactor = burstOf(profile);
    const composite =
      volumeRank * weights.volumeWeight +
      burstFactor * weights.burstWeight +
      profile.trustScore * weights.trustWeight;
    scored.push({
      profile,
      burstFactor,
      volumeRank,
      flagged: composite > weights.flagThreshold,
    });
  }
  scored.sort((a, b) => b.volumeRank - a.volumeRank);
  return scored;
}
