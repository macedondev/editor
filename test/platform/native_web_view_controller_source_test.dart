import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source fences for the native focus handoff.
///
/// The desktop focus contract lives in three places that cannot see each
/// other at compile time: the Dart platform controllers, the macOS Swift
/// plugin, and the pubspec plugin declaration. These tests fail the build if
/// any side of that contract drifts.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('Dart platform controllers', () {
    test('base controller keeps native focus a documented no-op', () {
      final source = read('lib/src/platform/web_view_controller/native.dart');

      final baseFocusStart = source.indexOf(
        '@override\n  Future<NativeFocusResult> requestNativeFocus() async {',
      );
      final baseFocusEnd = source.indexOf('/// Generates and caches');
      expect(baseFocusStart, isNonNegative);
      expect(baseFocusEnd, greaterThan(baseFocusStart));

      final baseFocusBlock = source.substring(baseFocusStart, baseFocusEnd);
      expect(baseFocusBlock, contains('No-op by default'));
      expect(baseFocusBlock, contains('NativeFocusResult.unsupported'));
      expect(baseFocusBlock, isNot(contains('_controller.focus()')));
    });

    test(
      'macOS handoff goes through the flutter_monaco/native_focus channel',
      () {
        final source = read('lib/src/platform/web_view_controller/native.dart');

        final flutterClassStart = source.indexOf(
          'class FlutterWebViewController',
        );
        final windowsClassStart = source.indexOf(
          'class WindowsWebViewController',
        );
        expect(flutterClassStart, isNonNegative);
        expect(windowsClassStart, greaterThan(flutterClassStart));

        final flutterClassBlock = source.substring(
          flutterClassStart,
          windowsClassStart,
        );
        expect(flutterClassBlock, contains("'flutter_monaco/native_focus'"));
        expect(flutterClassBlock, contains("'focusWebView'"));
        expect(flutterClassBlock, contains("'hasNativeFocus'"));
        expect(flutterClassBlock, contains("'releaseWebViewFocus'"));
        // The handoff is macOS-only on this controller; Android/iOS WebViews
        // take native focus from the user gesture itself.
        expect(flutterClassBlock, contains('if (!Platform.isMacOS)'));
        // Without the plugin, callers must get the replay fallback, not a
        // crash or a false success.
        expect(flutterClassBlock, contains('on MissingPluginException'));
      },
    );

    test('Windows handoff still moves real Win32 focus', () {
      final source = read('lib/src/platform/web_view_controller/native.dart');

      final windowsClassStart = source.indexOf(
        'class WindowsWebViewController',
      );
      final windowsFocusStart = source.indexOf(
        '@override\n  Future<NativeFocusResult> requestNativeFocus() async {',
        windowsClassStart,
      );
      expect(windowsClassStart, isNonNegative);
      expect(windowsFocusStart, greaterThan(windowsClassStart));

      final windowsFocusEnd = source.indexOf(
        '@override\n  Future<void> enableJavaScript()',
        windowsFocusStart,
      );
      expect(windowsFocusEnd, greaterThan(windowsFocusStart));

      final windowsFocusBlock = source.substring(
        windowsFocusStart,
        windowsFocusEnd,
      );
      expect(windowsFocusBlock, contains('await _controller.focus();'));
      expect(windowsFocusBlock, contains('hasNativeFocus'));
    });
  });

  group('macOS native plugin contract', () {
    test('Swift plugin implements the channel the Dart side calls', () {
      final swift = read(
        'macos/flutter_monaco/Sources/flutter_monaco/FlutterMonacoPlugin.swift',
      );

      expect(swift, contains('"flutter_monaco/native_focus"'));
      expect(swift, contains('case "focusWebView":'));
      expect(swift, contains('case "hasNativeFocus":'));
      expect(swift, contains('case "releaseWebViewFocus":'));
      // The whole point of the plugin: a real first-responder handoff.
      expect(swift, contains('window.makeFirstResponder(webView)'));
      // Status strings the Dart side maps to NativeFocusResult.
      expect(swift, contains('"granted"'));
      expect(swift, contains('"already-owned"'));
      // Coordinate contract: Dart sends top-left-origin logical points.
      expect(swift, contains('isFlipped'));
    });

    test('pubspec registers the macOS plugin class', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, contains('pluginClass: FlutterMonacoPlugin'));
    });

    test('podspec and Swift package share one source of truth', () {
      final podspec = read('macos/flutter_monaco.podspec');
      expect(
        podspec,
        contains(
          "s.source_files     = 'flutter_monaco/Sources/flutter_monaco/**/*.swift'",
        ),
      );
      expect(podspec, contains("s.dependency 'FlutterMacOS'"));

      final spmPackage = read('macos/flutter_monaco/Package.swift');
      expect(
        spmPackage,
        contains(
          '.library(name: "flutter-monaco", targets: ["flutter_monaco"])',
        ),
      );
    });
  });
}
