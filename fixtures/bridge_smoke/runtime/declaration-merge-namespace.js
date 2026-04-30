export function make(input) {
  return `make:${input}`;
}

make.version = "1.0.0";
make.withOptions = (input, options) => {
  return options?.uppercase ? input.toUpperCase() : input;
};

export class Tool {
  constructor(name) {
    this.name = name;
  }
}

Tool.version = "2.0.0";
Tool.parse = (input) => new Tool(input);

export const settings = {
  mode: "prod",
  defaultMode: "prod",
  normalize(input) {
    return input.trim().toLowerCase();
  },
};
