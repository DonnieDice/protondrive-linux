# Claude Guidance

Follow `AGENTS.md`. Additional Claude-specific guidance:

- Keep debugging notes cumulative under `docs/debugging/`.
- When changing local build scripts, update matching GitHub Actions workflow steps in the same change.
- Do not suggest recloning `WebClients/` for local development; CI is responsible for fresh clones.
- Keep responses concise and focused on correctness, parity, and non-regression.
