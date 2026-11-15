// @strict: true

// `typeFromPropertyAssignment36` pins TS2565 for an expando property assigned
// in only one branch and read after it. The check applies to a dotted WRITE
// and to both READ spellings — but an element-access WRITE escapes it, so the
// same possibly-unassigned read is accepted once the assignment is spelled
// `fn["q"] = 1`.
declare const cond: boolean;

function viaDot() {}
if (cond) { viaDot.q = 1; }
viaDot.q;        // TS2565
viaDot["q"];     // TS2565

function viaElement() {}
if (cond) { viaElement["q"] = 1; }
viaElement.q;    // accepted — expected TS2565
viaElement["q"]; // accepted — expected TS2565
