import 'dart:convert';
import 'dart:typed_data';

/// Encodes JSON-RPC messages into the LSP base protocol's stdio framing.
///
/// Each frame is `Content-Length: <bytes>\r\n\r\n<utf-8 JSON body>`, where
/// `<bytes>` is the UTF-8 byte length of the body (not its character count).
///
/// Used by `LspServerProcess` to write to a language server's stdin; exposed
/// publicly for apps that integrate their own process or socket plumbing via
/// `LspBridgedTransport`.
abstract final class LspStdioMessageEncoder {
  /// Frames [message] as LSP base-protocol bytes.
  static Uint8List encode(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');
    final builder = BytesBuilder(copy: false)
      ..add(header)
      ..add(body);
    return builder.takeBytes();
  }
}

/// Incremental decoder for the LSP base protocol's stdio framing.
///
/// Feed raw stdout chunks with [addBytes]; complete JSON-RPC messages are
/// returned as parsed maps. The decoder is robust to partial chunks, multiple
/// frames per chunk, additional headers (e.g. `Content-Type`), and
/// case-insensitive header names.
///
/// Throws [FormatException] when the stream is unrecoverably malformed
/// (missing `Content-Length` header or a body that is not valid JSON). After
/// a throw the decoder state is undefined; discard it together with the
/// connection.
class LspStdioMessageDecoder {
  static final RegExp _contentLength = RegExp(
    r'content-length:\s*(\d+)',
    caseSensitive: false,
  );

  final List<int> _buffer = <int>[];
  int _start = 0;
  int? _expectedBodyLength;

  /// Number of buffered, not-yet-consumed bytes.
  int get pendingBytes => _buffer.length - _start;

  /// Adds [chunk] and returns every message completed by it (possibly none).
  List<Map<String, Object?>> addBytes(List<int> chunk) {
    _buffer.addAll(chunk);
    final messages = <Map<String, Object?>>[];

    while (true) {
      if (_expectedBodyLength == null) {
        final headerEnd = _indexOfHeaderTerminator();
        if (headerEnd < 0) break;

        final headerText = ascii.decode(
          _buffer.sublist(_start, headerEnd),
          allowInvalid: true,
        );
        final match = _contentLength.firstMatch(headerText);
        if (match == null) {
          throw FormatException(
            'LSP frame is missing a Content-Length header: "$headerText"',
          );
        }
        _expectedBodyLength = int.parse(match.group(1)!);
        _start = headerEnd + 4; // consume "\r\n\r\n"
      }

      final expected = _expectedBodyLength!;
      if (pendingBytes < expected) break;

      final bodyBytes = _buffer.sublist(_start, _start + expected);
      _start += expected;
      _expectedBodyLength = null;
      _compact();

      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(bodyBytes));
      } on FormatException catch (e) {
        throw FormatException('LSP frame body is not valid JSON: $e');
      }
      if (decoded is Map<String, dynamic>) {
        messages.add(decoded);
      }
      // Non-object frames are not valid JSON-RPC 2.0 traffic from a server
      // (batching is unused by LSP); tolerate and skip them.
    }

    _compact(force: pendingBytes == 0);
    return messages;
  }

  int _indexOfHeaderTerminator() {
    for (var i = _start; i + 3 < _buffer.length; i++) {
      if (_buffer[i] == 0x0D &&
          _buffer[i + 1] == 0x0A &&
          _buffer[i + 2] == 0x0D &&
          _buffer[i + 3] == 0x0A) {
        return i;
      }
    }
    return -1;
  }

  /// Drops consumed bytes so the buffer doesn't grow without bound. Skipped
  /// for small offsets to avoid quadratic copying on chatty streams.
  void _compact({bool force = false}) {
    if (_start == 0) return;
    if (!force && _start < 8192) return;
    _buffer.removeRange(0, _start);
    _start = 0;
  }
}
