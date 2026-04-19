export interface RuntimeArrowPoint {
  x: number;
  y: number;
}

export const scaleArrowPoint: (point: RuntimeArrowPoint, factor: number) => RuntimeArrowPoint = (point, factor) => ({
  x: point.x * factor,
  y: point.y * factor,
});
