# AI coding-assistant support

Flutter Monaco publishes package-specific guidance for Claude Code and OpenAI Codex
from the repository's `plugins/flutter-monaco/` directory. The extension helps an
assistant use the real 3.x API, diagnose layered WebView failures, migrate 2.x code,
and keep the Dart-to-JavaScript bridge synchronized.

The extension is installed from GitHub, not by `dart pub add`. It is deliberately
excluded from the pub.dev archive and does not affect application size or runtime
behavior.

## What the extension includes

Six shared skills cover the package's high-risk workflows:

- `integrate-flutter-monaco`
- `configure-flutter-monaco-lsp`
- `diagnose-flutter-monaco`
- `migrate-flutter-monaco-v2-to-v3`
- `maintain-flutter-monaco-bridge`
- `upgrade-bundled-monaco`

Claude Code also receives a narrowly scoped, read-only
`bridge-contract-reviewer` agent. Codex plugins cannot bundle custom agents, so the
source repository contains an equivalent project agent at
`.codex/agents/bridge-contract-reviewer.toml`. That Codex agent is available only
when working in this checkout. The bridge-maintenance skill remains the canonical
procedure for both reviewers.

## Install for Claude Code

```bash
claude plugin marketplace add omar-hanafy/flutter_monaco --sparse .claude-plugin plugins
claude plugin install flutter-monaco@flutter-monaco-plugins
```

Start a new Claude Code session. Skills normally activate from context. To select one
explicitly, enter its namespaced slash command, for example:

```text
/flutter-monaco:integrate-flutter-monaco
/flutter-monaco:diagnose-flutter-monaco
/flutter-monaco:maintain-flutter-monaco-bridge
```

All six commands are listed in the
[`plugins/flutter-monaco` README on GitHub](https://github.com/omar-hanafy/flutter_monaco/blob/main/plugins/flutter-monaco/README.md).

Update:

```bash
claude plugin marketplace update flutter-monaco-plugins
claude plugin update flutter-monaco@flutter-monaco-plugins
```

Remove:

```bash
claude plugin uninstall flutter-monaco@flutter-monaco-plugins
claude plugin marketplace remove flutter-monaco-plugins
```

## Install for OpenAI Codex

```bash
codex plugin marketplace add omar-hanafy/flutter_monaco --sparse .agents --sparse plugins
codex plugin add flutter-monaco@flutter-monaco
```

Start a new Codex session so it loads the installed skills. In plugin-capable
interactive clients, `/plugins` provides the browser. To select a skill explicitly,
mention it with `$`, for example:

```text
$integrate-flutter-monaco
$diagnose-flutter-monaco
$maintain-flutter-monaco-bridge
```

Update:

```bash
codex plugin marketplace upgrade flutter-monaco
codex plugin add flutter-monaco@flutter-monaco
```

Remove:

```bash
codex plugin remove flutter-monaco@flutter-monaco
codex plugin marketplace remove flutter-monaco
```

## Supported clients and versions

| Client | Support in this release |
|---|---|
| Claude Code 2.1.214 (validated) | Marketplace plugin, six skills, and the bundled read-only reviewer |
| Codex CLI 0.144.6 (validated) | Marketplace plugin and six skills; the source checkout also exposes the project reviewer |
| Codex desktop Work and Codex modes | The same Codex plugin skill surface |
| ChatGPT web Work mode | The shared plugin skill surface through the web product's plugin catalog flow |
| Codex IDE integrations and mobile | No plugin browser for this installation flow |

The local Codex commands above configure local Codex, not ChatGPT web. The package
skills target Flutter Monaco 3.x after inspecting the app's resolved dependency. The
migration skill covers the breaking 2.x to 3.x transition.

Start a new assistant session after install or update. Existing sessions can keep a
cached plugin snapshot.

## Security and privacy

The plugin contains instructions, references, eval fixtures, and read-only reviewer
definitions. It contains no hooks, MCP server, app, connector, executable, runtime
service, authentication flow, or credential configuration. Installing it does not
contact a Flutter Monaco service. As with any coding assistant, the host can read or
change only what its own user-approved tools and sandbox permit.

## Validation and eval scope

Maintainers validate both product manifests and the shared extension contract from
the repository root:

```bash
claude plugin validate ./plugins/flutter-monaco --strict
claude plugin validate . --strict
dart run tool/validate_ai_extensions.dart
```

The eval fixture set covers four case classes per skill: positive selection,
realistic execution, adjacent negative triggering, and required information that is
missing. The repository validator checks that coverage and fixture structure. It
cannot prove that every future model will select or execute a skill correctly, so
release work also uses fresh-session forward tests.

The installed Claude Code CLI currently labels `claude plugin eval` as early access
and does not expose it as a stable release gate. This project does not claim a native
Claude eval pass until that command is available and actually runs.

## Specification references

The release metadata and commands follow the current primary documentation:

- [Claude Code plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
- [Claude Code plugins](https://code.claude.com/docs/en/plugins) and [plugin reference](https://code.claude.com/docs/en/plugins-reference)
- [OpenAI Codex plugin building](https://learn.chatgpt.com/docs/build-plugins) and [plugin installation](https://learn.chatgpt.com/docs/plugins)
- [OpenAI skill building](https://learn.chatgpt.com/docs/build-skills) and [Codex custom agents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Dart package publishing and archive rules](https://dart.dev/tools/pub/publishing)

## Troubleshooting assistant installation

- If a skill is missing, verify the marketplace and plugin with the client's list or
  plugin browser, then start a new session.
- If guidance is stale, update the marketplace and reinstall or update the plugin,
  then start a new session.
- If two marketplaces use the same name, remove the stale registration before adding
  this repository again.
- If a suggestion conflicts with the installed Dart package, inspect the resolved
  package source. The live API is authoritative.
