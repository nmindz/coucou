import Foundation

/// The agents Coucou MCP can be added to from Settings, and where each keeps its MCP servers.
enum MCPAgent: String, CaseIterable, Identifiable {
    case claudeCode, codex, gemini, antigravity, cursor, claudeDesktop, omp, opencode, amp, copilot, hermes

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claudeCode:    "Claude Code"
        case .codex:         "Codex"
        case .gemini:        "Gemini CLI"
        case .antigravity:   "Antigravity"
        case .cursor:        "Cursor"
        case .claudeDesktop: "Claude Desktop"
        case .omp:           "OMP"
        case .opencode:      "OpenCode"
        case .amp:           "Amp"
        case .copilot:       "Copilot CLI"
        case .hermes:        "Hermes"
        }
    }

    /// The file holding the agent's MCP servers, from the home folder.
    var configPath: String {
        switch self {
        case .claudeCode:    ".claude.json"   // read here, written by `claude mcp`
        case .codex:         ".codex/config.toml"
        case .gemini:        ".gemini/settings.json"
        case .antigravity:   ".gemini/antigravity/mcp_config.json"
        case .cursor:        ".cursor/mcp.json"
        case .claudeDesktop: "Library/Application Support/Claude/claude_desktop_config.json"
        case .omp:           ".omp/agent/mcp.json"
        case .opencode:      ".config/opencode/opencode.json"   // merged with opencode.jsonc
        case .amp:           ".config/amp/settings.json"
        case .copilot:       ".copilot/mcp-config.json"
        case .hermes:        ".hermes/config.yaml"
        }
    }

    /// The folder whose presence means the agent is set up on this Mac.
    var homeMarker: String {
        switch self {
        case .claudeCode:    ".claude"
        case .codex:         ".codex"
        case .gemini:        ".gemini"
        case .antigravity:   ".gemini/antigravity"
        case .cursor:        ".cursor"
        case .claudeDesktop: "Library/Application Support/Claude"
        case .omp:           ".omp/agent"
        case .opencode:      ".config/opencode"
        case .amp:           ".config/amp"
        case .copilot:       ".copilot"
        case .hermes:        ".hermes"
        }
    }

    fileprivate enum Format { case json(container: String, entry: (String) -> [String: Any]), toml, yaml }

    fileprivate var format: Format {
        switch self {
        case .claudeCode:
            .json(container: "mcpServers") { ["type": "stdio", "command": $0, "args": [String](), "env": [String: String]()] }
        case .gemini, .antigravity, .cursor, .claudeDesktop:
            .json(container: "mcpServers") { ["command": $0, "args": [String]()] }
        case .amp:
            .json(container: "amp.mcpServers") { ["command": $0, "args": [String]()] }
        case .omp:
            .json(container: "mcpServers") { ["type": "stdio", "command": $0] }
        case .copilot:
            .json(container: "mcpServers") { ["type": "local", "command": $0, "args": [String](), "tools": ["*"]] }
        case .opencode:
            .json(container: "mcp") { ["type": "local", "command": [$0], "enabled": true] }
        case .codex:  .toml
        case .hermes: .yaml
        }
    }
}

/// Coucou's entry in an agent's config, as pure edits of the file's text: Settings does the
/// reading, backup and writing. Every other server and setting is kept.
enum MCPConfigEdit {
    static let serverName = "coucou"

    enum Status: Equatable {
        case absent
        case installed        // points at this Mac's coucou-mcp
        case otherPath        // a `coucou` entry pointing elsewhere (an old copy, a hand edit)
    }

    enum Failure: Error, Equatable {
        case unreadable       // not the file format the agent uses: left untouched
        case unsupportedShape // valid, but laid out in a way Coucou does not edit (add it by hand)
    }

    // MARK: Status

    static func status(_ agent: MCPAgent, text: String?, script: String) -> Status {
        guard let text, !text.isEmpty else { return .absent }
        let command: String?
        switch agent.format {
        case .json(let container, _):
            guard let root = try? parseJSON(text),
                  let entry = (root[container] as? [String: Any])?[serverName] as? [String: Any] else { return .absent }
            command = (entry["command"] as? String) ?? (entry["command"] as? [String])?.first
        case .toml:
            guard let range = tomlTable(in: lines(text)) else { return .absent }
            command = lines(text)[range].lazy.compactMap { value(of: "command", in: $0, separator: "=") }.first
        case .yaml:
            guard let range = markerBlock(in: lines(text)) else {
                return yamlHasForeignEntry(lines(text)) ? .otherPath : .absent
            }
            command = lines(text)[range].lazy.compactMap { value(of: "command", in: $0, separator: ":") }.first
        }
        return command == script ? .installed : .otherPath
    }

    // MARK: Edits

    /// The config with Coucou's entry added, or replaced when one is there.
    static func install(_ agent: MCPAgent, text: String?, script: String) throws -> String {
        let current = text ?? ""
        switch agent.format {
        case .json(let container, let entry):
            var root = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [:] : try parseJSON(current)
            var servers = root[container] as? [String: Any] ?? [:]
            if root[container] != nil, root[container] as? [String: Any] == nil { throw Failure.unsupportedShape }
            servers[serverName] = entry(script)
            root[container] = servers
            return try serializeJSON(root)
        case .toml:
            var rows = lines(current)
            if let range = tomlTable(in: rows) { rows.removeSubrange(range) }
            return join(trimTrailingBlank(rows) + (rows.isEmpty ? [] : [""]) + tomlBlock(script))
        case .yaml:
            var rows = lines(current)
            if let range = markerBlock(in: rows) { rows.removeSubrange(range) }
            if yamlHasForeignEntry(rows) { throw Failure.unsupportedShape }
            if let key = rows.firstIndex(where: { $0.hasPrefix("mcp_servers:") }) {
                // An existing mcp_servers map: Coucou's entry goes first in it, at its indent.
                guard rows[key].trimmingCharacters(in: .whitespaces) == "mcp_servers:" else { throw Failure.unsupportedShape }
                let indent = rows[(key + 1)...].first { isYAMLContent($0) }.map(leadingSpaces).flatMap { $0 > 0 ? $0 : nil } ?? 2
                rows.insert(contentsOf: yamlEntry(script, indent: indent), at: key + 1)
                return join(rows)
            }
            let entry = yamlEntry(script, indent: 2)
            let block = [entry[0], "mcp_servers:"] + entry.dropFirst()
            return join(trimTrailingBlank(rows) + (rows.isEmpty ? [] : [""]) + block)
        }
    }

    /// The config without Coucou's entry; unchanged when it has none.
    static func remove(_ agent: MCPAgent, text: String) throws -> String {
        switch agent.format {
        case .json(let container, _):
            var root = try parseJSON(text)
            guard var servers = root[container] as? [String: Any], servers[serverName] != nil else { return text }
            servers[serverName] = nil
            root[container] = servers.isEmpty ? nil : servers   // an empty map Coucou created goes too
            return try serializeJSON(root)
        case .toml:
            var rows = lines(text)
            guard let range = tomlTable(in: rows) else { return text }
            rows.removeSubrange(range)
            return join(trimTrailingBlank(rows))
        case .yaml:
            var rows = lines(text)
            guard let range = markerBlock(in: rows) else {
                if yamlHasForeignEntry(rows) { throw Failure.unsupportedShape }
                return text
            }
            rows.removeSubrange(range)
            return join(trimTrailingBlank(rows))
        }
    }

    /// What Settings shows before writing: the entry as it will appear in the file.
    static func snippet(_ agent: MCPAgent, script: String) -> String {
        switch agent.format {
        case .json(let container, let entry):
            let data = try? JSONSerialization.data(withJSONObject: [container: [serverName: entry(script)]],
                                                   options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        case .toml: return tomlBlock(script).joined(separator: "\n")
        case .yaml: return (["mcp_servers:"] + yamlEntry(script, indent: 2).dropFirst().dropLast()).joined(separator: "\n")
        }
    }

    // MARK: JSON

    private static func parseJSON(_ text: String) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { throw Failure.unreadable }
        guard let dict = root as? [String: Any] else { throw Failure.unsupportedShape }
        return dict
    }

    private static func serializeJSON(_ root: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
    }

    // MARK: TOML (Codex)

    static let beginMarker = "# >>> coucou MCP >>>"
    static let endMarker = "# <<< coucou MCP <<<"

    private static func tomlBlock(_ script: String) -> [String] {
        [beginMarker, "[mcp_servers.\(serverName)]", "command = \(quoted(script))", "args = []", endMarker]
    }

    /// Coucou's table: its marker block, or a hand-made `[mcp_servers.coucou]` with its sub-tables.
    private static func tomlTable(in rows: [String]) -> Range<Int>? {
        if let block = markerBlock(in: rows) { return block }
        let header = "[mcp_servers.\(serverName)]"
        guard let start = rows.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else { return nil }
        var end = start + 1
        while end < rows.count {
            let row = rows[end].trimmingCharacters(in: .whitespaces)
            if row.hasPrefix("["), !row.hasPrefix("[mcp_servers.\(serverName).") { break }
            end += 1
        }
        return start..<end
    }

    // MARK: YAML (Hermes)

    /// `coucou:` and its fields between the markers, at `indent` (the map's own indent).
    private static func yamlEntry(_ script: String, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        return [pad + beginMarker, pad + "\(serverName):", pad + pad + "command: \(quoted(script))",
                pad + pad + "args: []", pad + endMarker]
    }

    /// A `coucou:` server outside Coucou's markers: written by hand, so not Coucou's to change.
    private static func yamlHasForeignEntry(_ rows: [String]) -> Bool {
        guard let key = rows.firstIndex(where: { $0.hasPrefix("mcp_servers:") }) else { return false }
        for row in rows[(key + 1)...] {
            guard row.isEmpty || row.hasPrefix(" ") || row.hasPrefix("#") else { break }   // next top-level key
            if row.trimmingCharacters(in: .whitespaces) == "\(serverName):" { return true }
        }
        return false
    }

    private static func isYAMLContent(_ row: String) -> Bool {
        let t = row.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && !t.hasPrefix("#")
    }

    // MARK: Text helpers

    /// The first marker block (begin through end), at any indent.
    private static func markerBlock(in rows: [String]) -> Range<Int>? {
        guard let start = rows.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == beginMarker }),
              let end = rows[start...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == endMarker })
        else { return nil }
        return start..<(end + 1)
    }

    /// `key = "value"` / `key: "value"` → value.
    private static func value(of key: String, in row: String, separator: Character) -> String? {
        let t = row.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix(key), let sep = t.firstIndex(of: separator),
              t[..<sep].trimmingCharacters(in: .whitespaces) == key else { return nil }
        let raw = t[t.index(after: sep)...].trimmingCharacters(in: .whitespaces)
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
        else { return raw }
        return decoded
    }

    /// A double-quoted string, valid in TOML and YAML.
    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func lines(_ text: String) -> [String] {
        var rows = text.components(separatedBy: "\n")
        if rows.last == "" { rows.removeLast() }
        return rows
    }

    private static func join(_ rows: [String]) -> String { rows.isEmpty ? "" : rows.joined(separator: "\n") + "\n" }

    private static func trimTrailingBlank(_ rows: [String]) -> [String] {
        var rows = rows
        while rows.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { rows.removeLast() }
        return rows
    }

    private static func leadingSpaces(_ row: String) -> Int { row.prefix { $0 == " " }.count }
}
