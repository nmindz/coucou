# Coucou MCP (macOS, GitHub build)

Coucou ships an [MCP](https://modelcontextprotocol.io) server so agents (Claude Code, Codex, OMP, Cursor…) can read what the Notetaker recorded: the list of calls, their summaries, to-dos and transcripts. It is read-only and answers from the **running** Coucou.

## Turning it on

Settings → Agents → **Coucou MCP** → **Let agents read your recordings** (off by default). The same section copies the setup for each agent:

| Agent | Setup |
|---|---|
| Claude Code | `claude mcp add --scope user coucou -- "$HOME/Library/Application Support/NotchBuddy/coucou-mcp"` |
| Codex | `codex mcp add coucou -- "$HOME/Library/Application Support/NotchBuddy/coucou-mcp"` |
| OMP | add `{"mcpServers": {"coucou": {"command": "<full path>"}}}` to `~/.omp/agent/mcp.json` |
| Others | the same JSON in their MCP settings |

JSON configs need the full path (`/Users/<you>/Library/…`): they do not expand `~` or `$HOME`. Settings copies it ready to paste.

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

Tests: `scripts/test-coucou-query.sh` (the answers), `scripts/test-coucou-mcp.sh` (the stdio server, end to end, over a fake Coucou).
