import { addDays, format, differenceInDays, parseISO } from "date-fns";

const start = parseISO("2026-01-01T00:00:00Z");
const later = addDays(start, 100);
const diff = differenceInDays(later, start);
const formatted = format(later, "yyyy-MM-dd");

if (diff === 100 && formatted === "2026-04-11") {
  console.log("date-fns ok:", formatted, diff);
} else {
  console.log("date-fns fail:", formatted, diff);
}
