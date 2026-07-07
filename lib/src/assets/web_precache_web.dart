import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/src/assets/monaco_assets.dart';
import 'package:flutter_monaco/src/assets/warmup_manifest.dart';
import 'package:flutter_monaco/src/platform/web_asset_resolver.dart';
import 'package:web/web.dart' as web;

/// Warms the browser's HTTP cache with the Monaco files the first editor
/// boot will request, so the boot inside the editor iframe is served from
/// cache instead of the network.
///
/// The whole routine is best-effort: every fetch failure is swallowed and
/// the boot path is completely untouched - a failed warmup just means the
/// iframe downloads the files itself, exactly as it does today. Responses
/// are read to completion because the browser only commits a fetch to the
/// HTTP cache once its body has been consumed.
Future<void> precacheMonacoWebAssets() async {
  try {
    final vsBase = resolveWebAssetUrl(
      web.document.baseURI,
      ui_web.assetManager.getAssetUrl('$monacoAssetBaseDir/min/vs'),
    );

    // The hash-named bulk chunk (~3.6MB) is discovered from editor.main.js,
    // so that fetch gates the chunk warms; the other static files warm
    // concurrently.
    final concurrent = <Future<void>>[
      for (final file in monacoWarmupStaticFiles)
        if (file != 'editor/editor.main.js') _fetchAndDiscard('$vsBase/$file'),
    ];

    final editorMainSource = await _fetchText('$vsBase/editor/editor.main.js');
    if (editorMainSource != null) {
      for (final chunk in extractMonacoWarmupChunks(editorMainSource)) {
        concurrent.add(_fetchAndDiscard('$vsBase/$chunk'));
      }
    }

    await Future.wait(concurrent);
    debugPrint('[MonacoAssets] Web warmup finished for $vsBase');
  } catch (e) {
    debugPrint('[MonacoAssets] Web warmup skipped: $e');
  }
}

Future<String?> _fetchText(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) return null;
    return (await response.text().toDart).toDart;
  } catch (_) {
    return null;
  }
}

Future<void> _fetchAndDiscard(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) return;
    await response.arrayBuffer().toDart;
  } catch (_) {}
}
