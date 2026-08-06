import 'dart:convert';

import 'package:flutter_monaco/src/assets/html_builder.dart';
import 'package:flutter_test/flutter_test.dart';

String _build({
  String? customCss,
  String? messageToken,
  bool isWeb = false,
  String vsPath = 'monaco/min/vs',
}) {
  return buildMonacoIndexHtml(
    vsPath: vsPath,
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

    test('absolute http(s) vsPath puts the asset origin into the CSP', () {
      // Firefox does not resolve CSP 'self' to the creating origin inside
      // blob: documents, so the origin must be named explicitly or every
      // same-origin asset load (loader.js, bridge, CSS, fonts) is blocked.
      final html = _build(
        isWeb: true,
        vsPath: 'http://localhost:9000/assets/monaco/min/vs',
      );
      expect(html, contains("script-src 'self' http://localhost:9000 "));
      expect(html, contains("style-src 'self' http://localhost:9000 "));
      expect(html, contains("font-src 'self' http://localhost:9000 "));
      expect(html, contains("connect-src 'self' http://localhost:9000 "));
    });

    test('relative vsPath leaves the CSP without an extra origin', () {
      final html = _build(vsPath: 'monaco/min/vs');
      expect(html, contains("script-src 'self' file: "));
      expect(html, isNot(contains("'self' http")));
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
