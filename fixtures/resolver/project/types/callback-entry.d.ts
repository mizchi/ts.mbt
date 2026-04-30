export function emitEvent(
  label: string,
  count: number,
  listener: (label: string, count: number) => void,
): string;

export function maybeEmit(
  label: string,
  listener?: (label: string, count: number) => void,
): string;
