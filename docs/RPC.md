# Inspecting screens (debug RPC, macOS)

Every screen Coucou publishes is built from app state and stored in `ScreenStore`. The SwiftUI view draws the stored value, and the debug RPC returns that same value as JSON, so the RPC shows exactly what is on screen: no screenshots, no clicks, no window focus. UI-only state that changes what is drawn (the window's page, the status line under Settings, an open preview) lives in the screen's `ui` and is mirrored into its view.

## Enabling

`coucou-rpc.sock` in Coucou's support folder (`~/Library/Application Support/NotchBuddy/`), mode `0600`, connections from this Mac's user only; a stale socket is replaced at start and `nb.log` records `[RPC] listening on …`. Always on in Debug builds (what `make install` builds); release builds start it only when launched with `COUCOU_RPC=1`. GitHub build only.

To install without taking focus or opening the window: `COUCOU_BACKGROUND=1 make install`.

## Protocol

JSON-RPC 2.0, one JSON document per line in each direction, batches allowed, any number of requests per connection. Errors: `-32700` parse, `-32600` invalid request, `-32601` unknown method, `-32602` invalid params (`data.detail` says which), `-32000` application error with `data: {kind, detail}`, `-32001` `screen.wait` timeout.

| Method | Params | Effect |
|---|---|---|
| `rpc.discover` | | Methods and screen names |
| `app.state` | | pid, version, build, socket, screen summaries |
| `screen.list` | | Revision and publish state per screen |
| `screen.get` | `{screen}` | Stored entry `{screen, revision, updated_at, view, ui}`; built first if never published |
| `screen.refresh` | `{screen}` | Rebuild from app state, then return the entry |
| `screen.wait` | `{screen, minRevision, timeoutMs?}` | Block until `revision >= minRevision` (default 5000 ms, max 120000) |
| `settings.setPage` | `{page}` | Page of the Coucou window (`dictation`, `notes`, `agents`, `chat`…); never opens or focuses it |
| `mcp.setEnabled` | `{enabled}` | The Coucou MCP switch |
| `mcp.preview` | `{agent, action: add\|remove}` | What Add / Update / Remove would write; nothing is written |
| `mcp.cancel` | | Close the preview |
| `mcp.confirm` | | Write the previewed change (dated backup first); `{message, entry}` |
| `plan.setCard` | `{open, codex?}` | Open or close the plan card in the notch, as its pill does |

Actions run the same functions as the buttons and return the screen they changed.

## Screens

| Screen | Parts |
|---|---|
| `settings` | `page` (page, title, settings section, window visible, status line), `coucouMCP` (switch, agents with status and buttons, preview, busy) |
| `plan` | `card` (title, subtitle, dot color, gauge rows with %, fill, color and reset text, Codex row), `pill` (shown, kind, label, color, open) |

A `revision` grows only when a part or the UI state changes. Fields with no value are left out of the JSON (an absent `preview` means none is showing). Views not listed here are not published yet.

## Command line

```bash
scripts/coucou-rpc rpc.discover
scripts/coucou-rpc screen.get '{"screen":"plan"}'
scripts/coucou-rpc mcp.preview '{"agent":"cursor","action":"add"}'
scripts/coucou-rpc screen.wait '{"screen":"settings","minRevision":12,"timeoutMs":3000}'
```

`COUCOU_RPC_SOCK` points it at another socket. Without the script: `printf '{"jsonrpc":"2.0","id":1,"method":"screen.list"}\n' | nc -U ~/Library/Application\ Support/NotchBuddy/coucou-rpc.sock`.

## Adding a screen

1. A `Codable, Equatable` model of what the view draws, with a pure `build(...)` from state (unit-tested).
2. A builder in `CoucouScreens` that publishes it (`ScreenStore.publish(screen, key, model)`), registered for its screen and scheduled by the changes it depends on.
3. The view reads `ScreenStore.shared.part(screen, key, as:)` and draws only that; its buttons call the same action functions the RPC dispatches.

Code: `App/ScreenStore.swift`, `App/RPCProtocol.swift`, `App/CoucouRPC.swift`. Tests: `scripts/test-screen-rpc.sh`.
