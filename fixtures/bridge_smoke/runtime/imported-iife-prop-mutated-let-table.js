export default (() => {
  let INDEXES = [0, 1];
  let KEYS = {
    nested: ["version", "build"],
  };
  KEYS.nested = ["version", "build"];
  let TABLES = { INDEXES, KEYS };
  return TABLES;
})();
