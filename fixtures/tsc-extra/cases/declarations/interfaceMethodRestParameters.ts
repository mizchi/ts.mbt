// @strict: true
// @target: esnext

// An interface or object-type method's rest parameter takes any number of
// arguments of its element type, through an alias as well. Each argument is
// still checked, and a plain array parameter is still one argument.

type ArgsType = any[];
interface ILog {
  debug(...args: ArgsType): void;
  info(...xs: number[]): void;
  plain(xs: number[]): void;
}
declare const log: ILog;
declare const obj: { warn(...xs: string[]): void };

function okAliasedAnyRest() { log.debug("a", 1, true); }
function okNoRestArguments() { log.debug(); log.info(); }
function okNumberRest() { log.info(1, 2, 3); }
function okObjectTypeRest() { obj.warn("a", "b"); }
function okPlainArray() { log.plain([1]); }
function badRestElementType() { log.info("no"); }
function badObjectTypeRestElement() { obj.warn(1); }
function badPlainArrayGivenElement() { log.plain(1); }
