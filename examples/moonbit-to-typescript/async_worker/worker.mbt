///|
pub struct Worker {
  name : String
}

///|
pub async fn Worker::new(name : String) -> Worker {
  { name, }
}

///|
pub async fn Worker::load(self : Worker, key? : String) -> String {
  match key {
    Some(key) => self.name + ":" + key
    None => self.name + ":default"
  }
}
