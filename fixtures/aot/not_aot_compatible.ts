// NOT AOT compatible - these should fail AOT check

// eval is not supported
function withEval(code: string) {
  return eval(code);
}

// with statement is not supported
function withWith(obj: any) {
  with (obj) {
    return x;
  }
}

// async functions not yet supported
async function asyncFunc() {
  return 42;
}

// await not yet supported
async function withAwait() {
  const result = await Promise.resolve(1);
  return result;
}

// Generator function expressions not supported in closures
function generatorInClosure() {
  const gen = function* () {
    yield 1;
  };
  return gen;
}

// yield inside closure not supported
function* yieldInClosure() {
  const f = () => {
    yield 1; // Error: yield in non-generator
  };
}
