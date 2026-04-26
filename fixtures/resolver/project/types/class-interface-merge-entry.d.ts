export interface Location {
  line: number;
  column: number;
}

export declare class Location {
  constructor(start: number);
  start: number;
}
