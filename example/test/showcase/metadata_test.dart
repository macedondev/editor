import 'package:flutter_monaco_example/showcase/data/showcase_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('showcase metadata', () {
    test('parses package metadata from pubspec yaml', () {
      final metadata = parseShowcasePubspec('''
name: flutter_monaco
description: Current description
version: 2.1.0
repository: https://github.com/omar-hanafy/flutter_monaco
issue_tracker: https://github.com/omar-hanafy/flutter_monaco/issues
topics:
  - monaco
  - editor
platforms:
  android:
  ios:
  web:
environment:
  sdk: ">=3.12.0 <4.0.0"
  flutter: ">=3.44.0"
''');

      expect(metadata.packageName, 'flutter_monaco');
      expect(metadata.version, '2.1.0');
      expect(metadata.description, 'Current description');
      expect(metadata.topics, ['monaco', 'editor']);
      expect(metadata.platforms.map((platform) => platform.id), [
        'android',
        'ios',
        'web',
      ]);
      expect(metadata.sdkConstraint, '>=3.12.0 <4.0.0');
      expect(metadata.flutterConstraint, '>=3.44.0');
    });

    test('pub.dev merge adds provenance but keeps the bundled build data', () {
      final metadata = parsePubDevPackage({
        'latest': {
          'version': '2.2.0',
          'published': '2026-06-21T10:00:00.000Z',
          'pubspec': {
            'name': 'flutter_monaco',
            'description': 'Live description',
            'version': '2.2.0',
            'repository': 'https://github.com/omar-hanafy/flutter_monaco',
            'platforms': {'windows': null, 'web': null},
            'environment': {'sdk': '>=3.12.0 <4.0.0'},
          },
        },
      });

      // The page reports the build it actually runs (the bundled pubspec);
      // pub.dev only contributes provenance and live stats.
      expect(metadata.version, ShowcaseMetadata.fallback.version);
      expect(metadata.description, ShowcaseMetadata.fallback.description);
      expect(metadata.latestPubVersion, '2.2.0');
      expect(metadata.hasLivePubDev, isTrue);
      expect(metadata.publishedAt, isNotNull);
      expect(
        metadata.publishedLabel,
        'v2.2.0 on pub.dev · ${formatShortDate(metadata.publishedAt!)}',
      );
      expect(
        metadata.platforms.map((platform) => platform.id),
        ShowcaseMetadata.fallback.platforms.map((platform) => platform.id),
      );
    });
  });
}
