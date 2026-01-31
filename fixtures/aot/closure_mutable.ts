// Closures with mutable captures (Phase 3)

function counter() {
  let count = 0;
  const inc = () => { count = count + 1; };
  inc();
  inc();
  inc();
  return count; // Should return 3
}

function accumulator(initial: number) {
  let sum = initial;
  const add = (x: number) => { sum = sum + x; };
  add(10);
  add(20);
  add(30);
  return sum; // Should return initial + 60
}

function toggle() {
  let state = 0;
  const flip = () => {
    if (state === 0) {
      state = 1;
    } else {
      state = 0;
    }
  };
  flip();
  flip();
  flip();
  return state; // Should return 1
}

function multipleClosures() {
  let x = 0;
  const inc = () => { x = x + 1; };
  const dec = () => { x = x - 1; };
  const get = () => x;

  inc();
  inc();
  dec();
  return get(); // Should return 1
}

function nestedMutation(n: number) {
  let result = 0;
  const addN = () => { result = result + n; };

  for (let i = 0; i < 5; i = i + 1) {
    addN();
  }
  return result; // Should return n * 5
}
