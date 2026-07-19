import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('complete example mounts before readiness-dependent registrations', () {
    final source = File('example/lib/complete_example.dart').readAsStringSync();
    final initializeStart = source.indexOf(
      'Future<void> _initializeEditor() async {',
    );
    final initializeEnd = source.indexOf(
      'Future<void> _registerCompletionSources',
      initializeStart,
    );

    expect(initializeStart, isNonNegative);
    expect(initializeEnd, greaterThan(initializeStart));

    final initializeBody = source.substring(initializeStart, initializeEnd);
    expect(initializeBody, contains('initialText: _sampleCode'));
    expect(initializeBody, isNot(contains('document.setText(')));

    final mountController = initializeBody.indexOf('_controller = controller;');
    final showEditor = initializeBody.indexOf('_isLoading = false;');
    final registerCompletions = initializeBody.indexOf(
      'await _registerCompletionSources(controller);',
    );
    final registerAction = initializeBody.indexOf(
      'await _registerSaveAction(controller);',
    );

    expect(mountController, isNonNegative);
    expect(showEditor, greaterThan(mountController));
    expect(registerCompletions, greaterThan(showEditor));
    expect(registerAction, greaterThan(registerCompletions));
  });
}
