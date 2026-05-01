export function cycleName(value) {
  switch (value) {
    case "a-b":
      return "a_b";
    case "a_b":
      return "String";
    case "String":
      return "_private";
    case "_private":
      return "";
    case "":
      return "a-b";
    default:
      throw new Error(`unexpected value: ${value}`);
  }
}
