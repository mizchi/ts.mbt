// The consumer, and deliberately outside the bundle: it calls each
// payload's method after the bundle is compiled, so nothing inside names
// them and only the export surface can have kept them.
//
// Each holder has its OWN payload class with its OWN method name. With
// one shared payload class this driver passed even with the fix reverted,
// because `prop_assigns` is keyed by receiver NAME and `this` is the
// union of every class — so the control holder's working spelling kept
// the shared method for everybody.
export default async (mod) => ({
  coalesce: mod.coalesce.inner.readCoalesce("k"),
  or: mod.or.inner.readOr("k"),
  literalKey: mod.literalKey.inner.readLiteralKey("k"),
  plain: mod.plain.inner.readPlain("k"),
  readThrough: mod.fillBag().readThrough("k"),
  bagCount: mod.bagCount(),
});
