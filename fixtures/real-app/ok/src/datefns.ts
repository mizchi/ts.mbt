import { format, addDays, differenceInDays, parseISO, isValid } from "date-fns";
import type { Locale } from "date-fns";
export function label(d: Date, locale?: Locale): string { return format(addDays(d, 1), "yyyy-MM-dd", { locale }); }
export const gap: number = differenceInDays(new Date(), parseISO("2020-01-01"));
export const ok: boolean = isValid(new Date());
