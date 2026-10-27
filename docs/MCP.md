# Coucou MCP (macOS, GitHub build)

Coucou ships an [MCP](https://modelcontextprotocol.io) server so agents (Claude Code, Codex, OMP, Cursor…) can read what the Notetaker recorded: the list of calls, their summaries, to-dos and transcripts. It is read-only and answers from the **running** Coucou.

## Turning it on

Settings → Agents → **Coucou MCP** → **Let agents read your recordings** (off by default).

**Add to your agents** lists the agents set up on this Mac, each with its status (*Added*, *Not added*, *Points to another copy*) and **Add**, **Update** or **Remove**. A button first shows what will change; **Confirm and write** then makes a dated backup of the file (`<file>.bak-<yyyyMMdd-HHmmss>`) and writes only Coucou's entry, keeping every other server and setting. Symlinked configs stay links; file permissions are kept.

| Agent | Where | Entry |
|---|---|---|
| Claude Code | `claude mcp add --scope user coucou` (its `~/.claude.json` is rewritten by every session, so Coucou runs its command) | stdio |
| Codex | `~/.codex/config.toml` | `[mcp_servers.coucou]` between `# >>> coucou MCP >>>` markers |
| Gemini CLI | `~/.gemini/settings.json` | `mcpServers.coucou` |
| Antigravity | `~/.gemini/antigravity/mcp_config.json` | `mcpServers.coucou` |
| Cursor | `~/.cursor/mcp.json` | `mcpServers.coucou` |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | `mcpServers.coucou` (restart Claude Desktop) |
| OMP | `~/.omp/agent/mcp.json` | `mcpServers.coucou`, `type: stdio` |
| OpenCode | `~/.config/opencode/opencode.json` (merged with `opencode.jsonc`) | `mcp.coucou`, `type: local` |
| Amp | `~/.config/amp/settings.json` | `amp.mcpServers.coucou` |
| Copilot CLI | `~/.copilot/mcp-config.json` | `mcpServers.coucou`, `type: local`, every tool |
| Hermes | `~/.hermes/config.yaml` | `mcp_servers.coucou` between markers |

A file Coucou cannot read is left untouched, and so is an entry laid out in a way it does not edit (a hand-written `coucou:` in Hermes' YAML, an inline `mcp_servers: {}`): Settings says so and the entry is added by hand. JSON configs are rewritten with sorted keys. Other agents: **Copy JSON** gives the `mcpServers` entry with the full path (JSON configs do not expand `~` or `$HOME`).

## Tools

| Tool | Arguments | Returns |
|---|---|---|
| `list_recordings` | `query` (searches titles, summaries, to-dos and transcripts, any case), `since` (`2026-10-27` or ISO 8601), `limit` (1–100, default 20) | Newest first: `id`, `title`, `start`, `end`, `duration_minutes`, `app`, `status`, `speakers`, `summary_preview`, `todos_open`, `todos_done`, `lines` |
| `get_summary` | `id` | The header above plus `summary`, `key_points`, `todos` (`text`, `owner`, `due`, `done`) |
| `get_transcript` | `id` | The header plus `lines`: `at` (`mm:ss`), `start`, `end` (seconds), `speaker` (name), `text`, and `heard` — the original transcription — on lines a correction changed |
| `get_todos` | `id` (optional), `include_done` (default false) | To-dos with `recording_id`, `recording_title`, `recording_start` |

`id` is the full id from `list_recordings`, or a unique prefix of 6 characters or more. Results are JSON in a text block.

## How it works

`coucou-mcp` is a small stdio server (Python 3, `/usr/bin/python3`, like `nb-hook`), written at launch to `~/Library/Application Support/NotchBuddy/`. Each tool call goes to the running Coucou as one line on its socket (`nb.sock`, owner-only, same-user connections only): `{"coucou_kind": "query", "tool", "arguments"}`. The app answers from the notes in memory (`CoucouQuery.swift`) and closes the connection.

- **Off:** the app refuses every query, and the agent is told to turn it on.
- **Coucou closed:** the agent is told to open Coucou; nothing is read from disk behind its back.
- **Logs:** `nb.log` records each tool name, never what it returned.
- **Privacy:** what an agent reads goes to its model provider. That is why it is off by default.

Tests: `scripts/test-coucou-query.sh` (the answers), `scripts/test-coucou-mcp.sh` (the stdio server, end to end, over a fake Coucou), `scripts/test-mcp-config.sh` (adding and removing the entry in each agent's format, and what the Settings section shows).
