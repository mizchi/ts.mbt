// Generator functions (AOT state machine)

function* range(start: number, end: number) {
  for (let i = start; i < end; i = i + 1) {
    yield i;
  }
}

function* countdown(n: number) {
  while (n > 0) {
    yield n;
    n = n - 1;
  }
}

function* fibonacci() {
  let a = 0;
  let b = 1;
  while (true) {
    yield a;
    let tmp = a + b;
    a = b;
    b = tmp;
  }
}

function* take(n: number, gen: Generator<number>) {
  for (let i = 0; i < n; i = i + 1) {
    const result = gen.next();
    if (result.done) {
      return;
    }
    yield result.value;
  }
}

function* map(gen: Generator<number>, f: (x: number) => number) {
  for (const x of gen) {
    yield f(x);
  }
}

// Simple generator that yields fixed values
function* simpleYield() {
  yield 1;
  yield 2;
  yield 3;
}

// Generator with conditional yield
function* conditionalYield(n: number) {
  if (n > 0) {
    yield n;
    yield n * 2;
  } else {
    yield 0;
  }
}
