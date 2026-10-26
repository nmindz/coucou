import Foundation

/// Plan usage read from a claude-lb load balancer (`GET /api/analytics/quota`), turned into the
/// same `PlanUsage` the Claude Code status line feeds the notch gauge.
enum ClaudeLB {
    static let defaultURL = "http://127.0.0.1:21987"
    static let keychainKey = "claudelb-api-key"

    /// What the gauge means when several accounts are selected.
    enum Aggregation: String, CaseIterable, Codable {
        case average   // mean utilization of the selected accounts (the pool's headroom)
        case mostUsed  // the selected account closest to its limit
        case single    // exactly one account, mirrored as is
    }

    struct Window: Equatable {
        let usedPct: Double
        let resetsAt: Date
    }

    struct Account: Equatable, Identifiable {
        let id: String
        let label: String
        let planTier: String
        let fiveHour: Window?
        let sevenDay: Window?
    }

    enum Failure: Error, Equatable {
        case badURL
        case noKey          // nothing saved yet: no request is sent
        case unauthorized   // 401: a key claude-lb does not know
        case forbidden      // 403: the key lacks "Read usage analytics"
        case http(Int)
        case unreachable
        case malformed
    }

    // MARK: Parsing

    /// The accounts of a `/api/analytics/quota` body. Windows never probed stay nil (not 0 %).
    static func parseQuota(_ data: Data) -> [Account]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let rows = payload["accounts"] as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard let ref = row["account"] as? [String: Any], let id = ref["id"] as? String else { return nil }
            let label = (ref["label"] as? String) ?? (ref["email"] as? String) ?? id
            return Account(id: id, label: label, planTier: ref["planTier"] as? String ?? "unknown",
                           fiveHour: window(row["fiveHour"]), sevenDay: window(row["sevenDay"]))
        }
    }

    private static func window(_ raw: Any?) -> Window? {
        guard let w = raw as? [String: Any],
              let pct = (w["utilizationPercent"] as? NSNumber)?.doubleValue,
              let reset = (w["resetAt"] as? String).flatMap(parseDate) else { return nil }
        // A rolled-over window reports 0; claude-lb can report over 100.
        let passed = (w["resetPassed"] as? Bool) ?? false
        return Window(usedPct: passed ? 0 : min(100, max(0, pct)), resetsAt: reset)
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: Aggregation

    /// The accounts the gauge counts: the selection, or every account when nothing is selected.
    /// `single` keeps one account: the first selected one in claude-lb's order.
    static func counted(_ accounts: [Account], selected: Set<String>, mode: Aggregation) -> [Account] {
        let chosen = selected.isEmpty ? accounts : accounts.filter { selected.contains($0.id) }
        return mode == .single ? Array(chosen.prefix(1)) : chosen
    }

    static func planUsage(_ accounts: [Account], selected: Set<String>, mode: Aggregation,
                          now: Date = Date()) -> PlanUsage? {
        let pool = counted(accounts, selected: selected, mode: mode)
        let five = combine(pool.compactMap(\.fiveHour), mode: mode)
        let seven = combine(pool.compactMap(\.sevenDay), mode: mode)
        guard five != nil || seven != nil else { return nil }
        return PlanUsage(fiveHour: five, sevenDay: seven, updatedAt: now)
    }

    private static func combine(_ windows: [Window], mode: Aggregation) -> PlanWindow? {
        guard !windows.isEmpty else { return nil }
        switch mode {
        case .average:
            let mean = windows.map(\.usedPct).reduce(0, +) / Double(windows.count)
            return PlanWindow(usedPct: mean, resetsAt: windows.map(\.resetsAt).min()!)
        case .mostUsed, .single:
            let top = windows.max { $0.usedPct < $1.usedPct }!
            return PlanWindow(usedPct: top.usedPct, resetsAt: top.resetsAt)
        }
    }

    // MARK: Network

    /// One GET of the quota with the analytics key (sent as `x-api-key`).
    static func fetchQuota(baseURL: String, apiKey: String) async -> Result<[Account], Failure> {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/analytics/quota"), url.host != nil,
              ["http", "https"].contains(url.scheme ?? "") else { return .failure(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return .failure(.unreachable) }
        switch http.statusCode {
        case 200: return parseQuota(data).map(Result.success) ?? .failure(.malformed)
        case 401: return .failure(.unauthorized)
        case 403: return .failure(.forbidden)
        default:  return .failure(.http(http.statusCode))
        }
    }
}
