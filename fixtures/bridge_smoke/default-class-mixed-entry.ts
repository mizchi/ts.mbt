export default class Counter {
  count: number

  constructor(initial: number) {
    this.count = initial
  }

  inc(delta: number): number {
    return this.count + delta
  }
}

export const version: string = "v2"

export function surround(label: string, prefix: string): string {
  return `${prefix}${label}${prefix}`
}
