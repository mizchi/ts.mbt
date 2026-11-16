import { format } from "date-fns";

// `format` returns a string.
export const bad: number = format(new Date(), "yyyy");
