import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The wire protocol version this Dart side speaks.
///
/// Declared twice on purpose: here and as `PROTOCOL_VERSION` in the static
/// asset `assets/monaco/bridge/core.js`. The page reports its version in the
/// `pageReady` lifecycle message and Dart asserts equality at handshake, so
/// any skew between generated page and Dart code fails loudly instead of
/// producing undefined behavior. A test pins the two constants together.
const int kMonacoProtocolVersion = 3;

/// Sentinel distinguishing a JavaScript `undefined` result from `null`.
///
/// `MonacoProtocol.invoke` returns this instance when the response envelope
/// carries `undefined: true`. Compare with [identical].
const Object monacoJsUndefined = _MonacoJsUndefined();

class _MonacoJsUndefined {
  const _MonacoJsUndefined();

  @override
  String toString() => 'monacoJsUndefined';
}

/// Parsed `lifecycle: pageReady` payload: what the page shell reports about
/// itself before the editor exists.
@immutable
final class MonacoHandshake {
  /// Creates a handshake snapshot.
  const MonacoHandshake({
    required this.protocolVersion,
    required this.monacoVersion,
    required this.capabilities,
  });

  /// Parses the handshake fields from a `pageReady` lifecycle envelope.
  factory MonacoHandshake.fromEnvelope(Map<String, Object?> json) {
    final rawCapabilities = json['capabilities'];
    return MonacoHandshake(
      protocolVersion: json['protocolVersion'] is int
          ? json['protocolVersion']! as int
          : -1,
      monacoVersion: json['monacoVersion']?.toString() ?? 'unknown',
      capabilities: rawCapabilities is List
          ? rawCapabilities.map((e) => e.toString()).toSet()
          : const <String>{},
    );
  }

  /// Protocol version the page speaks; must equal [kMonacoProtocolVersion].
  final int protocolVersion;

  /// Monaco Editor version bundled into the page.
  final String monacoVersion;

  /// Feature capabilities the page advertises (e.g. `lsp`, `diff`).
  final Set<String> capabilities;

  @override
  String toString() =>
      'MonacoHandshake(v$protocolVersion, monaco $monacoVersion, '
      '$capabilities)';
}

/// A decoded `kind: event` envelope from the page.
@immutable
final class ProtocolEvent {
  /// Creates a decoded event.
  const ProtocolEvent({required this.name, required this.data, this.seq});

  /// Event name (`contentChanged`, `stats`, `scrollHandoff`, ...).
  final String name;

  /// Event payload.
  final Map<String, Object?> data;

  /// Page-monotonic sequence number, when present.
  final int? seq;

  @override
  String toString() => 'ProtocolEvent($name, seq: $seq)';
}

/// A decoded `kind: request` envelope: JavaScript asking Dart for an answer
/// (completion providers, custom action callbacks).
@immutable
final class ProtocolRequest {
  /// Creates a decoded request.
  const ProtocolRequest({
    required this.id,
    required this.name,
    required this.data,
  });

  /// Correlation id to answer through `MonacoProtocol.respond`.
  final String id;

  /// Request name (`completion`, `action`).
  final String name;

  /// Request payload.
  final Map<String, Object?> data;

  @override
  String toString() => 'ProtocolRequest($name, id: $id)';
}

/// Decoded envelope union used internally by `MonacoProtocol`.
sealed class EnvelopeMessage {
  const EnvelopeMessage();

  /// Decodes one channel message into an envelope, or `null` when [raw] is
  /// not a protocol v3 envelope (not JSON, not a map, or missing `kind`).
  static EnvelopeMessage? decode(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final kind = decoded['kind'];
    if (kind is! String) return null;

    switch (kind) {
      case 'lifecycle':
        final name = decoded['name'];
        if (name is! String) return null;
        return LifecycleEnvelope(name: name, json: decoded);
      case 'response':
        final id = decoded['id'];
        if (id is! String) return null;
        return ResponseEnvelope(
          id: id,
          ok: decoded['ok'] == true,
          isUndefined: decoded['undefined'] == true,
          value: decoded['value'],
          error: decoded['error'] is Map<String, Object?>
              ? decoded['error']! as Map<String, Object?>
              : null,
        );
      case 'event':
        final name = decoded['name'];
        if (name is! String) return null;
        return EventEnvelope(
          ProtocolEvent(
            name: name,
            seq: decoded['seq'] is int ? decoded['seq']! as int : null,
            data: decoded['data'] is Map<String, Object?>
                ? decoded['data']! as Map<String, Object?>
                : const <String, Object?>{},
          ),
        );
      case 'request':
        final id = decoded['id'];
        final name = decoded['name'];
        if (id is! String || name is! String) return null;
        return RequestEnvelope(
          ProtocolRequest(
            id: id,
            name: name,
            data: decoded['data'] is Map<String, Object?>
                ? decoded['data']! as Map<String, Object?>
                : const <String, Object?>{},
          ),
        );
      case 'log':
        return LogEnvelope(
          level: decoded['level']?.toString() ?? 'info',
          message: decoded['message']?.toString() ?? '',
        );
      default:
        return UnknownEnvelope(kind: kind, json: decoded);
    }
  }
}

/// `kind: lifecycle` envelope (`pageReady`, `ready`, `fatal`).
final class LifecycleEnvelope extends EnvelopeMessage {
  /// Creates a lifecycle envelope.
  const LifecycleEnvelope({required this.name, required this.json});

  /// Lifecycle stage name.
  final String name;

  /// Full envelope payload (handshake fields, fatal error details).
  final Map<String, Object?> json;
}

/// `kind: response` envelope answering a dispatched command.
final class ResponseEnvelope extends EnvelopeMessage {
  /// Creates a response envelope.
  const ResponseEnvelope({
    required this.id,
    required this.ok,
    required this.isUndefined,
    required this.value,
    required this.error,
  });

  /// Correlation id of the originating dispatch.
  final String id;

  /// Whether the command succeeded.
  final bool ok;

  /// Whether the JavaScript result was `undefined`.
  final bool isUndefined;

  /// The JSON result value (null when [isUndefined] or on failure).
  final Object? value;

  /// Error payload `{name, message, stack}` on failure.
  final Map<String, Object?>? error;
}

/// `kind: event` envelope.
final class EventEnvelope extends EnvelopeMessage {
  /// Creates an event envelope.
  const EventEnvelope(this.event);

  /// The decoded event.
  final ProtocolEvent event;
}

/// `kind: request` envelope.
final class RequestEnvelope extends EnvelopeMessage {
  /// Creates a request envelope.
  const RequestEnvelope(this.request);

  /// The decoded request.
  final ProtocolRequest request;
}

/// `kind: log` envelope.
final class LogEnvelope extends EnvelopeMessage {
  /// Creates a log envelope.
  const LogEnvelope({required this.level, required this.message});

  /// Log severity (`info`, `warn`, `error`).
  final String level;

  /// Log text.
  final String message;
}

/// Envelope with an unrecognized `kind` (forward compatibility).
final class UnknownEnvelope extends EnvelopeMessage {
  /// Creates an unknown-kind envelope.
  const UnknownEnvelope({required this.kind, required this.json});

  /// The unrecognized kind.
  final String kind;

  /// Full payload.
  final Map<String, Object?> json;
}
