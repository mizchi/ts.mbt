///|
pub struct Counter {
  label : String
  item : @child.Item
}

///|
pub fn create(label : String, item : @child.Item) -> Counter {
  { label, item }
}

///|
pub fn summarize(counter : Counter) -> String {
  counter.label + ":" + counter.item.display()
}

///|
pub fn Counter::label(self : Counter) -> String {
  self.label
}
