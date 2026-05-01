export function describeRead(path, options) {
  if (typeof path !== "string") throw new Error("path must be a string");
  if (typeof options.encoding !== "string") {
    throw new Error("encoding must arrive as a primitive string");
  }
  if (typeof options.flag !== "string") {
    throw new Error("flag must arrive as a primitive string");
  }
  if (options.encoding !== "utf8") {
    throw new Error(`unexpected encoding: ${options.encoding}`);
  }
  if (options.flag !== "r") {
    throw new Error(`unexpected flag: ${options.flag}`);
  }
  return "buffer";
}

export function nextFlag(flag) {
  if (flag === "r") return "w";
  if (flag === "w") return "a";
  return "r";
}

export function renderReactButton(props) {
  if (typeof props.type !== "string") {
    throw new Error("React button type must arrive as a primitive string");
  }
  if (props.type !== "submit") {
    throw new Error(`unexpected button type: ${props.type}`);
  }
  return "reset";
}

export function createHonoProbe(options) {
  if (typeof options.mode !== "string") {
    throw new Error("Hono mode must arrive as a primitive string");
  }
  if (options.mode !== "strict") {
    throw new Error(`unexpected Hono mode: ${options.mode}`);
  }
  return "loose";
}
