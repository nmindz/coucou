#if !APPSTORE
import AppKit
import Combine

// MARK: - Screens

/// The Coucou window's page, as drawn: the `page` part of the `settings` screen.
struct SettingsPageScreen: Codable, Equatable {
    static let key = "page"
    let page: String          // HubPage raw value
    let title: String
    let settingsSection: String?
    let windowVisible: Bool
    let status: String        // the status line under Settings pages
}

/// Builds every published screen from app state and keeps it current. Views draw what is
/// published here; the debug RPC returns the same values.
@MainActor
enum CoucouScreens {
    private static var subscriptions: [AnyCancellable] = []
    private static var ticker: Timer?

    static func start() {
        let store = ScreenStore.shared
        store.register(.settings) { publishSettingsPage(); CoucouMCPActions.publish(rescan: true) }
        store.register(.plan, build: publishPlan)

        let hub = FlowHubController.shared
        subscriptions = [
            AppState.shared.objectWillChange.sink { _ in MainActor.assumeIsolated { store.schedule(.plan) } },
            hub.router.$page.dropFirst().sink { _ in
                MainActor.assumeIsolated {
                    store.mergeUI(.settings, ["status": ""])   // a new page starts without the last page's status
                    store.schedule(.settings)
                }
            },
            hub.windowState.$visible.dropFirst().sink { _ in MainActor.assumeIsolated { publishSettingsPage() } },
            // Settings written anywhere (the window, `defaults`, another part of Coucou), on any thread.
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: DispatchQueue.main)
                .sink { _ in MainActor.assumeIsolated { publishSettingsPage(); CoucouMCPActions.publish(); store.schedule(.plan) } },
            // Back to Coucou: agent configs may have changed meanwhile.
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
                .receive(on: DispatchQueue.main)
                .sink { _ in MainActor.assumeIsolated { CoucouMCPActions.publish(rescan: true) } },
            store.$entries.sink { entries in
                // The status line is UI state: mirror it into the page part when it changes.
                let status = entries[.settings]?.ui["status"] as? String ?? ""
                MainActor.assumeIsolated {
                    if store.part(.settings, SettingsPageScreen.key, as: SettingsPageScreen.self)?.status != status {
                        store.schedule(.settings)
                    }
                }
            },
        ]
        store.refresh(.settings)
        store.refresh(.plan)
    }

    /// Ages and reset countdowns move with time, but only an open card shows them: the timer
    /// exists only then (0 % CPU when the island is hidden).
    private static func tick(_ cardOpen: Bool) {
        if !cardOpen {
            ticker?.invalidate()
            ticker = nil
        } else if ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                MainActor.assumeIsolated { ScreenStore.shared.schedule(.plan) }
            }
        }
    }

    static func publishSettingsPage() {
        let hub = FlowHubController.shared
        let page = hub.router.page
        ScreenStore.shared.publish(.settings, SettingsPageScreen.key, SettingsPageScreen(
            page: page.rawValue, title: page.title, settingsSection: page.settingsSection,
            windowVisible: hub.isWindowVisible && hub.windowState.visible,
            status: ScreenStore.shared.ui(.settings, "status") as? String ?? ""))
    }

    static func publishPlan() {
        let state = AppState.shared
        let store = ScreenStore.shared
        let now = Date()
        let codexWindow = dominantCodexWindow(state.codexPlanUsage, now: now)
        let card = PlanCardScreen.build(
            open: state.showingPlanDetail && !state.planDetailIsCodex,
            usage: state.claudePlanUsage,
            sourceNote: state.planFromClaudeLB ? state.claudeLBSourceNote : nil,
            codexRow: state.claudePlanAvailable && state.showCodexPlanInNotch,
            codexWindow: codexWindow,
            codexWeekly: codexWindow != nil && codexWindow == state.codexPlanUsage?.sevenDay,
            now: now)
        store.publish(.plan, PlanCardScreen.key, card)
        tick(state.showingPlanDetail)

        // Claude and Codex both on: only Claude in the header; Codex is a row in its card.
        let claude = state.view == .overview && state.claudePlanAvailable
        let codex = !claude && state.view == .overview && state.showCodexPlanInNotch
        let usage = state.demoPlanUsageOverride ?? state.claudePlanUsage
        store.publish(.plan, PlanPillScreen.key, PlanPillScreen(
            shown: claude || codex,
            kind: codex ? "codex" : "claude",
            label: codex ? CodexPlanGauge.pillLabel(state.codexPlanUsage) : ClaudePlanGauge.pillLabel(usage, now: now),
            color: codex ? CodexPlanGauge.color(state.codexPlanUsage)
                         : ClaudePlanGauge.color(for: usage.flatMap { ClaudePlanGauge.dominantPct($0, now: now) }),
            open: state.showingPlanDetail && state.planDetailIsCodex == codex))
    }

    /// The Codex window closest to its limit.
    private static func dominantCodexWindow(_ usage: CodexPlanUsage?, now: Date) -> PlanWindow? {
        guard let usage else { return nil }
        switch (usage.fiveHour, usage.sevenDay) {
        case (nil, nil): return nil
        case (let f?, nil): return f
        case (nil, let w?): return w
        case (let f?, let w?):
            return ClaudePlanGauge.effectivePct(f, now: now) >= ClaudePlanGauge.effectivePct(w, now: now) ? f : w
        }
    }
}

// MARK: - Methods

/// Coucou's debug JSON-RPC (docs/RPC.md): reads exactly what the windows draw from the screen
/// store, and runs the same actions as their buttons.
@MainActor
enum CoucouRPC {
    nonisolated static let socketName = "coucou-rpc.sock"
    nonisolated static var socketPath: String { HookServer.supportDir.appendingPathComponent(socketName).path }

    /// Always in Debug builds; in release only when launched with COUCOU_RPC=1.
    nonisolated static var enabled: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.environment["COUCOU_RPC"] == "1"
        #endif
    }

    /// `(method, params, description)`; `rpc.discover` returns this table.
    static let methods: [(String, String, String)] = [
        ("rpc.discover", "", "Every method with its params, and the screen names."),
        ("app.state", "", "pid, version, build, socket and screens."),
        ("screen.list", "", "Revision and publish state of every screen."),
        ("screen.get", "{screen}", "Stored entry {screen, revision, updated_at, view, ui}; built first when never published."),
        ("screen.refresh", "{screen}", "Rebuild the screen from app state, then return the entry."),
        ("screen.wait", "{screen, minRevision, timeoutMs?}", "Block until revision >= minRevision; error -32001 on timeout (default 5000 ms, max 120000)."),
        ("settings.setPage", "{page}", "Show a page of the Coucou window (dictation, notes, agents, chat…) without opening or focusing it."),
        ("mcp.setEnabled", "{enabled}", "The Coucou MCP switch."),
        ("mcp.preview", "{agent, action: add|remove}", "Add / Update / Remove: show what will change, write nothing."),
        ("mcp.cancel", "", "Close the preview."),
        ("mcp.confirm", "", "Write the previewed change to the agent's config (dated backup first)."),
        ("plan.setCard", "{open, codex?}", "Open or close the plan card in the notch, as clicking its pill does."),
    ]

    static func dispatch(_ method: String, _ params: [String: Any]) async throws -> Any {
        let store = ScreenStore.shared
        switch method {
        case "rpc.discover":
            return ["methods": methods.map { ["method": $0.0, "params": $0.1, "description": $0.2] },
                    "screens": Screen.allCases.map(\.rawValue)]
        case "app.state":
            #if DEBUG
            let build = "debug"
            #else
            let build = "release"
            #endif
            return ["pid": Int(getpid()), "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "",
                    "gitHash": Bundle.main.infoDictionary?["CoucouGitHash"] ?? "", "build": build,
                    "socket": socketPath, "screens": store.summaries()]
        case "screen.list":
            return store.summaries()
        case "screen.get":
            let screen = try screenParam(params)
            if store.revision(screen) == 0 { store.refresh(screen) }
            return store.entryJSON(screen)
        case "screen.refresh":
            let screen = try screenParam(params)
            store.refresh(screen)
            return store.entryJSON(screen)
        case "screen.wait":
            let screen = try screenParam(params)
            guard let minRevision = try RPCProtocol.uint(params, "minRevision") else {
                throw RPCFailure.invalidParams("minRevision is required")
            }
            let ms = min(try RPCProtocol.uint(params, "timeoutMs") ?? 5_000, 120_000)
            guard await store.wait(screen, minRevision: minRevision, timeout: .milliseconds(Int(ms))) else {
                throw RPCFailure.timeout(revision: store.revision(screen))
            }
            return store.entryJSON(screen)
        case "settings.setPage":
            let raw = try RPCProtocol.string(params, "page")
            guard let page = HubPage(rawValue: raw) else {
                throw RPCFailure.invalidParams("page must be one of: " + HubPage.allCases.map(\.rawValue).joined(separator: ", "))
            }
            FlowHubController.shared.router.page = page
            store.refresh(.settings)
            return store.entryJSON(.settings)
        case "mcp.setEnabled":
            CoucouMCPActions.setEnabled(try RPCProtocol.bool(params, "enabled"))
            return store.entryJSON(.settings)
        case "mcp.preview":
            let raw = try RPCProtocol.string(params, "agent")
            guard let agent = MCPAgent(rawValue: raw) else {
                throw RPCFailure.invalidParams("agent must be one of: " + MCPAgent.allCases.map(\.rawValue).joined(separator: ", "))
            }
            let action = try RPCProtocol.string(params, "action")
            guard ["add", "remove"].contains(action) else { throw RPCFailure.invalidParams("action must be add or remove") }
            try CoucouMCPActions.preview(agent, install: action == "add")
            return store.entryJSON(.settings)
        case "mcp.cancel":
            CoucouMCPActions.cancel()
            return store.entryJSON(.settings)
        case "mcp.confirm":
            let message = try await CoucouMCPActions.confirm()
            return ["message": message, "entry": store.entryJSON(.settings)]
        case "plan.setCard":
            let state = AppState.shared
            let open = try RPCProtocol.bool(params, "open")
            let codex = params["codex"] == nil ? false : try RPCProtocol.bool(params, "codex")
            state.planDetailIsCodex = codex
            state.showingPlanDetail = open
            if open { if codex { state.refreshCodexPlanUsage() } else { state.refreshClaudeLBUsage() } }
            store.refresh(.plan)
            return store.entryJSON(.plan)
        default:
            throw RPCFailure.methodNotFound(method)
        }
    }

    private static func screenParam(_ params: [String: Any]) throws -> Screen {
        let raw = try RPCProtocol.string(params, "screen")
        guard let screen = Screen(rawValue: raw) else {
            throw RPCFailure.invalidParams("screen must be one of: " + Screen.allCases.map(\.rawValue).joined(separator: ", "))
        }
        return screen
    }
}

// MARK: - Socket

/// `coucou-rpc.sock` in the support folder: mode 0600, this Mac's user only, one JSON-RPC
/// document per line in each direction, any number of requests per connection.
final class CoucouRPCServer: @unchecked Sendable {
    static let shared = CoucouRPCServer()
    private static let maxLine = 1_048_576
    private static let maxConnections = 16
    private let lock = NSLock()
    private var connections = 0

    func start() {
        guard CoucouRPC.enabled else { return }
        Thread.detachNewThread { self.serve() }
    }

    private func serve() {
        let path = CoucouRPC.socketPath
        let maxSunPath = MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size - 1
        guard path.utf8.count <= maxSunPath else { return appendAppLog("nb.log", "[RPC] socket path too long: \(path)") }
        unlink(path)   // a stale socket from an earlier run
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, byte) in path.utf8.enumerated() where i < raw.count - 1 { raw[i] = byte }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            close(fd)
            return appendAppLog("nb.log", "[RPC] could not listen on \(path)")
        }
        appendAppLog("nb.log", "[RPC] listening on \(path)")
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            var euid: uid_t = 0
            var egid: gid_t = 0
            lock.lock()
            let admitted = connections < Self.maxConnections
            if admitted { connections += 1 }
            lock.unlock()
            guard admitted, getpeereid(client, &euid, &egid) == 0, euid == getuid() else {
                if admitted { lock.lock(); connections -= 1; lock.unlock() }
                close(client)
                continue
            }
            Thread.detachNewThread { self.handle(client) }
        }
    }

    private func handle(_ fd: Int32) {
        defer {
            close(fd)
            lock.lock(); connections -= 1; lock.unlock()
        }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(fd, &chunk, chunk.count, 0)
            guard n > 0 else { return }
            buffer.append(contentsOf: chunk[0..<n])
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                guard !line.allSatisfy({ $0 == 32 || $0 == 13 || $0 == 9 }) else { continue }
                if let reply = answer(line) { send(fd, reply + Data([UInt8(ascii: "\n")])) }
            }
            guard buffer.count <= Self.maxLine else { return }
        }
    }

    /// Runs one request line on the main actor; this connection's thread waits for it.
    private func answer(_ line: Data) -> Data? {
        final class Box: @unchecked Sendable { var reply: Data? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            box.reply = await RPCProtocol.respond(to: line, handler: CoucouRPC.dispatch)
            done.signal()
        }
        done.wait()
        return box.reply
    }

    private func send(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = Darwin.send(fd, raw.baseAddress! + sent, raw.count - sent, 0)
                if n <= 0 { return }
                sent += n
            }
        }
    }
}
#endif
