///|
/// Auto-generated glue wrappers for MoonBit JS package output.

pub fn create(arg0 : String, arg1 : @tsmbt_source_child.Item) -> @tsmbt_source.Counter {
  @tsmbt_source.create(arg0, arg1)
}

pub fn summarize(arg0 : @tsmbt_source.Counter) -> String {
  @tsmbt_source.summarize(arg0)
}

pub fn tsmbt_source_child_item_tag(arg0 : @tsmbt_source_child.Item) -> @tsmbt_source_child_grand.Tag {
  @tsmbt_source_child.item_tag(arg0)
}

pub fn tsmbt_source_child_make_item(arg0 : Int, arg1 : String) -> @tsmbt_source_child.Item {
  @tsmbt_source_child.make_item(arg0, arg1)
}

pub fn tsmbt_source_child_grand_make_tag(arg0 : String) -> @tsmbt_source_child_grand.Tag {
  @tsmbt_source_child_grand.make_tag(arg0)
}