// Drive the export so the record actually reaches the host stub.
export default async (mod) => ({ report: mod.report(21) });
