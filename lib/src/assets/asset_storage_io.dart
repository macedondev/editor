import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/src/assets/asset_diagnostics.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Extracts bundled Monaco assets to application support storage if needed.
Future<void> ensureMonacoAssetsReady({
  required String assetBaseDir,
  required String cacheSubDir,
  required String htmlFileName,
  required String monacoVersion,
}) async {
  final targetDir = await monacoAssetCacheDir(
    assetBaseDir: assetBaseDir,
    cacheSubDir: cacheSubDir,
    monacoVersion: monacoVersion,
  );
  final loader = File(p.join(targetDir, 'min', 'vs', 'loader.js'));
  final sentinel = File(p.join(targetDir, '.monaco_complete'));

  final ok =
      loader.existsSync() &&
      sentinel.existsSync() &&
      (await sentinel.readAsString()).trim() == monacoVersion;

  if (ok) {
    debugPrint(
      '[MonacoAssets] Monaco already extracted at: $targetDir (version $monacoVersion)',
    );
    return;
  }

  debugPrint(
    '[MonacoAssets] Monaco not found or incomplete, copying assets...',
  );
  await _copyAllAssets(
    targetDir: targetDir,
    assetBaseDir: assetBaseDir,
    htmlFileName: htmlFileName,
    monacoVersion: monacoVersion,
  );
}

/// Rewrites the bridge JavaScript files in the native asset cache.
///
/// Unlike the sentinel-guarded `min/` tree, the bridge files are small and
/// are rewritten unconditionally on every launch, so upgrading the package
/// can never leave a stale JS bridge next to a current Dart side.
Future<void> refreshMonacoBridgeAssets({
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {
  final targetDir = await monacoAssetCacheDir(
    assetBaseDir: assetBaseDir,
    cacheSubDir: cacheSubDir,
    monacoVersion: monacoVersion,
  );

  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final bridgeAssets = manifest
      .listAssets()
      .where((key) => key.startsWith('$assetBaseDir/bridge/'))
      .where((key) => !key.endsWith('.DS_Store'))
      .toList();

  if (bridgeAssets.isEmpty) {
    // Mirrors the `min/` copy behavior: in a consuming app the manifest
    // always lists the bridge, but the package's own test harness keys
    // assets without the `packages/flutter_monaco/` prefix and finds none.
    debugPrint(
      '[MonacoAssets] No bridge assets under $assetBaseDir/bridge/ in the '
      'asset manifest; skipping bridge refresh.',
    );
    return;
  }

  for (final assetKey in bridgeAssets) {
    final relativePath = assetKey.substring('$assetBaseDir/'.length);
    final targetFile = File(p.join(targetDir, relativePath));
    await targetFile.parent.create(recursive: true);
    final bytes = await rootBundle.load(assetKey);
    await targetFile.writeAsBytes(bytes.buffer.asUint8List());
  }

  debugPrint('[MonacoAssets] Bridge refreshed (${bridgeAssets.length} files)');
}

/// Returns the native cache directory used for extracted Monaco assets.
Future<String> monacoAssetCacheDir({
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {
  return p.join(
    (await getApplicationSupportDirectory()).path,
    cacheSubDir,
    'monaco-$monacoVersion',
  );
}

/// Returns the native generated HTML path for a configuration cache key.
Future<String> monacoAssetHtmlPath({
  required int cacheKey,
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {
  final targetDir = await monacoAssetCacheDir(
    assetBaseDir: assetBaseDir,
    cacheSubDir: cacheSubDir,
    monacoVersion: monacoVersion,
  );
  return p.join(targetDir, 'monaco_$cacheKey.html');
}

/// Returns diagnostics for the extracted native Monaco asset cache.
Future<MonacoAssetDiagnostics> monacoAssetInfo({
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {
  final targetDir = await monacoAssetCacheDir(
    assetBaseDir: assetBaseDir,
    cacheSubDir: cacheSubDir,
    monacoVersion: monacoVersion,
  );
  final directory = Directory(targetDir);

  if (!directory.existsSync()) {
    return MonacoAssetDiagnostics(
      exists: false,
      path: targetDir,
      monacoVersion: monacoVersion,
    );
  }

  var fileCount = 0;
  var totalSize = 0;
  var generatedHtmlCount = 0;

  await for (final entity in directory.list(recursive: true)) {
    if (entity is File) {
      fileCount++;
      totalSize += await entity.length();

      final fileName = p.basename(entity.path);
      if (fileName.startsWith('monaco_') && fileName.endsWith('.html')) {
        generatedHtmlCount++;
      }
    }
  }

  return MonacoAssetDiagnostics(
    exists: true,
    path: targetDir,
    monacoVersion: monacoVersion,
    fileCount: fileCount,
    totalSizeBytes: totalSize,
    generatedHtmlCount: generatedHtmlCount,
  );
}

/// Deletes the native Monaco asset cache directory when present.
Future<void> clearMonacoAssetCache({
  required String assetBaseDir,
  required String cacheSubDir,
  required String monacoVersion,
}) async {
  final targetDir = await monacoAssetCacheDir(
    assetBaseDir: assetBaseDir,
    cacheSubDir: cacheSubDir,
    monacoVersion: monacoVersion,
  );
  final directory = Directory(targetDir);

  if (directory.existsSync()) {
    await directory.delete(recursive: true);
    debugPrint('[MonacoAssets] Monaco assets cleaned');
  }
}

Future<void> _copyAllAssets({
  required String targetDir,
  required String assetBaseDir,
  required String htmlFileName,
  required String monacoVersion,
}) async {
  final stopwatch = Stopwatch()..start();
  final failures = <String>[];

  final directory = Directory(targetDir);
  if (directory.existsSync()) {
    await directory.delete(recursive: true);
  }
  await directory.create(recursive: true);

  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final monacoAssets = manifest
      .listAssets()
      .where((key) => key.startsWith('$assetBaseDir/'))
      .where((key) => !key.endsWith('.DS_Store'))
      .where((key) => !key.endsWith('/$htmlFileName'))
      .toList();

  debugPrint(
    '[MonacoAssets] Found ${monacoAssets.length} Monaco assets to copy',
  );

  var copiedCount = 0;
  for (final assetKey in monacoAssets) {
    try {
      final relativePath = assetKey.substring('$assetBaseDir/'.length);
      if (relativePath.isEmpty) continue;

      final targetFile = File(p.join(targetDir, relativePath));
      await targetFile.parent.create(recursive: true);

      final bytes = await rootBundle.load(assetKey);
      await targetFile.writeAsBytes(bytes.buffer.asUint8List());

      copiedCount++;

      if (copiedCount % 100 == 0) {
        debugPrint(
          '[MonacoAssets] Progress: $copiedCount/${monacoAssets.length} files copied',
        );
      }
    } catch (e) {
      debugPrint('[MonacoAssets] Error copying $assetKey: $e');
      failures.add('$assetKey: $e');
    }
  }

  stopwatch.stop();
  debugPrint(
    '[MonacoAssets] Completed: $copiedCount files copied in ${stopwatch.elapsedMilliseconds}ms',
  );

  if (copiedCount != monacoAssets.length || failures.isNotEmpty) {
    throw StateError(
      '[MonacoAssets] Copy incomplete ($copiedCount/${monacoAssets.length}). '
      'Failures: ${failures.length}',
    );
  }

  final sentinelFile = File(p.join(targetDir, '.monaco_complete'));
  await sentinelFile.writeAsString(monacoVersion);
  debugPrint('[MonacoAssets] Sentinel file written for version $monacoVersion');
}
