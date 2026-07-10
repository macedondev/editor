import 'dart:convert';

import 'package:flutter_monaco/src/assets/html_builder.dart';
import 'package:flutter_test/flutter_test.dart';

String _build({String? customCss, String? messageToken, bool isWeb = false}) {
  return buildMonacoIndexHtml(
    vsPath: 'monaco/min/vs',
    bridgeBase: 'bridge',
    monacoVersion: '0.55.1',
    isWeb: isWeb,
    messageToken: messageToken,
    customCss: customCss,
  );
}

void main() {
  group('buildMonacoIndexHtml', () {
    test('customCss cannot break out of its style element', () {
      final html = _build(
        customCss: '.a { color: red } </style><script>alert(1)</script>',
      );

      // The literal close sequence must not survive inside the custom
      // block: an early "</style" would end the element and promote the
      // rest to markup (script injection). An escaped form must remain.
      expect(html, isNot(contains('</style><script>')));
      expect(html, isNot(contains('alert(1)</script>')));
      expect(html, contains(r'<\/style><script>alert(1)<\/script>'));
    });

    test('ordinary customCss passes through', () {
      final html = _build(customCss: '.margin { color: rgb(1, 2, 3); }');
      expect(html, contains('.margin { color: rgb(1, 2, 3); }'));
    });

    test('the web message token is JSON-encoded in every interpolation', () {
      const token = r"tok'; window.pwned = true; '";
      final html = _build(isWeb: true, messageToken: token);

      // A raw single-quoted interpolation would let a token containing a
      // quote terminate the string literal and run code; both sites must
      // emit a JSON-encoded literal instead.
      expect(
        html,
        contains('window.flutterMonacoToken = ${jsonEncode(token)};'),
      );
      expect(html, isNot(contains("window.flutterMonacoToken = 'tok';")));
    });
  });
}
