import { describe, it, expect, vi } from "vitest";
describe("x", () => {
  it("works", async () => {
    const fn = vi.fn((a: number) => a * 2);
    expect(fn(2)).toBe(4);
    expect(fn).toHaveBeenCalledWith(2);
    await expect(Promise.resolve(1)).resolves.toBe(1);
  });
});
