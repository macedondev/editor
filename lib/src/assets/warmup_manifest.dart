/// Which Monaco files are worth warming into the browser's HTTP cache
/// before the first editor boots on web.
///
/// Internal: consumed by the web precache implementation and its tests; not
/// exported by the barrel.
library;

/// Files (relative to `min/vs/`) that every boot loads and whose names are
/// stable across Monaco releases.
///
/// The list is ordered smallest-first so the boot-critical loader is cached
/// even if warmup is interrupted early.
const List<String> monacoWarmupStaticFiles = [
  'loader.js',
  'editor/editor.main.js',
  'editor/editor.main.css',
];

/// Extracts the hash-named editor chunks that `editor.main.js` declares as
/// AMD dependencies, as paths relative to `min/vs/`.
///
/// Monaco 0.55+ ships the bulk of the editor (~3.6MB) in a content-hashed
/// sibling chunk that `min/vs/editor/editor.main.js` requires as
/// `"../editor.api-<hash>"`. The hash changes with every Monaco release, so
/// it cannot be hard-coded; it is recovered from the entry module's source
/// instead. Returns an empty list when no chunk reference is found (older
/// or restructured Monaco builds) - warmup then simply covers the static
/// files and the boot fetches the rest as usual.
List<String> extractMonacoWarmupChunks(String editorMainSource) {
  final chunkRef = RegExp(r'\.\./(editor\.api-[A-Za-z0-9_-]+)');
  return {
    for (final match in chunkRef.allMatches(editorMainSource)) '${match[1]}.js',
  }.toList();
}
