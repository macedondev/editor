# flutter_monaco example

Run the minimal editor from the repository root:

```sh
cd example
flutter pub get
flutter run
```

Other focused entrypoints:

```sh
flutter run -t lib/complete_example.dart
flutter run -t lib/showcase/main.dart
flutter run -d chrome -t lib/web_demo.dart
flutter run -d macos -t lib/diff_example.dart
flutter run -t lib/lsp_example.dart
```

The LSP demo needs either a WebSocket-fronted language server or a local stdio
language-server executable. Its on-screen controls describe both transports.
