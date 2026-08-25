// The text is built here, outside the bundle, so the key names in it
// are fixed no matter what the mangler does inside.
export default async (mod) => ({
  load: mod.load('{"retryCount":3,"timeoutMs":250}'),
});
