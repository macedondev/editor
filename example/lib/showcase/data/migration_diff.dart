/// Content for the live migration diff: the same small editor service written
/// against flutter_monaco 2.x (original) and 3.0 (modified). The changed
/// hunks are the real migration story - documents, typed errors, sparse
/// options, typed action ids, and the sealed event union.
library;

/// The 2.x side of the migration diff.
const String kMigrationOriginal = '''
// editor_service.dart - written against flutter_monaco 2.x
import 'package:flutter_monaco/flutter_monaco.dart';

Future<MonacoController> boot() async {
  // Blocked until ready on native, returned early on web.
  final controller = await MonacoController.create(
    options: const EditorOptions(
      language: MonacoLanguage.dart,
      fontSize: 14,
      themeId: 'app-dark', // custom themes need a side-channel field
    ),
  );
  return controller;
}

Future<void> save(MonacoController controller) async {
  // '' could mean "empty document" or "bridge died" - no way to tell.
  final text = await controller.getValue();
  await upload(text);
}

Future<void> shrinkFont(MonacoController controller) async {
  // Sent ALL ~40 options; every unset field reset to package defaults.
  await controller.updateOptions(const EditorOptions(fontSize: 12));
}

Future<void> tidy(MonacoController controller) async {
  await controller.format();
  await controller.setValue('// formatted');
}

void watch(MonacoController controller) {
  // Raw payloads; full-text pulls on every keystroke.
  controller.onContentChanged.listen((_) async {
    final text = await controller.getValue();
    await upload(text);
  });
}
''';

/// The 3.0 side of the migration diff.
const String kMigrationModified = '''
// editor_service.dart - written against flutter_monaco 3.0
import 'package:flutter_monaco/flutter_monaco.dart';

Future<MonacoController> boot() async {
  // Never blocks, on any platform; readiness is one explicit future.
  final controller = await MonacoController.create(
    options: const EditorOptions(
      language: MonacoLanguage.dart,
      fontSize: 14,
      theme: MonacoTheme('app-dark'), // one open typed id, no side channel
    ),
  );
  await controller.whenReady;
  return controller;
}

Future<void> save(MonacoController controller) async {
  // Documents are first-class; failed reads throw typed MonacoExceptions.
  final text = await controller.document.getText();
  await upload(text);
}

Future<void> shrinkFont(MonacoController controller) async {
  // Sparse options: this changes the font size and nothing else.
  await controller.updateOptions(const EditorOptions(fontSize: 12));
}

Future<void> tidy(MonacoController controller) async {
  await controller.executeAction(MonacoAction.formatDocument);
  await controller.document.setText('// formatted');
}

void watch(MonacoController controller) {
  // One sealed event union with structured change ranges.
  controller.events.listen((event) async {
    if (event is MonacoContentChanged && !event.truncated) {
      await uploadDeltas(event.changes!);
    }
  });
}
''';
