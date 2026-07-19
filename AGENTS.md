# flutter_monaco agent guidance

- Inspect the live package source, resolved dependency source, and bundled JavaScript
  before deciding how an API or bridge works. Do not guess from a generic Monaco or
  WebView integration.
- Use the package skills in `plugins/flutter-monaco/skills/` for integration, LSP,
  diagnosis, 2.x migration, bridge maintenance, and bundled Monaco upgrades. Read a
  selected SKILL.md completely and follow only its directly relevant references.
- Preserve the asynchronous lifecycle: controller creation is nonblocking, Web needs
  a mounted host before readiness, and owned controllers and documents must be
  disposed by their owner.
- Treat focus as Flutter focus, native WebView focus, and Monaco DOM focus. Preserve
  intentional route and app-level recovery instead of replaying focus blindly.
- For bridge changes, trace the Dart API through `MonacoProtocol`, bridge JavaScript,
  platform hosting, the fake bridge, Dart tests, and JavaScript tests. Keep commands,
  events, envelopes, errors, protocol versions, and packaged assets synchronized.
- Delegate an independent read-only pass to the repo-scoped
  `bridge-contract-reviewer` when a change crosses that bridge boundary. Keep the
  main agent responsible for fixes and do not delegate ordinary consumer setup or
  unrelated Flutter review to this specialist.
- After Dart edits, format the touched code and run appropriately scoped analysis and
  tests. Run the full package gates for releases or broad protocol and asset changes.
- Keep both marketplace entries, both plugin manifests, eval coverage,
  `pubspec.yaml`, documentation, and release validation synchronized. The
  assistant plugin must remain excluded from the pub.dev archive.
- Release only by merging a version change through the protected branch. The
  auto-release workflow owns `flutter_monaco-v*` tags; those tags trigger the
  trusted pub.dev publisher and are protected by the repository tag ruleset.
  Refresh pinned action and reusable-workflow SHAs only from their verified
  upstream release tags.
- Preserve unrelated local changes. Never discard work with restore, checkout,
  reset, or equivalent commands unless the user explicitly requests it.
