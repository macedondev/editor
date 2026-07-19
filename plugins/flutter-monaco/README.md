# Flutter Monaco assistant plugin

Installable, package-specific coding-assistant support for the
[`flutter_monaco`](https://pub.dev/packages/flutter_monaco) Flutter package. The
same six skills serve Claude Code and OpenAI Codex from one `skills/` tree.

This plugin is repository tooling. It is not part of the Dart runtime API and is
excluded from the pub.dev archive.

## Included guidance

| Component | Type | Use it for |
|---|---|---|
| `integrate-flutter-monaco` | skill | Adding the editor, choosing widget-owned or controller-owned lifecycle, multi-document state, typed events, overlays, and platform setup |
| `configure-flutter-monaco-lsp` | skill | Selecting WebSocket, bridged stdio, or custom LSP transport and configuring page security, URIs, lifecycle, and platform constraints |
| `diagnose-flutter-monaco` | skill | Boot, asset, protocol, focus, overlay, LSP, scroll-handoff, and disposal failures |
| `migrate-flutter-monaco-v2-to-v3` | skill | Moving an existing 2.x integration to the current 3.x APIs and wire protocol |
| `maintain-flutter-monaco-bridge` | skill | Changing Dart commands or events, the JavaScript bridge, platform hosts, fakes, and contract tests together |
| `upgrade-bundled-monaco` | skill | Replacing the bundled Monaco distribution, worker assets, warmup manifest, and bridge compatibility checks |
| `bridge-contract-reviewer` | Claude Code agent | Read-only source audit for Dart-to-JavaScript contract drift. It applies the bridge skill as the canonical procedure |
| `.codex/agents/bridge-contract-reviewer.toml` | repository Codex agent | The same narrow read-only audit while Codex works inside this source repository |
| `evals/` | regression cases | Positive selection, execution, adjacent negative, and missing-information cases checked by the repository validator |

There are no hooks, MCP servers, apps, connectors, settings, executables, runtime
services, or credential requests in this plugin. Installing it adds instruction and
reference files only. The host assistant can still use tools that the user has
allowed in that assistant.

## Claude Code

Install from the GitHub marketplace:

```bash
claude plugin marketplace add omar-hanafy/flutter_monaco --sparse .claude-plugin plugins
claude plugin install flutter-monaco@flutter-monaco-plugins
```

Start a new Claude Code session after installation. Skills can activate from the
request or be invoked explicitly:

```text
/flutter-monaco:integrate-flutter-monaco
/flutter-monaco:configure-flutter-monaco-lsp
/flutter-monaco:diagnose-flutter-monaco
/flutter-monaco:migrate-flutter-monaco-v2-to-v3
/flutter-monaco:maintain-flutter-monaco-bridge
/flutter-monaco:upgrade-bundled-monaco
```

Claude Code can delegate package-source bridge audits to
`flutter-monaco:bridge-contract-reviewer`. The agent has only Read, Grep, and Glob
tools and does not make fixes.

Update or remove:

```bash
claude plugin marketplace update flutter-monaco-plugins
claude plugin update flutter-monaco@flutter-monaco-plugins

claude plugin uninstall flutter-monaco@flutter-monaco-plugins
claude plugin marketplace remove flutter-monaco-plugins
```

## OpenAI Codex

Install from the GitHub marketplace:

```bash
codex plugin marketplace add omar-hanafy/flutter_monaco --sparse .agents --sparse plugins
codex plugin add flutter-monaco@flutter-monaco
```

Start a new Codex session after installation. Interactive clients can also use the
`/plugins` browser. Skills can activate from the request or be named explicitly:

```text
$integrate-flutter-monaco
$configure-flutter-monaco-lsp
$diagnose-flutter-monaco
$migrate-flutter-monaco-v2-to-v3
$maintain-flutter-monaco-bridge
$upgrade-bundled-monaco
```

Codex plugins do not bundle custom subagents. This source repository therefore keeps
the optional read-only reviewer at `.codex/agents/bridge-contract-reviewer.toml` for
Codex sessions opened in the flutter_monaco checkout. Consumer repositories receive
the skills, not that project-scoped agent.

Update or remove:

```bash
codex plugin marketplace upgrade flutter-monaco
codex plugin add flutter-monaco@flutter-monaco

codex plugin remove flutter-monaco@flutter-monaco
codex plugin marketplace remove flutter-monaco
```

## Example requests

- "Integrate flutter_monaco with three tabs and stable file URIs."
- "Connect this editor to a language server on Web and macOS."
- "The Web editor mounts but never becomes ready. Diagnose it."
- "Migrate this flutter_monaco 2.x screen to 3.x without losing its focus rules."
- "Add a bridge command and update every Dart and JavaScript contract boundary."
- "Upgrade the bundled Monaco engine and verify workers and dynamic chunks."

## Compatibility

- Consumer skills target `flutter_monaco` 3.x and inspect the resolved package APIs
  before proposing code. The migration skill covers 2.x to 3.x.
- Both plugin manifests use version `3.4.2`, matching the package release that ships
  this support.
- The manifests and commands were validated with Claude Code 2.1.214 and Codex CLI
  0.144.6. The shared SKILL.md frontmatter deliberately uses the fields accepted by
  both clients.
- Claude Code supports the bundled reviewer agent. Codex CLI, Codex desktop Work and
  Codex modes, and ChatGPT web Work mode support the shared plugin skill surface;
  only Codex sessions in this repository discover the project-scoped Codex reviewer.
- The local Codex commands configure local Codex. ChatGPT web uses its own plugin
  catalog flow. Codex IDE integrations and mobile do not currently provide the
  plugin browser used by this installation flow.

## Validate a checkout

From the repository root:

```bash
claude plugin validate ./plugins/flutter-monaco --strict
claude plugin validate . --strict
dart run tool/validate_ai_extensions.dart
```

The repository eval cases are deterministic fixtures for selection and execution
expectations. Static validation proves their shape and coverage, not model behavior.
At release time, Claude Code reports native `claude plugin eval` as early access and
does not make that command available as a stable release gate. Forward tests are run
separately and their limits must be reported honestly.

## Maintenance rules

- Keep one canonical skill tree. Do not fork Claude-specific and Codex-specific
  copies.
- Keep the package version synchronized across `pubspec.yaml` and both plugin
  manifests.
- Add or change a skill only with positive selection, realistic execution, adjacent
  negative, and missing-information eval cases.
- Keep the bridge reviewer thin. Contract steps belong in
  `maintain-flutter-monaco-bridge`, not in a second independent procedure.
- Do not add hooks, executables, network services, or credentials unless a future
  release demonstrates a package-specific need and documents the security change.
