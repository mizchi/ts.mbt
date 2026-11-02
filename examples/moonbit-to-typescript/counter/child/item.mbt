///|
pub struct Item {
  id : Int32
  name : String
}

///|
pub fn make_item(id : Int32, name : String) -> Item {
  { id, name, }
}

///|
pub fn item_tag(item : Item) -> @grand.Tag {
  @grand.make_tag(item.display())
}

///|
pub fn Item::display(self : Item) -> String {
  self.name + "#" + self.id.to_string()
}
