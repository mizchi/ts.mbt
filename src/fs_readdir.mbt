///|
/// `@fs.readdir`, returning an `Array` that works on every backend.
///
/// On `js`, `mizchi/x/fs` (0.6.1) declares `readdir`'s result as
/// `Array[String]` and its extern hands back the plain JS array Node
/// produced. That was the same thing until moonc v0.10.20, which
/// represents a MoonBit `Array` on `js` as an object `{ buf, len }` — so
/// iterating the result found nothing, and the bundler's module
/// resolution and `-p`'s file walk both saw empty directories. A plain JS
/// array IS a `FixedArray` on this backend under every toolchain, so the
/// `js` arm reads the value as one and converts. Remove once `mizchi/x`
/// returns a `FixedArray` from its extern.
#cfg(target="js")
async fn fs_readdir(path : String, sort~ : Bool = false) -> Array[String] {
  let raw = @fs.readdir(
    path,
    include_hidden=false,
    include_special=false,
    sort~,
  )
  Array::from_fixed_array(fs_readdir_js_array(raw))
}

///|
#cfg(target="js")
fn[A, B] fs_readdir_js_array(value : A) -> B = "%identity"

///|
#cfg(not(target="js"))
async fn fs_readdir(path : String, sort~ : Bool = false) -> Array[String] {
  @fs.readdir(path, include_hidden=false, include_special=false, sort~)
}
