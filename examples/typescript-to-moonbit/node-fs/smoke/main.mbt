extern "js" fn node_fs_path_like() -> @sut.PathLike =
  #| () => process.cwd() + "/node-fs-smoke.txt"

extern "js" fn node_fs_path_or_fd() -> @sut.PathOrFileDescriptor =
  #| () => process.cwd() + "/node-fs-smoke.txt"

extern "js" fn node_fs_data() -> @sut.JSValue =
  #| () => "hello from moonbit"

extern "js" fn node_fs_to_string(data : @sut.NonSharedBuffer) -> String =
  #| (data) => data.toString("utf8")

fn main {
  let path = node_fs_path_like()
  let file = node_fs_path_or_fd()
  if @sut.existsSync(path) {
    @sut.unlinkSync(path)
  }
  @sut.writeFileSync(file, node_fs_data(), None)
  if !@sut.existsSync(path) {
    abort("expected file to exist")
  }
  let data = @sut.readFileSync(file, None)
  if node_fs_to_string(data) != "hello from moonbit" {
    abort("unexpected file content")
  }
  @sut.unlinkSync(path)
  if @sut.existsSync(path) {
    abort("expected file to be removed")
  }
}
