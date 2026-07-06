/// Conditional storage helpers for Monaco asset extraction.
///
/// Native builds extract bundled assets to application support storage. Web
/// builds serve the package assets directly and must not import `dart:io` or
/// `path_provider`, so they use the stub implementation.
library;

export 'monaco_asset_storage_web.dart'
    if (dart.library.io) 'monaco_asset_storage_io.dart';
