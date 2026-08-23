export default async (mod) => ({
  first: mod.send("orders", "one"),
  second: mod.send("events", "two"),
  last: mod.lastTopicSeen(),
});
