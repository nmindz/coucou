import Foundation

// Coucou MCP added to and removed from each agent's config (App/CoucouMCPInstall.swift).

@main
enum MCPConfigEditTests {

    static var failures = 0

    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func json(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    static let script = "/Users/me/Library/Application Support/NotchBuddy/coucou-mcp"

    static func main() {
        print("JSON (Cursor, Gemini, Claude Desktop, OMP, Copilot, Amp, OpenCode)")
        let cursor = #"{"mcpServers":{"memory":{"command":"npx","args":["-y","m"]}},"other":1}"#
        let added = try! MCPConfigEdit.install(.cursor, text: cursor, script: script)
        let root = json(added)
        let servers = root["mcpServers"] as? [String: Any] ?? [:]
        check("other servers and keys kept", servers["memory"] != nil && root["other"] as? Int == 1)
        check("entry points at the script", (servers["coucou"] as? [String: Any])?["command"] as? String == script)
        check("slashes and spaces written plainly", added.contains(script))
        check("status: installed", MCPConfigEdit.status(.cursor, text: added, script: script) == .installed)
        check("status: other copy", MCPConfigEdit.status(.cursor, text: added, script: "/old/coucou-mcp") == .otherPath)
        check("status: absent", MCPConfigEdit.status(.cursor, text: cursor, script: script) == .absent)
        check("installing twice is the same file",
              (try? MCPConfigEdit.install(.cursor, text: added, script: script)) == added)
        let removed = try! MCPConfigEdit.remove(.cursor, text: added)
        check("remove leaves the rest", (json(removed)["mcpServers"] as? [String: Any])?.keys.sorted() == ["memory"])
        check("remove when absent: unchanged", (try? MCPConfigEdit.remove(.cursor, text: cursor)) == cursor)
        check("missing file → new config", json(try! MCPConfigEdit.install(.gemini, text: nil, script: script))["mcpServers"] != nil)
        check("broken JSON is left alone", throwsFailure(.unreadable) { try MCPConfigEdit.install(.cursor, text: "{nope", script: script) })
        let ocAdded = try! MCPConfigEdit.install(.opencode, text: #"{"plugin":["a"]}"#, script: script)
        check("OpenCode: remove drops the map Coucou created", json(try! MCPConfigEdit.remove(.opencode, text: ocAdded)).keys.sorted() == ["plugin"])
        check("mcpServers not a map → by hand",
              throwsFailure(.unsupportedShape) { try MCPConfigEdit.install(.cursor, text: #"{"mcpServers":[]}"#, script: script) })

        let omp = json(try! MCPConfigEdit.install(.omp, text: #"{"$schema":"x","disabledServers":[]}"#, script: script))
        check("OMP: stdio entry, schema kept", ((omp["mcpServers"] as? [String: Any])?["coucou"] as? [String: Any])?["type"] as? String == "stdio"
              && omp["$schema"] as? String == "x")
        let copilot = (json(try! MCPConfigEdit.install(.copilot, text: "{}", script: script))["mcpServers"] as? [String: Any])?["coucou"] as? [String: Any]
        check("Copilot: local, every tool", copilot?["type"] as? String == "local" && copilot?["tools"] as? [String] == ["*"])
        let opencode = json(try! MCPConfigEdit.install(.opencode, text: #"{"plugin":["a"]}"#, script: script))
        let oc = (opencode["mcp"] as? [String: Any])?["coucou"] as? [String: Any]
        check("OpenCode: command as a list, enabled", oc?["command"] as? [String] == [script] && oc?["enabled"] as? Bool == true)
        check("OpenCode: status reads the list", MCPConfigEdit.status(.opencode, text: try! MCPConfigEdit.install(.opencode, text: "{}", script: script), script: script) == .installed)
        let amp = json(try! MCPConfigEdit.install(.amp, text: "{}", script: script))
        check("Amp: the dotted amp.mcpServers key", amp["amp.mcpServers"] != nil)
        check("Claude Code: status from ~/.claude.json",
              MCPConfigEdit.status(.claudeCode, text: #"{"mcpServers":{"coucou":{"type":"stdio","command":"\#(script)"}}}"#, script: script) == .installed)

        print("TOML (Codex)")
        let codex = """
        model = "gpt-5"

        [mcp_servers.codegraph]
        command = "codegraph"
        args = ["serve", "--mcp"]

        [profiles.fast]
        model = "mini"
        """
        let codexAdded = try! MCPConfigEdit.install(.codex, text: codex, script: script)
        check("block appended, rest kept", codexAdded.hasPrefix(codex) && codexAdded.contains("[mcp_servers.coucou]"))
        check("path quoted", codexAdded.contains("command = \"\(script)\""))
        check("status: installed", MCPConfigEdit.status(.codex, text: codexAdded, script: script) == .installed)
        check("installing twice is the same file", (try? MCPConfigEdit.install(.codex, text: codexAdded, script: script)) == codexAdded)
        check("remove → original", (try? MCPConfigEdit.remove(.codex, text: codexAdded)) == codex + "\n")
        let handMade = codex + "\n\n[mcp_servers.coucou]\ncommand = \"/old/coucou-mcp\"\n\n[mcp_servers.coucou.env]\nA = \"1\"\n\n[other]\nx = 1\n"
        check("hand-made table: other copy", MCPConfigEdit.status(.codex, text: handMade, script: script) == .otherPath)
        let replaced = try! MCPConfigEdit.install(.codex, text: handMade, script: script)
        check("hand-made table and sub-table replaced, next table kept",
              !replaced.contains("/old/") && !replaced.contains("coucou.env") && replaced.contains("[other]")
              && replaced.components(separatedBy: "[mcp_servers.coucou]").count == 2)

        print("YAML (Hermes)")
        let hermes = "model: x\nagent:\n  max_turns: 3\n"
        let hermesAdded = try! MCPConfigEdit.install(.hermes, text: hermes, script: script)
        check("new mcp_servers block at the end", hermesAdded.hasPrefix(hermes) && hermesAdded.contains("mcp_servers:\n  coucou:\n    command: \"\(script)\""))
        check("status: installed", MCPConfigEdit.status(.hermes, text: hermesAdded, script: script) == .installed)
        check("remove → original", (try? MCPConfigEdit.remove(.hermes, text: hermesAdded)) == hermes)
        let withServers = "mcp_servers:\n    github:\n        command: \"npx\"\nother: 1\n"
        let merged = try! MCPConfigEdit.install(.hermes, text: withServers, script: script)
        check("existing map: entry at its 4-space indent",
              merged.contains("mcp_servers:\n    # >>> coucou MCP >>>\n    coucou:\n        command:") && merged.contains("    github:"))
        check("existing map: one mcp_servers key", merged.components(separatedBy: "mcp_servers:").count == 2)
        check("existing map: remove → original", (try? MCPConfigEdit.remove(.hermes, text: merged)) == withServers)
        let foreign = "mcp_servers:\n  coucou:\n    command: \"/old\"\n"
        check("hand-written coucou: other copy", MCPConfigEdit.status(.hermes, text: foreign, script: script) == .otherPath)
        check("hand-written coucou: not edited", throwsFailure(.unsupportedShape) { try MCPConfigEdit.install(.hermes, text: foreign, script: script) })
        check("inline mcp_servers: not edited",
              throwsFailure(.unsupportedShape) { try MCPConfigEdit.install(.hermes, text: "mcp_servers: {}\n", script: script) })

        print("snippets")
        check("JSON snippet names the container", MCPConfigEdit.snippet(.opencode, script: script).contains("\"mcp\""))
        check("TOML snippet is the block", MCPConfigEdit.snippet(.codex, script: script).contains("[mcp_servers.coucou]"))
        check("YAML snippet has no markers", !MCPConfigEdit.snippet(.hermes, script: script).contains(">>>"))

        print("Settings screen model (what the section draws and the RPC returns)")
        let statuses: [(MCPAgent, MCPConfigEdit.Status)] = [(.claudeCode, .installed), (.cursor, .absent), (.codex, .otherPath)]
        let screen = CoucouMCPScreen.build(enabled: false, statuses: statuses, pending: nil, busy: false,
                                           script: script, claudeCommand: "claude mcp add x")
        check("one row per agent, in order", screen.agents.map(\.id) == ["claudeCode", "cursor", "codex"])
        check("buttons follow the status",
              screen.agents.map(\.actions) == [["remove"], ["add"], ["update", "remove"]])
        check("paths from home", screen.agents[1].path == "~/.cursor/mcp.json")
        check("off → the hint shows", screen.offHint != nil && screen.preview == nil)
        let addCursor = CoucouMCPScreen.build(enabled: true, statuses: statuses, pending: (.cursor, true), busy: false,
                                              script: script, claudeCommand: "claude mcp add x")
        check("on → no hint", addCursor.offHint == nil)
        check("Add previews the entry it writes", addCursor.preview?.code == MCPConfigEdit.snippet(.cursor, script: script))
        let claude = CoucouMCPScreen.build(enabled: true, statuses: statuses, pending: (.claudeCode, false), busy: true,
                                           script: script, claudeCommand: "claude mcp add x")
        check("Claude Code previews the command it runs", claude.preview?.code == "claude mcp remove --scope user coucou")
        let removeCursor = CoucouMCPScreen.build(enabled: true, statuses: statuses, pending: (.cursor, false), busy: false,
                                                 script: script, claudeCommand: "claude mcp add x")
        check("Remove shows no code", removeCursor.preview?.code == nil && removeCursor.preview?.install == false)
        check("busy is drawn", claude.busy)

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("All MCP config tests passed.")
    }

    static func throwsFailure(_ expected: MCPConfigEdit.Failure, _ body: () throws -> String) -> Bool {
        do { _ = try body(); return false } catch let f as MCPConfigEdit.Failure { return f == expected } catch { return false }
    }
}
