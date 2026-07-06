/// Web asset setup is a no-op because Flutter serves package assets directly.
Future<void> ensureMonacoAssetsReady({
  required String assetBaseDir,
  required String cacheSubDir,
  required String htmlFileName,
  required String monacoVersion,
}) async {}

/// Returns the browser-visible Monaco asset directory.
Future<String> monacoAssetCacheDir({
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {
  return 'assets/$assetBaseDir';
}

/// Returns the browser-visible Monaco HTML asset path.
Future<String> monacoAssetHtmlPath({
  required int cacheKey,
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {
  return 'assets/$assetBaseDir/index.html';
}

/// Returns web diagnostics for the package-served Monaco assets.
Future<Map<String, dynamic>> monacoAssetInfo({
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {
  return {
    'exists': true,
    'path': 'assets/$assetBaseDir',
    'version': monacoVersion,
    'platform': 'web',
    'note': 'Assets served directly from web server, no extraction needed.',
  };
}

/// Web cache clearing is a no-op because assets are served by Flutter.
Future<void> clearMonacoAssetCache({
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {}
