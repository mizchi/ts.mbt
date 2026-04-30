///|
pub struct Tag {
  value : String
}

///|
pub fn make_tag(value : String) -> Tag {
  { value, }
}

///|
pub fn Tag::label(self : Tag) -> String {
  self.value
}
