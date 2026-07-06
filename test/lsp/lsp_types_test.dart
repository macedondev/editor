import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LspConnectionState', () {
    test('supports value equality', () {
      const a = LspConnectionState(status: LspConnectionStatus.open);
      const b = LspConnectionState(status: LspConnectionStatus.open);
      const c = LspConnectionState(
        status: LspConnectionStatus.open,
        reconnectAttempt: 1,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('exposes lifecycle helpers', () {
      const open = LspConnectionState(status: LspConnectionStatus.open);
      const closed = LspConnectionState(status: LspConnectionStatus.closed);
      const failed = LspConnectionState(status: LspConnectionStatus.failed);
      const connecting = LspConnectionState(
        status: LspConnectionStatus.connecting,
      );

      expect(open.isOpen, isTrue);
      expect(open.isFinal, isFalse);
      expect(closed.isFinal, isTrue);
      expect(failed.isFinal, isTrue);
      expect(connecting.isOpen, isFalse);
      expect(connecting.isFinal, isFalse);
    });
  });

  group('LspReconnectPolicy', () {
    test('none() disables reconnecting', () {
      const policy = LspReconnectPolicy.none();
      expect(policy.enabled, isFalse);
      expect(policy.maxAttempts, 0);
    });

    test('exponentialBackoff grows delays and caps at maxDelay', () {
      const policy = LspReconnectPolicy.exponentialBackoff(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 10),
        maxAttempts: 10,
      );

      expect(policy.enabled, isTrue);
      expect(policy.delayFor(1), const Duration(seconds: 1));
      expect(policy.delayFor(2), const Duration(seconds: 2));
      expect(policy.delayFor(3), const Duration(seconds: 4));
      expect(policy.delayFor(4), const Duration(seconds: 8));
      expect(policy.delayFor(5), const Duration(seconds: 10)); // capped
      expect(policy.delayFor(9), const Duration(seconds: 10)); // still capped
    });

    test('supports value equality', () {
      const a = LspReconnectPolicy.exponentialBackoff();
      const b = LspReconnectPolicy.exponentialBackoff();
      expect(a, b);
      expect(a, isNot(const LspReconnectPolicy.none()));
    });
  });
}
