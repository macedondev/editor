import 'package:flutter_monaco/src/assets/asset_diagnostics.dart';

/// Web asset setup is a no-op because Flutter serves package assets directly.
Future<void> ensureMonacoAssetsReady({
  required String assetBaseDir,
  required String cacheSubDir,
  required String htmlFileName,
  required String monacoVersion,
}) async {}

/// Web bridge refresh is a no-op: bridge files are served directly as
/// Flutter assets, so they can never go stale relative to the Dart side.
Future<void> refreshMonacoBridgeAssets({
  required String assetBaseDir,
  required String cacheSubDir,
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
  required String cacheKey,
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {
  return 'assets/$assetBaseDir/index.html';
}

/// Returns web diagnostics for the package-served Monaco assets. Assets are
/// served directly by the web server (no extraction), so the file counts
/// stay zero.
Future<MonacoAssetDiagnostics> monacoAssetInfo({
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {
  return MonacoAssetDiagnostics(
    exists: true,
    path: 'assets/$assetBaseDir',
    monacoVersion: monacoVersion,
  );
}

/// Web cache clearing is a no-op because assets are served by Flutter.
Future<void> clearMonacoAssetCache({
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {}
