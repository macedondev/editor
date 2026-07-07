import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('commands await readiness uniformly on all platforms', () {
    final source = File(
      'lib/src/core/monaco_controller.dart',
    ).readAsStringSync();

    // Protocol v3 removed the hand-rolled pre-ready queues and the web/native
    // divergence: every command gates on readiness through _ensureReady.
    expect(source, contains('await _ensureReady();'));
    expect(source, isNot(contains('_queuedValue')));
    expect(source, isNot(contains('_queuedLanguage')));
    expect(source, isNot(contains('if (kIsWeb) return;')));
  });
}
