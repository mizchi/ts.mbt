export default async (mod) => ({
  report: mod.report,
  exportedArity: mod.exported.length,
  exportedResult: mod.exported(1, 9),
});
