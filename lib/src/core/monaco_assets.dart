import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/src/assets/html_builder.dart';
import 'package:flutter_monaco/src/core/monaco_asset_storage.dart';

/// Manages Monaco Editor assets across all platforms.
///
/// This class is the single source of truth for Monaco asset locations, versions,
/// and extraction. It handles:
///
/// - **Asset extraction:** Copies bundled Monaco files to app support directory
///   on native platforms for WebView access.
/// - **Version management:** Tracks Monaco version and re-extracts on updates.
/// - **HTML generation:** Creates platform-specific HTML with correct paths
///   and Content-Security-Policy headers.
/// - **Caching:** Avoids redundant extraction and HTML generation.
///
/// ### Platform Behavior
///
/// - **Native (Android/iOS/macOS/Windows):** Assets are extracted from the app
///   bundle to the application support directory on first use. A sentinel file
///   tracks the version to detect when re-extraction is needed.
/// - **Web:** Assets are served directly from the `assets/` directory. No
///   extraction is needed.
///
/// ### Usage
///
/// ```dart
/// // Ensure assets are ready before using Monaco
/// await MonacoAssets.ensureReady();
///
/// // Get the HTML file path for a specific configuration
/// final htmlPath = await MonacoAssets.indexHtmlPath(cacheKey: options.hashCode);
/// ```
///
/// See also:
/// - [MonacoController] which calls [ensureReady] during initialization.
/// - [generateIndexHtml] for HTML generation details.
class MonacoAssets {
  /// The Flutter asset path where Monaco Editor files are bundled.
  ///
  /// This path is relative to the package root and used for both web asset
  /// serving and native asset extraction.
  static const String assetBaseDir = 'packages/flutter_monaco/assets/monaco';

  /// Subdirectory name within application support for extracted assets.
  static const String _cacheSubDir = 'monaco_editor_cache';

  static const String _htmlFileName = 'index.html';

  /// The Monaco Editor version bundled with this package.
  ///
  /// When this version changes, [ensureReady] will re-extract assets on
  /// native platforms to ensure the correct version is used.
  static const String monacoVersion = '0.55.1';

  static Completer<void>? _initCompleter;

  /// Ensures Monaco assets are extracted and ready for use on native platforms.
  ///
  /// This method performs the following checks and operations:
  ///
  /// 1. **Existence check:** Verifies `loader.js` exists in the target directory
  /// 2. **Version check:** Compares sentinel file content with [monacoVersion]
  /// 3. **Extraction:** Copies all assets from the bundle if missing or outdated
  ///
  /// ### Thread Safety
  ///
  /// This method is idempotent and thread-safe. Multiple concurrent calls
  /// will share the same [Completer], ensuring extraction happens only once.
  /// Subsequent calls return immediately if assets are already ready.
  ///
  /// ### Web Platform
  ///
  /// On web, this method completes immediately without any file operations,
  /// as assets are served directly from the web server.
  ///
  /// ### Error Handling
  ///
  /// Throws [StateError] if asset extraction fails (e.g., insufficient disk
  /// space or permission issues). The error includes details about which
  /// files failed to copy.
  ///
  /// ### Example
  ///
  /// ```dart
  /// // Call before creating MonacoController
  /// await MonacoAssets.ensureReady();
  /// final controller = await MonacoController.create();
  /// ```
  static Future<void> ensureReady() async {
    if (_initCompleter != null) return _initCompleter!.future;

    final completer = _initCompleter = Completer<void>();

    try {
      await ensureMonacoAssetsReady(
        assetBaseDir: assetBaseDir,
        cacheSubDir: _cacheSubDir,
        htmlFileName: _htmlFileName,
        monacoVersion: monacoVersion,
      );
      // The sentinel guards only the large Monaco `min/` tree. The bridge
      // JavaScript is rewritten on every launch so a package upgrade can
      // never ship stale bridge code (replaces the 2.x
      // `htmlGenerationVersion` cache-bust constant).
      await refreshMonacoBridgeAssets(
        assetBaseDir: assetBaseDir,
        cacheSubDir: _cacheSubDir,
        monacoVersion: monacoVersion,
      );
      completer.complete();
    } catch (e, st) {
      _initCompleter = null;
      completer.completeError(e, st);
    }

    return completer.future;
  }

  /// Returns the path to the Monaco HTML file for a given configuration.
  ///
  /// The [cacheKey] should be derived from configuration options that affect
  /// HTML generation (e.g., `Object.hash(customCss, allowCdnFonts)`). This
  /// enables caching multiple HTML variants for different configurations.
  ///
  /// ### Native Platforms
  ///
  /// Ensures assets are extracted via [ensureReady], then returns a path
  /// like: `{appSupport}/monaco_editor_cache/monaco-{version}/monaco_{key}.html`
  ///
  /// The actual HTML file is created lazily by the WebView controller when
  /// it calls [generateIndexHtml].
  ///
  /// ### Web Platform
  ///
  /// Returns the static asset path directly:
  /// `assets/packages/flutter_monaco/assets/monaco/index.html`
  ///
  /// Note that on web, the [cacheKey] is ignored since HTML is generated
  /// dynamically as a blob URL rather than loaded from this path.
  static Future<String> indexHtmlPath({required int cacheKey}) async {
    if (kIsWeb) {
      return 'assets/packages/flutter_monaco/assets/monaco/index.html';
    }

    await ensureReady();

    return monacoAssetHtmlPath(
      cacheKey: cacheKey,
      assetBaseDir: assetBaseDir,
      cacheSubDir: _cacheSubDir,
      monacoVersion: monacoVersion,
    );
  }

  /// Returns diagnostic information about extracted Monaco assets.
  ///
  /// This method is useful for debugging asset extraction issues or
  /// displaying version information in an about dialog.
  ///
  /// ### Returned Fields
  ///
  /// - `exists` (bool): Whether the asset directory exists
  /// - `path` (String): Absolute path to the asset directory
  /// - `version` (String): The [monacoVersion] constant
  /// - `fileCount` (int): Number of files in the directory (if exists)
  /// - `totalSize` (int): Total size in bytes (if exists)
  /// - `totalSizeMB` (String): Formatted size in megabytes (if exists)
  /// - `generatedHtmlCount` (int): Number of generated HTML files found
  ///
  /// ### Web Platform
  ///
  /// On web, assets are served directly from the web server, so this returns
  /// limited information without file system access.
  ///
  /// ### Example
  ///
  /// ```dart
  /// final info = await MonacoAssets.assetInfo();
  /// print('Monaco ${info['version']} - ${info['totalSizeMB']} MB');
  /// ```
  static Future<Map<String, dynamic>> assetInfo() async {
    return monacoAssetInfo(
      assetBaseDir: assetBaseDir,
      cacheSubDir: _cacheSubDir,
      monacoVersion: monacoVersion,
    );
  }

  /// Deletes all extracted Monaco assets and resets initialization state.
  ///
  /// This method:
  /// 1. Recursively deletes the Monaco asset directory
  /// 2. Clears the in-memory HTML cache
  /// 3. Resets [_initCompleter] so [ensureReady] will re-extract
  ///
  /// ### Use Cases
  ///
  /// - **Corruption recovery:** If Monaco fails to load, clearing and
  ///   re-extracting may fix the issue.
  /// - **Storage cleanup:** Frees ~5-10MB of disk space.
  /// - **Development:** Forces fresh extraction after updating Monaco assets.
  ///
  /// ### Web Platform
  ///
  /// On web, this method only clears the in-memory HTML cache since assets
  /// are served directly from the web server and cannot be deleted.
  ///
  /// ### Example
  ///
  /// ```dart
  /// // Clear corrupted assets and re-extract
  /// await MonacoAssets.clearCache();
  /// await MonacoAssets.ensureReady();
  /// ```
  ///
  /// **Note:** Any existing [MonacoController] instances will become invalid
  /// after clearing. Dispose and recreate them after calling this method.
  static Future<void> clearCache() async {
    // On web, only clear in-memory caches (no file system access)
    if (kIsWeb) {
      _initCompleter = null;
      debugPrint('[MonacoAssets] Web cache cleared (in-memory only)');
      return;
    }

    await clearMonacoAssetCache(
      assetBaseDir: assetBaseDir,
      cacheSubDir: _cacheSubDir,
      monacoVersion: monacoVersion,
    );

    // Reset the init completer so ensureReady will re-extract.
    _initCompleter = null;
  }

  /// Generates the HTML document that hosts the Monaco Editor.
  ///
  /// Since 3.0 the page is a slim shell: platform channel/worker shims and a
  /// `window.__FM_PAGE` config snippet stay inline, while all bridge logic is
  /// loaded from real JavaScript files via `<script src>` (see
  /// `assets/monaco/bridge/`). [bridgeBasePath] is the URL prefix for those
  /// files without a trailing slash: the default `bridge` suits native
  /// platforms where the generated HTML sits next to the extracted `bridge/`
  /// directory; Windows passes an absolute `file://` directory URL and web
  /// passes a resolved asset URL.
  ///
  /// All other parameters keep their 2.3.0 semantics: [vsPath] locates the
  /// Monaco `vs/` directory, [isWindows]/[isIosOrMacOS]/[isWeb] select the
  /// platform shims, [messageToken] authenticates web postMessage traffic,
  /// [customCss] is injected into a `<style>` tag, [allowCdnFonts] relaxes
  /// CSP for `https:` styles/fonts, and [allowedConnectSources] extends the
  /// CSP `connect-src` list (validated; throws [ArgumentError] on entries
  /// that could break the policy attribute).
  static String generateIndexHtml(
    String vsPath, {
    bool isWindows = false,
    bool isIosOrMacOS = false,
    bool isWeb = false,
    String? messageToken,
    String? customCss,
    bool allowCdnFonts = false,
    List<String> allowedConnectSources = const [],
    String bridgeBasePath = 'bridge',
  }) {
    return buildMonacoIndexHtml(
      vsPath: vsPath,
      bridgeBase: bridgeBasePath,
      monacoVersion: monacoVersion,
      isWindows: isWindows,
      isIosOrMacOS: isIosOrMacOS,
      isWeb: isWeb,
      messageToken: messageToken,
      customCss: customCss,
      allowCdnFonts: allowCdnFonts,
      allowedConnectSources: allowedConnectSources,
    );
  }
}
