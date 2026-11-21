// @strict: true
// @target: esnext

// An unannotated method's return type is inferred from its body at a call,
// so `getData() { return this._data }` returns the field's declared type
// and `getN() { return 1 }` returns `number`.

type Nullable<T> = T | null | undefined | void;
interface Page { pageWidth: number }
interface Data { pages: Page[] }
export class Skel {
  private _data: Nullable<Data>;
  private _n = 1;
  getData() { return this._data; }
  getN() { return this._n; }
  getLit() { return 1; }
}
export function okNarrowedThroughGetter(s: Skel, i: number) {
  const data = s.getData();
  if (data == null) { return; }
  const { pages } = data;
  let p: Nullable<Page> = null;
  p = pages[i];
  return p.pageWidth;
}
export function badGetterField(s: Skel) { const q: string = s.getData(); return q; }
export function badGetterDestructured(s: Skel) {
  const data = s.getData();
  if (data == null) { return; }
  const { pages } = data;
  const q: string = pages;
  return q;
}
export function badInferredField(s: Skel) { const q: string = s.getN(); return q; }
export function badLiteralReturn(s: Skel) { const q: string = s.getLit(); return q; }
