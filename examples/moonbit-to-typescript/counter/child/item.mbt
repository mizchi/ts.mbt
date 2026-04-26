///|
pub struct Item {
  id : Int
  name : String
}

///|
pub fn make_item(id : Int, name : String) -> Item {
  { id, name }
}

///|
pub fn Item::display(self : Item) -> String {
  self.name + "#" + self.id.to_string()
}
