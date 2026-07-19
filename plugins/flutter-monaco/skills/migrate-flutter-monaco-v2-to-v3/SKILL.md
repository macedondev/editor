---
name: migrate-flutter-monaco-v2-to-v3
description: Migrate an application from flutter_monaco 2.x to 3.x using the complete API and lifecycle map, or migrate 1.7.1 after its toolchain and Windows prerequisites are verified. Use when pubspec or source still uses legacy content methods, model APIs, full-state options, old focus/events, old readiness, or page configuration. Do not use when the app is already fully on 3.x or when upgrading the bundled Monaco engine inside this package.
---

# Migrate Flutter Monaco v2 to v3

Treat this as a source migration with behavioral changes, not a dependency-only bump. Read the consuming app, its locked source version, persisted option/state formats, supported platforms, and the current package README. A 1.7.1 app may use the same source map after the Dart, Flutter, and Windows WebView prerequisites documented in the reference are verified; normal barrel consumers did not have a separate 1.7.1-to-2.x symbol rewrite.

Read [references/v2-to-v3-map.md](references/v2-to-v3-map.md) completely before editing.
Use [fixtures/cases.json](fixtures/cases.json) to test normal migration, persisted-value judgment, already-migrated input, the 1.7.1 prerequisite audit, an unsupported future version, and recovery from a Web readiness regression.

## Workflow

1. Establish the baseline. Run the app's analyzer/tests and save the exact existing failures. Do not discard local changes.
2. Inventory legacy usage with every `rg` review queue in the reference. Include generated adapters, tests, persisted JSON, and custom wrappers. Trace controller aliases so qualified stream searches do not miss renamed variables.
3. Update the dependency to the intended 3.x range and resolve packages.
4. Migrate lifecycle and ownership first: `create` readiness, `initialText`, `MonacoPageConfig`, mounting on Web, and disposal.
5. Migrate content/models to `MonacoDocument`, then options/types, actions, decorations/markers/completions, focus, events, and view state.
6. Audit behavior that still compiles: sparse option reads and updates, changed boot defaults, typed errors instead of defaults, JavaScript conversion failures, strict public parsers, typed stats/state, open typed ids, scroll boundary policy, asset diagnostics, stable document URIs, and persisted JSON.
7. Format, analyze, test, and exercise every supported platform whose WebView lifecycle or focus behavior matters.

## Recovery

Before modifying persisted settings, keep a recoverable copy and confirm how the app rolls back its schema. Keep the dependency and source edits reviewable as one migration slice. If validation fails, preserve the first error, restore the last known-good app state through the project's normal version-control workflow only with the user's authorization, and reapply the migration in smaller symbol families. Reverting the dependency alone is not sufficient after stored options have been rewritten.

## Stop conditions

- If the starting version is 1.7.1, verify the documented 2.0 toolchain and Windows prerequisites before applying the same source map. For any earlier or locally forked 1.x source, inspect its intervening release notes and actual barrel diff instead of assuming compatibility.
- If the source major is newer than the target or outside the versions documented here, stop before editing. Inspect the exact installed package and select a migration path supported by that source and target.
- If the dependency files or integration source are unavailable, stop before editing and request access to the actual source. A migration cannot be validated from a prose description alone.
- If the app depends on a removed method through a local fork, inspect that fork and decide whether the behavior belongs in app code or a package contribution.
- If persisted 2.x options cannot be re-created from source data, require an explicit data migration policy. Do not silently parse them as 3.x.
- If a target platform is unavailable, report it as unverified rather than inferring runtime success from analyzer output.

## Verification

- The removed-name search finds no old symbols except deliberate migration documentation or fixtures, and every surviving-signature and source-compatible behavior review result has a recorded decision.
- Analyzer and tests pass at least as well as the recorded baseline.
- Web self-owned controllers mount before readiness.
- Reads surface typed failures and the app applies fallback behavior explicitly where required.
- Explicit options preserve the old editor defaults where product behavior requires them, and scroll handoff chooses either `continuous` or `newGestureOnly` intentionally.
- Persisted value objects use verified 3.x keys and types; stats, state, and typed ids no longer rely on v2 record or enum behavior.
- Documents keep stable URIs, switching state, dirty tracking, and view state.
- Keyboard focus works after navigation/app resume on each desktop/mobile target in scope.

Report old and new versions, migrated symbol families, behavioral decisions, persisted-data handling, platforms exercised, and remaining risks.
