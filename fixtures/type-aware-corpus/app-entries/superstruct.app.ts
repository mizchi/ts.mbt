// superstruct, used the way its Readme's first example uses it, plus
// the non-throwing `validate` so the failure path is observed too.
//
// Every export is a scalar.

import {
  array,
  assert,
  is,
  number,
  object,
  string,
  validate,
} from "./src/index.ts";

const Article = object({
  id: number(),
  title: string(),
  tags: array(string()),
  author: object({
    id: number(),
  }),
});

const data = {
  id: 34,
  title: "Hello World",
  tags: ["news", "features"],
  author: { id: 1 },
};

function check(input: unknown): string {
  const [failure, value] = validate(input, Article);
  if (failure) {
    return "fail:" +
      failure.failures().map((f) => f.path.join(".") + "!" + f.type).join(",");
  }
  return "ok:" + value.title + "/" + value.tags.length;
}

let threw = "none";
try {
  assert({ id: "34", title: 5, tags: "news", author: {} }, Article);
} catch (e) {
  threw = (e as Error).message.slice(0, 60);
}

export const valid: string = check(data);
export const invalid: string = check({ id: "x", title: 1, tags: [2], author: 3 });
export const guard: boolean = is(data, Article);
export const guardFails: boolean = is({ id: 1 }, Article);
export const thrown: string = threw;
