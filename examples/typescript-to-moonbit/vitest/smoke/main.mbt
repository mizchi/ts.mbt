extern "js" fn test_vitest_expect(expect : @sut.JSValue) -> Unit =
  #| (expect) => {
  #|   expect(1 + 1).toBe(2);
  #|   expect({ value: "ok" }).toEqual({ value: "ok" });
  #| }

extern "js" fn test_vitest_assert(assert_ : @sut.JSValue) -> Unit =
  #| (assert_) => {
  #|   assert_.equal("a".toUpperCase(), "A");
  #| }

extern "js" fn test_vitest_vi(vi : @sut.JSValue) -> Unit =
  #| (vi) => {
  #|   const fn = vi.fn((x) => x + 1);
  #|   if (fn(2) !== 3) throw new Error("unexpected vi.fn output");
  #|   if (!vi.isMockFunction(fn)) throw new Error("expected vi.fn mock");
  #| }

fn main {
  test_vitest_expect(@sut.unsafeCast(@sut.get_expect()))
  test_vitest_assert(@sut.unsafeCast(@sut.get_assert()))
  test_vitest_vi(@sut.unsafeCast(@sut.get_vi()))
}

