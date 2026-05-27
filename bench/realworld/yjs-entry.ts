import * as Y from "yjs";

const doc = new Y.Doc();
const yarr = doc.getArray<string>("items");
const ymap = doc.getMap<number>("counts");

yarr.push(["a", "b", "c"]);
ymap.set("x", 42);

const arrLen = yarr.length;
const mapVal = ymap.get("x");

// Update via transaction.
doc.transact(() => {
  yarr.push(["d"]);
  ymap.set("y", 7);
});

const sumLen = yarr.length + ymap.size;

if (arrLen === 3 && mapVal === 42 && sumLen === 4 + 2) {
  console.log("yjs ok:", arrLen, mapVal, sumLen);
} else {
  console.log("yjs fail:", arrLen, mapVal, sumLen);
}
