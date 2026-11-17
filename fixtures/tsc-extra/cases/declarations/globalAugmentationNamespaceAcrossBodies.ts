// @strict: true
// @target: esnext

// A namespace is one scope across every body that declares it: a member
// declared in one `declare global` block's `namespace NodeJS` is visible,
// unqualified, inside another block's `namespace NodeJS` (how @types/node
// writes `interface ProcessEnv extends Dict<string>`). Values a module's
// `declare global` declares are globals.

export {};
declare global {
  namespace NodeJS {
    interface Dict<T> { [key: string]: T | undefined }
  }
}
declare global {
  namespace NodeJS {
    interface ProcessEnv extends Dict<string> { TZ?: string }
    interface Proc { env: ProcessEnv }
  }
  var proc: NodeJS.Proc;
  const APP_VERSION: string;
}

function okDeclaredMember() { const tz: string | undefined = proc.env.TZ; }
function okIndexSignatureFromOtherBody() { const v: string | undefined = proc.env.OTHER; }
function okGlobalConst() { const v: string = APP_VERSION; }
function badIndexSignatureValueType() { const n: number = proc.env.OTHER; }
function badGlobalConstType() { const n: number = APP_VERSION; }
