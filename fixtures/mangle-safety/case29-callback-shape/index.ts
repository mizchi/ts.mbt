// The names that escape here are read off a callback PARAMETER, not
// off anything an import touches. The host fills `row` in, so `rowId`
// and `rowCaption` are the host's names even though nothing in this
// file connects them to `HostList` syntactically.
export function collect(): string[] {
  const seen: string[] = [];
  HostList.each((row) => {
    seen.push(row.rowCaption + ":" + row.rowId);
  });
  return seen;
}
