import * as Y from "yjs";
const doc = new Y.Doc();
const text = doc.getText("t");
text.insert(0, "hello");
export const len: number = text.length;
export const s: string = text.toString();
export const update: Uint8Array = Y.encodeStateAsUpdate(doc);
