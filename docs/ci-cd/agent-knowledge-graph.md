# Agent Knowledge Graph

This project includes project-scoped Graphify guidance so coding agents can use a
repository knowledge graph for architecture and relationship questions.

Graphify is installed as the Python package `graphifyy`; the command is
`graphify`. The project-scoped adapter files were generated with Graphify
`0.8.36`.

## Install Locally

Recommended:

```powershell
uv tool install graphifyy
graphify install --project --platform codex
graphify install --project --platform claude
graphify install --project --platform opencode
graphify install --project --platform cursor
graphify install --project --platform gemini
graphify install --project --platform aider
graphify install --project --platform copilot
```

The project tracks portable Graphify integration for:

- Codex: `AGENTS.md` and `.codex/skills/graphify/`
- Claude Code: `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/settings.json`,
  and `.claude/skills/graphify/`
- OpenCode: `.opencode/opencode.json`, `.opencode/plugins/graphify.js`, and
  `.opencode/skills/graphify/`
- Cursor: `.cursor/rules/graphify.mdc`
- Gemini CLI: `GEMINI.md`, `.gemini/settings.json`, and
  `.gemini/skills/graphify/`
- Aider: `.aider/graphify/` plus the shared `AGENTS.md` guidance
- Copilot: `.copilot/skills/graphify/`

The project tracks:

- `AGENTS.md`
- `.codex/skills/graphify/`
- `CLAUDE.md`
- `GEMINI.md`
- `.claude/`
- `.opencode/opencode.json`
- `.opencode/plugins/graphify.js`
- `.opencode/skills/graphify/`
- `.cursor/rules/graphify.mdc`
- `.gemini/`
- `.aider/graphify/`
- `.copilot/skills/graphify/`

The project does not track:

- `.codex/hooks.json`, because Graphify generated it with a local absolute
  executable path on this machine.
- `.opencode/node_modules/` and OpenCode package lockfiles, because they are
  local tool dependencies.
- `graphify-out/`, because it is generated and can be large.

## Build The Graph

From the repository root:

```powershell
graphify extract . --no-cluster
```

This full-repository extraction needs an LLM API key because the repo contains
docs, HTML, and image files. Configure one supported provider key in the local
environment, for example `DEEPSEEK_API_KEY`, `OPENAI_API_KEY`,
`ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, or `GOOGLE_API_KEY`.

For ongoing maintenance after code changes:

```powershell
graphify update .
```

Useful queries:

```powershell
graphify query "How does the Tauri shell hand off authentication to Drive?"
graphify query "Which files control package release gating?"
graphify path "src-tauri/src/main.rs" ".gitlab-ci.yml"
graphify explain "live sync"
```

## Agent Behavior

Agents should prefer scoped Graphify queries when `graphify-out/graph.json`
exists. For broad architecture review, read `graphify-out/GRAPH_REPORT.md`.

If no graph exists, agents should continue using normal repository inspection and
may offer to build the graph.
