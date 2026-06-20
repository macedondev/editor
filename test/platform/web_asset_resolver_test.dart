import 'package:flutter_monaco/src/platform/web_view_controller/web_asset_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The URL ui_web.assetManager.getAssetUrl returns by default for Monaco's
  // bundled vs/ directory: relative to <base href>, no leading slash.
  const monacoVsAssetUrl =
      'assets/packages/flutter_monaco/assets/monaco/min/vs';

  group('resolveWebAssetUrl', () {
    test(
      'resolves against the document base URI, ignoring the SPA route (#14)',
      () {
        // Under usePathUrlStrategy(), Uri.base carries the route (e.g.
        // /canvas/123) while web.document.baseURI is the <base href> root.
        // Resolving the asset against the route would nest it under the route
        // - this is the original bug:
        expect(
          resolveWebAssetUrl(
            'https://app.example/canvas/123',
            monacoVsAssetUrl,
          ),
          'https://app.example/canvas/$monacoVsAssetUrl',
        );
        // Resolving against the document base URI (what the fix passes) yields
        // the correct root-relative asset URL, independent of the route:
        expect(
          resolveWebAssetUrl('https://app.example/', monacoVsAssetUrl),
          'https://app.example/$monacoVsAssetUrl',
        );
      },
    );

    test('honors a non-root <base href> (sub-path deployment)', () {
      expect(
        resolveWebAssetUrl('https://app.example/app/', monacoVsAssetUrl),
        'https://app.example/app/$monacoVsAssetUrl',
      );
    });

    test('passes through an absolute asset URL (CDN assetBase)', () {
      const cdnAssetUrl =
          'https://cdn.example/x/assets/packages/flutter_monaco/assets/monaco/min/vs';
      expect(
        resolveWebAssetUrl('https://app.example/', cdnAssetUrl),
        cdnAssetUrl,
      );
    });
  });
}
