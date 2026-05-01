export interface OrderedListProps {
  type?: "1" | "a" | "A" | "i" | "I" | undefined;
  setMode(mode: "manual" | "nextTimerAsync"): void;
}

export declare function setListType(type: "1" | "a" | "A"): "i" | "I";
