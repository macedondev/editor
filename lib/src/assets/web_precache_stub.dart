/// Native stand-in for the web precache implementation.
///
/// `MonacoAssets.precache` only calls this behind a `kIsWeb` check; on
/// native platforms asset readiness is handled by extraction in
/// `MonacoAssets.ensureReady`, so there is nothing to warm here.
Future<void> precacheMonacoWebAssets() async {}
