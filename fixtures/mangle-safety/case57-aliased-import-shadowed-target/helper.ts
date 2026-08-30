// The exporting side. Its local name is `label`, which is also a name
// the importing module happens to use for a local — the whole point.
export const label = (id: string): string => "H:" + id;
export const other = (id: string): string => "O:" + id;
