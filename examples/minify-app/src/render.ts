import type { Report } from "./domain.js";

interface RenderOptions {
  maxActorLines: number;
  showFlagsOnly: boolean;
}

const renderOptions: RenderOptions = { maxActorLines: 3, showFlagsOnly: false };

export function renderReport(report: Report): string {
  const lines: string[] = [];
  lines.push(
    "window " + report.windowStartMs + ".." + report.windowEndMs +
      " actors=" + report.actorCount + " rejected=" + report.rejectedCount,
  );
  for (const kind of report.kindBreakdown) {
    lines.push(
      "  kind " + kind.eventKind + " n=" + kind.occurrences +
        " avg=" + kind.averageBytes + " peak=" + kind.peakBytes,
    );
  }
  let shown = 0;
  for (const actor of report.topActors) {
    if (shown >= renderOptions.maxActorLines) {
      break;
    }
    if (renderOptions.showFlagsOnly && !actor.flagged) {
      continue;
    }
    lines.push(
      "  actor " + actor.profile.displayLabel +
        " rank=" + actor.volumeRank +
        " burst=" + actor.burstFactor +
        (actor.flagged ? " FLAGGED" : ""),
    );
    shown = shown + 1;
  }
  return lines.join("\n");
}
