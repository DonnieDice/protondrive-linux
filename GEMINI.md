## Repository Operations

GitLab is canonical. GitHub is a forced downstream publication mirror. Never
make authoritative changes on GitHub; GitHub-only commits, branches, or tags
can be overwritten or removed by the next mirror run.

For cross-provider work, use the installed private skills in this order:
`project-management`, `gitlab`, then `github`. Discover provider configuration
at runtime and never embed private hosts, endpoints, IDs, accounts, or
credentials in this repository.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
