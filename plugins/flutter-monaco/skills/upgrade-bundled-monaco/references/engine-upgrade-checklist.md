# Bundled Monaco engine upgrade checklist

## Baseline

- Read `lib/src/assets/monaco_assets.dart` for `MonacoAssets.monacoVersion`.
- Inventory `assets/monaco/min/` file count and byte size.
- Run `flutter test test/assets test/protocol test/lsp` and `node --test tool/bridge_tests/*_test.mjs`.
- Capture `dart pub publish --dry-run` archive contents and size.

## Upstream artifact

- Use the exact official `monaco-editor` release artifact.
- Fetch it reproducibly from the npm registry with `npm pack monaco-editor@<exact-version> --json` in a new temporary directory. Record the resolved version, tarball filename, `shasum`, and `integrity` values from the JSON output. Treat a version mismatch or missing integrity metadata as a stop condition.
- Extract the tarball into that temporary directory and verify `package/package.json` reports the requested version before touching repository assets. Compare the new `package/min/` inventory and license files to the current bundle.
- Stage the verified `package/min/` tree as the replacement for the exact `assets/monaco/min/` directory. Preserve `assets/monaco/bridge/`, inspect the diff, and avoid broad deletion globs or paths outside the repository.
- Retain applicable upstream license notices and the acquisition metadata in the release evidence.
- Prefer the supported minified `min/vs` distribution. Do not publish an entire dependency checkout, caches, source maps, or development sources unless the runtime requires them.
- Preserve `assets/monaco/bridge/`; it is package code, not upstream Monaco output.

## Version and cache

Search the repository for the old exact version. Update the production constant and intentional test fixtures, but do not rewrite historical changelog entries.

The engine version participates in extraction paths and sentinel validation. Verify a stale prior cache is not accepted for the new release and repeated initialization is idempotent.

## Loader, chunks, and workers

- Confirm `vs/loader.js`, `vs/editor/editor.main.js`, and `editor.main.css` exist.
- Re-run warmup manifest tests. The runtime discovers hash-named editor chunks from `editor.main.js`; update invariants if upstream syntax legitimately changed.
- Exercise TypeScript/JavaScript, JSON, CSS, and HTML workers and at least one basic language.
- Check AMD base paths on Web and extracted native paths.

## Bridge and protocol

Run structural tests for every bridge file and the real Node harness. Confirm boot remains last, handshake reports the new Monaco version, command registrations still match fixtures, and no private Monaco method changed beneath a bridge handler.

The Dart-JS protocol version changes only when the wire contract becomes incompatible. Engine version skew is reported separately in the handshake.

## LSP

The LSP integration relies on engine APIs and some explicitly experimental raw request/notification internals. Verify:

- transport creation and initialize handshake
- document synchronization with stable URIs
- diagnostics
- completion or hover
- disconnect and unexpected drop behavior
- any raw server request/notification feature the package documents

## Release gates

- Format and full `dart analyze`
- Full `flutter test`
- Node bridge tests
- Asset/source invariant tests
- Example compile/build where practical
- `dart doc`
- Pana and `dart pub publish --dry-run`
- Archive content and size comparison
- Manual Web cold-cache boot and representative native WebView smoke

Explain every significant size delta before publication.
