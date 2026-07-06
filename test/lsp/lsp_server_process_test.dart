@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // `cat` echoes stdin to stdout, which makes it a perfect loopback "server"
  // for exercising framing, the transport pump, and process lifecycle.
  final hasCat = !Platform.isWindows;

  group('LspServerProcess', () {
    test(
      'round-trips framed messages through a real process',
      () async {
        final server = await LspServerProcess.start('cat', []);
        addTearDown(server.stop);

        final received = <Map<String, Object?>>[];
        final sub = server.transport.fromServer.listen(received.add);
        addTearDown(sub.cancel);

        server.transport.toServer({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'processId': null},
        });
        server.transport.toServer({
          'jsonrpc': '2.0',
          'method': 'initialized',
          'params': <String, Object?>{},
        });

        await _poll(() => received.length == 2);
        expect(received[0]['method'], 'initialize');
        expect(received[1]['method'], 'initialized');
      },
      skip: hasCat ? false : 'requires a POSIX cat binary',
    );

    test(
      'stop() closes stdin and reaps the process',
      () async {
        final server = await LspServerProcess.start('cat', []);
        expect(server.isStopped, isFalse);

        final code = await server.stop();
        expect(code, 0); // cat exits cleanly on stdin EOF
        expect(server.isStopped, isTrue);

        // Idempotent.
        expect(await server.stop(), 0);
      },
      skip: hasCat ? false : 'requires a POSIX cat binary',
    );

    test(
      'fromServer closes when the process exits',
      () async {
        final server = await LspServerProcess.start('cat', []);

        final done = Completer<void>();
        server.transport.fromServer.listen((_) {}, onDone: done.complete);

        await server.stop();
        await done.future.timeout(const Duration(seconds: 5));
      },
      skip: hasCat ? false : 'requires a POSIX cat binary',
    );

    test('start() surfaces spawn failures', () async {
      expect(
        () => LspServerProcess.start(
          'definitely-not-a-real-language-server-binary',
          [],
        ),
        throwsA(isA<ProcessException>()),
      );
    });
  });
}

Future<void> _poll(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
