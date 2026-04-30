extern "js" fn test_number() -> @sut.JSValue =
  #| () => 2

extern "js" fn test_object() -> @sut.JSValue =
  #| () => ({ value: "ok" })

extern "js" fn test_vitest_vi(vi : @sut.VitestUtils) -> Unit =
  #| (vi) => {
  #|   const fn = vi.fn((x) => x + 1);
  #|   if (fn(2) !== 3) throw new Error("unexpected vi.fn output");
  #|   if (!vi.isMockFunction(fn)) throw new Error("expected vi.fn mock");
  #| }

fn main {
  let expect = @sut.get_expect()
  expect._call_(@sut.unsafeCast(test_number()), None).toBe(
    @sut.unsafeCast(test_number()),
  )
  expect._call_(@sut.unsafeCast(test_object()), None).toEqual(
    @sut.unsafeCast(test_object()),
  )
  test_vitest_vi(@sut.get_vi())
}
