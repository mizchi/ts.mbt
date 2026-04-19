///|
pub struct MoonBitTsBridgeBundle {
  entry_path : String
  module_spec : String
  decl_mbt : String
  ffi_mbt : String
  bridge_js : String
} derive(Debug)

///|
pub struct MoonBitTsBridgePackageBundle {
  entry_path : String
  module_spec : String
  moon_pkg_json : String
  bridge_mbti : String
  bridge_mbt : String
  bridge_js : String
} derive(Debug)

///|
fn render_bridge_pkg_json(needs_js_import : Bool) -> String {
  if needs_js_import {
    let content =
      #|{
      #|  "import": [
      #|    { "path": "mizchi/js/core", "alias": "js" }
      #|  ]
      #|}
    content
  } else {
    "{}"
  }
}

///|
fn bridge_bundle_needs_js_import(bundle : MoonBitTsBridgeBundle) -> Bool {
  bundle.ffi_mbt.contains("@js.")
}

///|
pub async fn emit_moonbit_ts_bridge_bundle_from_entry_path(
  entry_path : String,
  module_spec : String,
) -> MoonBitTsBridgeBundle raise ModuleGraphError {
  let decl_mbt = emit_moonbit_decl_from_entry_path(entry_path)
  let ffi_bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    entry_path, module_spec,
  )
  {
    entry_path,
    module_spec,
    decl_mbt,
    ffi_mbt: ffi_bundle.ffi_mbt,
    bridge_js: ffi_bundle.bridge_js,
  }
}

///|
pub async fn emit_moonbit_ts_bridge_package_bundle_from_entry_path(
  entry_path : String,
  module_spec : String,
) -> MoonBitTsBridgePackageBundle raise ModuleGraphError {
  let bundle = emit_moonbit_ts_bridge_bundle_from_entry_path(
    entry_path, module_spec,
  )
  {
    entry_path: bundle.entry_path,
    module_spec: bundle.module_spec,
    moon_pkg_json: render_bridge_pkg_json(bridge_bundle_needs_js_import(bundle)),
    bridge_mbti: bundle.decl_mbt,
    bridge_mbt: bundle.ffi_mbt,
    bridge_js: bundle.bridge_js,
  }
}
