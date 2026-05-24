// Public bundle / transform API.
//
// Re-exports the `mizchi/ts/transform` package's main entry points
// under stable names on `mizchi/ts` so library consumers can call
// the optimizer pipeline without reaching into the internal
// package. Three flavors are exposed:
//
//   - `bundle_source` — one TS source string in, one JS string out.
//     The simplest entry point; no module resolution.
//
//   - `bundle_files` — `Map[String, String]` virtual filesystem,
//     entry path, options. Returns the bundled JS + an optional
//     v3 source map. Same shape as `@transform.bundle_modules`.
//
//   - `BundleProfile` — preset opt levels (`development` /
//     `production` / `full`) so callers don't have to know the
//     internals of `BundleOptions`.

///|
pub(all) enum BundleProfile {
  // No optimization. Bundles modules, emits JS, nothing else.
  Development
  // Tree shake + class-method DCE. Safe set: changes are
  // structural (drop dead code) but don't touch identifier or
  // property names. Useful when consumers of the bundle still
  // need stable names for JSON / fetch / DOM interop.
  Production
  // Everything: tree-shake, mangle (id + property), auto-reserve,
  // method DCE, inline-immutable, const-fold. Smallest output.
  Full
} derive(Eq, Show)

///|
/// Build a `@transform.BundleOptions` value from a preset.
pub fn BundleProfile::to_options(self : BundleProfile) -> @transform.BundleOptions {
  match self {
    Development => @transform.BundleOptions::default()
    Production => {
      ..@transform.BundleOptions::default(),
      tree_shake: true,
      drop_unused_methods: true,
    }
    Full => {
      ..@transform.BundleOptions::default(),
      tree_shake: true,
      mangle: Some(
        @transform.ManglerConfig::default().with_mangle_properties(true),
      ),
      auto_reserve: true,
      drop_unused_methods: true,
      inline_immutable: true,
      fold_constants: true,
    }
  }
}

///|
/// Bundle a single TS source string at the given profile. Returns
/// the emitted JS, or an error message if parsing / bundling
/// failed. Useful for one-off transforms with no module imports.
pub fn bundle_source(
  source : String,
  profile~ : BundleProfile = Development,
) -> Result[String, String] {
  let files : Map[String, String] = { "entry.ts": source }
  match @transform.bundle_modules(files, "entry.ts", profile.to_options()) {
    Ok(out) => Ok(out.js)
    Err(e) => Err(e)
  }
}

///|
/// Bundle a virtual file system at the given profile. `files` maps
/// path → source text; `entry` is the entry-point path. Returns
/// the bundle output (JS + optional source map + module list).
pub fn bundle_files(
  files : Map[String, String],
  entry : String,
  profile~ : BundleProfile = Development,
  with_sourcemap~ : Bool = false,
) -> Result[@transform.BundleOutput, String] {
  let mut opts = profile.to_options()
  if with_sourcemap {
    opts = { ..opts, with_sourcemap: true }
  }
  @transform.bundle_modules(files, entry, opts)
}

///|
/// Lower-level escape hatch: bundle with an arbitrary
/// `BundleOptions`. Pass-through to `@transform.bundle_modules`.
pub fn bundle_files_with(
  files : Map[String, String],
  entry : String,
  options : @transform.BundleOptions,
) -> Result[@transform.BundleOutput, String] {
  @transform.bundle_modules(files, entry, options)
}
