import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonacoLanguage', () {
    test('constructor resolves built-in language ids', () {
      expect(const MonacoLanguage('javascript'), MonacoLanguage.javascript);
      expect(const MonacoLanguage('typescript'), MonacoLanguage.typescript);
      expect(const MonacoLanguage('dart'), MonacoLanguage.dart);
      expect(const MonacoLanguage('python'), MonacoLanguage.python);
    });

    test('unknown language ids stay custom instead of falling back', () {
      const custom = MonacoLanguage('unknown-lang');
      expect(custom.id, 'unknown-lang');
      expect(custom.isBuiltIn, false);
      expect(custom.label, isNull);
    });

    test('language id should match catalog id', () {
      expect(MonacoLanguage.javascript.id, 'javascript');
      expect(MonacoLanguage.python.id, 'python');
      expect(MonacoLanguage.dart.id, 'dart');
    });
  });

  group('MonacoTheme', () {
    test('constructor resolves built-in theme ids', () {
      expect(const MonacoTheme('vs'), MonacoTheme.vs);
      expect(const MonacoTheme('vs-dark'), MonacoTheme.vsDark);
      expect(const MonacoTheme('hc-black'), MonacoTheme.hcBlack);
      expect(const MonacoTheme('hc-light'), MonacoTheme.hcLight);
    });

    test('unknown theme ids stay custom instead of falling back', () {
      const custom = MonacoTheme('unknown-theme');
      expect(custom.id, 'unknown-theme');
      expect(custom.isBuiltIn, false);
      expect(custom.label, isNull);
    });

    test('theme id should match expected values', () {
      expect(MonacoTheme.vs.id, 'vs');
      expect(MonacoTheme.vsDark.id, 'vs-dark');
      expect(MonacoTheme.hcBlack.id, 'hc-black');
      expect(MonacoTheme.hcLight.id, 'hc-light');
    });
  });

  group('EditorOptions', () {
    test('default construction leaves every field unset', () {
      const options = EditorOptions();
      expect(options.fontSize, isNull);
      expect(options.tabSize, isNull);
      expect(options.wordWrap, isNull);
      expect(options.minimap, isNull);
      expect(options.lineNumbers, isNull);
    });

    test('MonacoDefaults.editorOptions carries the curated boot defaults', () {
      const defaults = MonacoDefaults.editorOptions;
      expect(defaults.fontSize, 14);
      expect(defaults.tabSize, 4);
      expect(defaults.wordWrap, MonacoWordWrap.on);
      expect(defaults.minimap, const MonacoMinimapOptions(enabled: false));
      expect(defaults.lineNumbers, MonacoLineNumbers.on);
    });

    test('should create with custom values', () {
      const options = EditorOptions(
        language: MonacoLanguage.python,
        theme: MonacoTheme.vsDark,
        fontSize: 16,
        tabSize: 2,
        wordWrap: MonacoWordWrap.on,
        minimap: MonacoMinimapOptions(enabled: false),
      );
      expect(options.language, MonacoLanguage.python);
      expect(options.theme, MonacoTheme.vsDark);
      expect(options.fontSize, 16);
      expect(options.tabSize, 2);
      expect(options.wordWrap, MonacoWordWrap.on);
      expect(options.minimap, const MonacoMinimapOptions(enabled: false));
    });
  });
}
