// The injectable IO boundary.
//
// Everything else in this package is deliberately filesystem-free, and
// the original `checkModuleGraph` ABI took that to its limit: the caller
// pre-resolved the whole program and handed over module sources plus the
// import edges between them. That is the right shape for a bundler
// plugin, which already holds every source in memory — and the wrong one
// for anybody else, because it makes module resolution the CALLER's
// problem before they can type-check a single file.
//
// So resolution moves in here and the IO moves OUT, behind a trait. This
// is TypeScript's own split: `LanguageServiceHost` supplies file access
// and the service does the resolving. A host is three questions —
// what are the root files, what text does this path hold, and what are
// the compiler options — and every one of them is answerable by an
// in-memory map, by Node's `fs`, by a bundler's virtual filesystem, or
// by a test fixture.
//
// A TRAIT rather than a struct of closures, for a reason this repo has
// paid for repeatedly: MoonBit requires an `impl` to supply every method,
// so a new host cannot silently inherit a default that fails open. That
// is the same compiler-driven completeness that made `TsFunc`'s
// `name_is_member_key` census exhaustive instead of a grep. The cost is
// that a host must be a named type; the benefit is that "one rule applied
// in some places" cannot happen at this boundary.
//
// It is also deliberately SYNCHRONOUS, and that is the reason this trait
// does not live in `src/parser` next to the resolver that already does
// filesystem IO. That resolver is `async` throughout — 26 `async fn`s over
// an async filesystem — so a sync trait cannot serve it, and an async one
// cannot serve a `LanguageServiceHost`, whose `readFile` is sync by
// design. Sharing one interface between them would mean guessing at an
// interface that fits neither. The two boundaries stay separate until
// something actually needs to cross both.

///|
/// The compiler options this package honours.
///
/// Deliberately not a mirror of `tsc`'s option set. The CLI accepts ~90
/// `tsc` flags it has no behaviour for and reports them as such (see
/// `tsc_options.mbt`), which is the right trade for a drop-in command
/// line and the wrong one for a library: a field here that nothing reads
/// is a promise to a caller that we silently break. Every field below
/// changes what the checker does.
pub(all) struct MtscCompilerOptions {
  /// Parse JSX syntax in files whose extension does not already imply it.
  ///
  /// `.tsx` and `.jsx` always allow JSX regardless of this flag, the way
  /// `tsc` decides it from the extension; this covers a `.ts` file that
  /// the embedding tool knows to be JSX anyway.
  jsx : Bool
}

///|
/// The IO a program needs, supplied by the embedding tool.
///
/// Implement all three. There is no default for any of them, which is
/// the point of the trait — see the file header.
pub trait MtscHost {
  /// The text of `path`, or `None` when there is nothing readable there.
  ///
  /// `None` is also how the resolver learns that a candidate path does
  /// not exist, so this doubles as the existence check and there is no
  /// separate `file_exists` to disagree with it. Callers see each path
  /// at most once per operation — `MtscSourceCache` memoizes both hits
  /// and misses, because resolution probes many candidates per import
  /// and a host backed by real IO pays a syscall for each.
  fn read_file(Self, String) -> String?

  /// The program's root files, as paths `read_file` accepts.
  ///
  /// Everything these import is discovered from them, so a host lists
  /// entry points rather than the whole tree.
  fn script_file_names(Self) -> Array[String]

  /// The directory a relative root file name is resolved against.
  fn current_directory(Self) -> String

  /// The options above.
  fn compilation_settings(Self) -> MtscCompilerOptions
}

// ---------------------------------------------------------------------------
// In-memory host
// ---------------------------------------------------------------------------

///|
/// A host over a map of path to source text.
///
/// Works on every backend, which is what makes it more than a test
/// double: the native test suite drives the language service through
/// this host, so the code a JavaScript caller reaches is the same code
/// `moon test` covers. A bundler plugin holding its modules in memory
/// wants exactly this too, and gets resolution for free — which is what
/// the old `checkModuleGraph` made it compute for itself.
///
/// Constructed as a record literal so every field is stated at the call
/// site rather than defaulted.
pub(all) struct MtscMemoryHost {
  files : Map[String, String]
  roots : Array[String]
  cwd : String
  options : MtscCompilerOptions
}

///|
impl MtscHost for MtscMemoryHost with fn read_file(self, path) {
  self.files.get(path)
}

///|
impl MtscHost for MtscMemoryHost with fn script_file_names(self) {
  self.roots
}

///|
impl MtscHost for MtscMemoryHost with fn current_directory(self) {
  self.cwd
}

///|
impl MtscHost for MtscMemoryHost with fn compilation_settings(self) {
  self.options
}

///|
/// An `MtscMemoryHost` over `files`, rooted at every one of them.
///
/// The common shape for a test and for a caller who means "check all of
/// this": listing the same paths twice is noise, and a root set that
/// drifts from the file set is a silent way to check nothing.
///
/// The roots are SORTED, which is about the output rather than the
/// input: root order is diagnostic order, so taking it from `Map`
/// iteration would make the report depend on the map's internals, and a
/// caller diffing two runs wants the same list twice. Where the order
/// matters, `roots` is a field — state it there instead.
pub fn MtscMemoryHost::over(
  files : Map[String, String],
  jsx? : Bool = false,
) -> MtscMemoryHost {
  let roots : Array[String] = []
  for path in files.keys() {
    roots.push(path)
  }
  roots.sort()
  { files, roots, cwd: ".", options: { jsx, }, }
}

// ---------------------------------------------------------------------------
// Source cache
// ---------------------------------------------------------------------------

///|
/// Every path one operation has asked the host about, hit or miss.
///
/// Both directions matter. Resolving `./util` probes `./util.d.ts`,
/// `./util.ts`, `./util.tsx` and seven more before it finds one, so
/// without a negative cache a host backed by real IO pays those
/// syscalls again for every importer of the same module; and without a
/// positive one it reads each resolved file twice, once to prove it
/// exists and once to parse it.
priv struct MtscSourceCache {
  entries : Map[String, String?]
}

///|
/// An empty cache.
fn MtscSourceCache::new() -> MtscSourceCache {
  { entries: Map([]), }
}

///|
/// `host.read_file(path)`, asked at most once per path.
fn[H : MtscHost] MtscSourceCache::read(
  self : MtscSourceCache,
  host : H,
  path : String,
) -> String? {
  match self.entries.get(path) {
    Some(hit) => hit
    None => {
      let value = host.read_file(path)
      self.entries[path] = value
      value
    }
  }
}
