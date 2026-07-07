import 'package:flutter_monaco/src/assets/html_builder.dart';
import 'package:flutter_monaco/src/assets/monaco_assets.dart';

/// Test-side convenience over the internal [buildMonacoIndexHtml] with the
/// bundled [MonacoAssets.monacoVersion], mirroring the 2.x
/// `MonacoAssets.generateIndexHtml` shape the HTML tests were written
/// against. The public facade no longer exposes HTML generation (D25).
String generateIndexHtml(
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
    monacoVersion: MonacoAssets.monacoVersion,
    isWindows: isWindows,
    isIosOrMacOS: isIosOrMacOS,
    isWeb: isWeb,
    messageToken: messageToken,
    customCss: customCss,
    allowCdnFonts: allowCdnFonts,
    allowedConnectSources: allowedConnectSources,
  );
}
