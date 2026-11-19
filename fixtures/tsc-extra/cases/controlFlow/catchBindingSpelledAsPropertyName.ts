// @strict: true
// @target: esnext

// Under `useUnknownInCatchVariables` (on with `strict`), a catch binding is
// `unknown`. Passing it along is fine, and so is a property spelled like it:
// `console.error("…", error)` neither reads nor calls the binding. Reading a
// member of it or calling it is TS18046.

declare const log: { error(m: string, e: unknown): void } | undefined;

export function okPassedToConsoleError() { try { JSON.parse("x"); } catch (error) { console.error("x", error); } }
export function okPassedThroughOptionalCall() { try { JSON.parse("x"); } catch (error) { log?.error("x", error); } }
export function badMemberOfUnknown() { try { JSON.parse("x"); } catch (error) { return error.message; } }
export function badCallOfUnknown() { try { JSON.parse("x"); } catch (error) { return error(); } }
