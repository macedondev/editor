import 'package:flutter/foundation.dart';

/// Typed diagnostics about the extracted Monaco assets (D25).
///
/// Returned by `MonacoAssets.assetInfo()`. Useful for debugging extraction
/// issues or showing version information in an about dialog.
@immutable
final class MonacoAssetDiagnostics {
  /// Creates a diagnostics snapshot.
  const MonacoAssetDiagnostics({
    required this.exists,
    required this.path,
    required this.monacoVersion,
    this.fileCount = 0,
    this.totalSizeBytes = 0,
    this.generatedHtmlCount = 0,
  });

  /// Whether the asset directory exists.
  ///
  /// Always `true` on web, where assets are served by the web server and
  /// the file counts below stay `0` (no file system access).
  final bool exists;

  /// Location of the assets: the extraction directory on native platforms,
  /// the served asset root on web.
  final String path;

  /// The bundled Monaco version (`MonacoAssets.monacoVersion`).
  final String monacoVersion;

  /// Number of files in the extraction directory (`0` when [exists] is
  /// `false` or on web).
  final int fileCount;

  /// Total extracted size in bytes (`0` when [exists] is `false` or on web).
  final int totalSizeBytes;

  /// Number of generated `monaco_<key>.html` variants found.
  final int generatedHtmlCount;

  /// Total extracted size in megabytes.
  double get totalSizeMB => totalSizeBytes / 1024 / 1024;

  @override
  bool operator ==(Object other) =>
      other is MonacoAssetDiagnostics &&
      other.exists == exists &&
      other.path == path &&
      other.monacoVersion == monacoVersion &&
      other.fileCount == fileCount &&
      other.totalSizeBytes == totalSizeBytes &&
      other.generatedHtmlCount == generatedHtmlCount;

  @override
  int get hashCode => Object.hash(
    exists,
    path,
    monacoVersion,
    fileCount,
    totalSizeBytes,
    generatedHtmlCount,
  );

  @override
  String toString() =>
      'MonacoAssetDiagnostics(exists: $exists, path: $path, '
      'monacoVersion: $monacoVersion, fileCount: $fileCount, '
      'totalSizeBytes: $totalSizeBytes, '
      'generatedHtmlCount: $generatedHtmlCount)';
}
