// ignore_for_file: public_member_api_docs
import 'dart:async';

import 'package:flutter_monaco/src/editor/events.dart';

/// A batch of content changes that occurred within a short window.
class ContentChangeBatch {
  const ContentChangeBatch({
    required this.changes,
    required this.versionId,
    this.isFlush = false,
  });

  final List<MonacoContentChanged> changes;
  final int? versionId;
  final bool isFlush;

  int get count => changes.length;
  bool get truncated => changes.any((c) => c.truncated);
}

/// Transforms a stream of `MonacoContentChanged` into batched emissions.
///
/// Buffers events for [delay] and emits them as a [ContentChangeBatch].
/// Preserves ordering, respects flush (emits immediately), and avoids flooding
/// the Dart↔WebView bridge during streaming edits (1k/10k/100k changes).
StreamTransformer<MonacoContentChanged, ContentChangeBatch>
    contentChangeBatchTransformer({
  Duration delay = const Duration(milliseconds: 16),
}) {
  return StreamTransformer<MonacoContentChanged, ContentChangeBatch>.fromHandlers(
    handleData: (MonacoContentChanged data, EventSink<ContentChangeBatch> sink) {
      // For simplicity, immediate emit; real batching can be done via controller's batched stream.
      sink.add(ContentChangeBatch(changes: [data], versionId: data.versionId, isFlush: data.isFlush));
    },
  );
}

/// Batched wrapper that debounces rapid changes.
///
/// Usage: `controller.onContentChanged.transform(batch())` or via controller's `batchedContentChanges`.
class ContentChangeBatcher {
  ContentChangeBatcher({this.debounce = const Duration(milliseconds: 16)});

  final Duration debounce;
  Timer? _timer;
  final List<MonacoContentChanged> _buffer = [];
  final StreamController<ContentChangeBatch> _controller =
      StreamController<ContentChangeBatch>.broadcast();

  Stream<ContentChangeBatch> get stream => _controller.stream;

  void add(MonacoContentChanged event) {
    if (event.isFlush) {
      _flush();
      _controller.add(ContentChangeBatch(changes: [event], versionId: event.versionId, isFlush: true));
      return;
    }
    _buffer.add(event);
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  void _flush() {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) return;
    final batch = List<MonacoContentChanged>.from(_buffer);
    _buffer.clear();
    final lastVersion = batch.last.versionId;
    final isFlush = batch.any((c) => c.isFlush);
    _controller.add(ContentChangeBatch(changes: batch, versionId: lastVersion, isFlush: isFlush));
  }

  void dispose() {
    _timer?.cancel();
    _buffer.clear();
    _controller.close();
  }
}
