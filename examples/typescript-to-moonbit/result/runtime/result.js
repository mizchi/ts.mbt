export function parseUser(input) {
  return {
    value: { id: input, name: `user:${input}` },
    isOk() {
      return true;
    },
  };
}

export function fetchUser(id) {
  return {
    promiseValue: { id, name: `user:${id}` },
    isOk() {
      return true;
    },
  };
}
