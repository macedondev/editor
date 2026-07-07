import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorOptions', () {
    test('fromJson maps values sparsely (unset fields stay null)', () {
      final options = EditorOptions.fromJson({
        'language': 'python',
        'theme': 'vs',
        'fontSize': 16,
        'lineNumbers': 'off',
        'tabSize': 2,
      });
      expect(options.language, MonacoLanguage.python);
      expect(options.theme, MonacoTheme.vs);
      expect(options.fontSize, 16);
      expect(options.lineNumbers, MonacoLineNumbers.off);
      expect(options.tabSize, 2);
      expect(options.wordWrap, isNull);
    });

    test('fromJson throws on unknown keys', () {
      expect(
        () => EditorOptions.fromJson({'themeId': 'app-dark'}),
        throwsFormatException,
      );
    });

    test('fromJson throws on wrongly typed values', () {
      expect(
        () => EditorOptions.fromJson({'lineNumbers': false}),
        throwsFormatException,
      );
      expect(
        () => EditorOptions.fromJson({'fontSize': 'big'}),
        throwsFormatException,
      );
    });

    test('toJson omits null fields and round-trips sparsely', () {
      const options = EditorOptions(
        theme: MonacoTheme('app-dark'),
        fontSize: 16,
        wordWrap: MonacoWordWrap.bounded,
        minimap: MonacoMinimapOptions(enabled: true),
        padding: MonacoPadding(top: 10),
      );

      final json = options.toJson();
      expect(json.containsKey('lineNumbers'), false);
      expect(json.containsKey('tabSize'), false);

      final restored = EditorOptions.fromJson(json);
      expect(restored, options);
    });

    test('merge lets non-null fields of the other options win', () {
      const base = EditorOptions(fontSize: 14, tabSize: 4);
      const override = EditorOptions(fontSize: 16);

      final merged = base.merge(override);
      expect(merged.fontSize, 16);
      expect(merged.tabSize, 4);
    });

    test('toMonacoOptions maps expected keys', () {
      const options = EditorOptions(
        wordWrap: MonacoWordWrap.off,
        minimap: MonacoMinimapOptions(enabled: true),
        lineNumbers: MonacoLineNumbers.off,
        cursorBlinking: CursorBlinking.expand,
        cursorStyle: CursorStyle.block,
        renderWhitespace: RenderWhitespace.all,
        parameterHints: false,
        hover: false,
        contextMenu: false,
        bracketPairColorization: false,
      );
      final map = options.toMonacoOptions();
      expect(map['wordWrap'], 'off');
      expect(map['minimap'], {'enabled': true});
      expect(map['lineNumbers'], 'off');
      expect(map['cursorBlinking'], 'expand');
      expect(map['cursorStyle'], 'block');
      expect(map['renderWhitespace'], 'all');
      expect(map['parameterHints'], {'enabled': false});
      expect(map['hover'], {'enabled': false});
      expect(map['contextmenu'], false);
      expect(map['bracketPairColorization'], {'enabled': false});
      expect(map.containsKey('padding'), false);
    });
  });
}
