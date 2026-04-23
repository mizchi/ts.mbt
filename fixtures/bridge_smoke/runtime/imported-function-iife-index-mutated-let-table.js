export default (function() {
  let INDEXES = [0, 1];
  let KEYS = {
    nested: ["version", "build"],
  };
  INDEXES[0] = 0;
  let TABLES = { INDEXES, KEYS };
  return TABLES;
})();
