import { useState } from "react";

// `useState("")` infers `string` state.
export function C() {
  const [v] = useState("");
  const bad: number = v;
  return bad;
}
