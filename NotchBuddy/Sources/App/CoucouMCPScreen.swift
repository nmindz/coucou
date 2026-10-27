import Foundation

/// Settings → Agents → Coucou MCP, as drawn: the `coucouMCP` part of the `settings` screen.
struct CoucouMCPScreen: Codable, Equatable {
    static let key = "coucouMCP"

    struct Agent: Codable, Equatable {
        let id: String
        let name: String
        let path: String
        let status: String          // installed | absent | otherPath
        let statusText: String
        let actions: [String]       // add | update | remove, in button order
    }

    /// What will change before anything is written (Add / Update / Remove pressed).
    struct Preview: Codable, Equatable {
        let agent: String
        let install: Bool
        let heading: String
        let code: String?
    }

    let enabled: Bool
    let offHint: String?
    let agents: [Agent]             // the agents set up on this Mac
    let preview: Preview?
    let busy: Bool
    let scriptPath: String

    static func build(enabled: Bool, statuses: [(MCPAgent, MCPConfigEdit.Status)],
                      pending: (agent: MCPAgent, install: Bool)?, busy: Bool, script: String,
                      claudeCommand: String) -> CoucouMCPScreen {
        let agents = statuses.map { agent, status in
            Agent(id: agent.rawValue, name: agent.name, path: "~/" + agent.configPath,
                  status: statusID(status), statusText: statusText(status), actions: actions(status))
        }
        let preview = pending.map { pending -> Preview in
            let path = "~/" + pending.agent.configPath
            if pending.agent == .claudeCode {
                return Preview(agent: pending.agent.rawValue, install: pending.install,
                               heading: String(localized: "mcp.preview-run"),
                               code: pending.install ? claudeCommand : "claude mcp remove --scope user \(MCPConfigEdit.serverName)")
            }
            return pending.install
                ? Preview(agent: pending.agent.rawValue, install: true,
                          heading: String(format: String(localized: "mcp.preview-add %@"), path),
                          code: MCPConfigEdit.snippet(pending.agent, script: script))
                : Preview(agent: pending.agent.rawValue, install: false,
                          heading: String(format: String(localized: "mcp.preview-remove %@"), path), code: nil)
        }
        return CoucouMCPScreen(enabled: enabled, offHint: enabled ? nil : String(localized: "mcp.off-hint"),
                               agents: agents, preview: preview, busy: busy, scriptPath: script)
    }

    private static func statusID(_ status: MCPConfigEdit.Status) -> String {
        switch status {
        case .installed: "installed"
        case .absent:    "absent"
        case .otherPath: "otherPath"
        }
    }

    private static func statusText(_ status: MCPConfigEdit.Status) -> String {
        switch status {
        case .installed: String(localized: "mcp.status.installed")
        case .absent:    String(localized: "mcp.status.absent")
        case .otherPath: String(localized: "mcp.status.other")
        }
    }

    private static func actions(_ status: MCPConfigEdit.Status) -> [String] {
        switch status {
        case .installed: ["remove"]
        case .absent:    ["add"]
        case .otherPath: ["update", "remove"]
        }
    }
}
