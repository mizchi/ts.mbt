export interface RuntimePoint {
  x: number;
  y: number;
}

export function scalePoint(point: RuntimePoint, factor: number): RuntimePoint {
  return {
    x: point.x * factor,
    y: point.y * factor,
  };
}
