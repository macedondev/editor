import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_monaco/src/options/editor_options.dart';
import 'package:flutter_monaco/src/options/language.dart';
import 'package:flutter_monaco/src/options/option_enums.dart';
import 'package:flutter_monaco/src/options/sub_options.dart';
import 'package:flutter_monaco/src/options/theme.dart';

/// Curated defaults applied when the caller leaves fields unset.
abstract final class MonacoDefaults {
  /// Base options merged UNDER user options at boot (user fields win).
  ///
  /// Defines the 3.x out-of-the-box experience: word wrap on, minimap off,
  /// line numbers on, automatic layout on, tab size 4, spaces for tabs, a
  /// 14px coding font stack, bracket-pair colorization, smooth scrolling,
  /// mouse-wheel zoom, scroll beyond the last line, selection whitespace
  /// rendering, a blinking line cursor, and 10px top padding.
  ///
  /// These are not an exact copy of either 2.3.0 `EditorOptions()` or
  /// `MonacoConstants.defaultOptions`. Apps migrating behavior-sensitive
  /// settings should specify those values explicitly.
  static const EditorOptions editorOptions = EditorOptions(
    fontSize: 14,
    fontFamily: MonacoFontStacks.cascadiaCodePrimary,
    wordWrap: MonacoWordWrap.on,
    minimap: MonacoMinimapOptions(enabled: false),
    lineNumbers: MonacoLineNumbers.on,
    automaticLayout: true,
    tabSize: 4,
    insertSpaces: true,
    bracketPairColorization: true,
    smoothScrolling: true,
    mouseWheelZoom: true,
    scrollBeyondLastLine: true,
    renderWhitespace: RenderWhitespace.selection,
    cursorBlinking: CursorBlinking.blink,
    cursorStyle: CursorStyle.line,
    padding: MonacoPadding(top: 10),
  );

  /// Boot deadline applied when the caller leaves `readyTimeout` unset.
  ///
  /// Native platforms load Monaco from local files, so 20 seconds only
  /// trips on a genuinely hung boot. On web the first (cold-cache) visit
  /// must download the multi-megabyte editor bundle over the network -
  /// bandwidth-bound, not hang-bound - so the backstop is far more
  /// generous there. Hard failures (missing assets, script errors) are
  /// reported immediately through the page's error handlers on every
  /// platform; this deadline only catches silent stalls.
  static const Duration readyTimeout = kIsWeb
      ? Duration(seconds: 90)
      : Duration(seconds: 20);

  /// Document language used when none is configured.
  static const MonacoLanguage language = MonacoLanguage.markdown;

  /// Theme used for dark surroundings (and as the headless fallback).
  static const MonacoTheme darkTheme = MonacoTheme.vsDark;

  /// Theme used for light surroundings.
  static const MonacoTheme lightTheme = MonacoTheme.vs;
}

/// Common CSS `font-family` stacks for [EditorOptions.fontFamily].
///
/// Replaces the 2.3.0 `MonacoFont` enum; the stack strings are unchanged.
abstract final class MonacoFontStacks {
  /// A font stack prioritizing "Cascadia Code".
  static const String cascadiaCodePrimary =
      'Cascadia Code, Fira Code, Consolas, monospace';

  /// A font stack prioritizing "Fira Code".
  static const String firaCodePrimary = 'Fira Code, Consolas, monospace';

  /// A font stack for Apple platforms.
  static const String sfMono = 'SF Mono, Monaco, monospace';

  /// The "JetBrains Mono" font.
  static const String jetBrainsMono = 'JetBrains Mono, monospace';

  /// The "Source Code Pro" font.
  static const String sourceCodePro = 'Source Code Pro, monospace';

  /// The "Consolas" font.
  static const String consolas = 'Consolas, monospace';

  /// The "Monaco" font.
  static const String monaco = 'Monaco, monospace';

  /// The "Menlo" font.
  static const String menlo = 'Menlo, monospace';

  /// The "Courier New" font.
  static const String courierNew = 'Courier New, monospace';

  /// A generic monospace font.
  static const String monospace = 'monospace';

  /// All stacks in this catalog.
  static const List<String> all = [
    cascadiaCodePrimary,
    firaCodePrimary,
    sfMono,
    jetBrainsMono,
    sourceCodePro,
    consolas,
    monaco,
    menlo,
    courierNew,
    monospace,
  ];
}
