/// Conditional export for the stdio language-server process helper.
///
/// Native builds (desktop) spawn and manage real processes via `dart:io`.
/// Web builds must not import `dart:io`, so they get a stub whose `start`
/// throws [UnsupportedError] with guidance to use a WebSocket or custom
/// transport instead.
library;

export 'lsp_server_process_stub.dart'
    if (dart.library.io) 'lsp_server_process_io.dart';
