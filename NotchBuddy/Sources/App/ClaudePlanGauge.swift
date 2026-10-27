import Foundation

// MARK: - Plan window

struct PlanWindow: Codable, Equatable {
    let usedPct: Double   // 0–100, clamped
    let resetsAt: Date
}

// MARK: - Plan usage

struct PlanUsage: Codable {
    var fiveHour: PlanWindow?
    var sevenDay: PlanWindow?
    var updatedAt: Date
}

// MARK: - Parsing + helpers (Foundation-only, no AppKit/SwiftUI)

enum ClaudePlanGauge {

    /// Parses rate_limits from a statusline payload dict. Returns nil if absent/malformed.
    static func parse(payload: [String: Any]) -> PlanUsage? {
        guard let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        let fh = parseWindow(limits["five_hour"])
        let sd = parseWindow(limits["seven_day"])
        guard fh != nil || sd != nil else { return nil }
        return PlanUsage(fiveHour: fh, sevenDay: sd, updatedAt: Date())
    }

    private static func parseWindow(_ raw: Any?) -> PlanWindow? {
        guard let d = raw as? [String: Any] else { return nil }
        let rawPct: Double
        if let v = d["used_percentage"] as? Double { rawPct = v }
        else if let v = d["used_percentage"] as? Int { rawPct = Double(v) }
        else { return nil }
        guard rawPct >= 0, rawPct <= 200 else { return nil }
        let pct = min(100, rawPct)   // clamp 100–200 down to 100
        let rawEpoch: Double
        if let v = d["resets_at"] as? Double { rawEpoch = v }
        else if let v = d["resets_at"] as? Int { rawEpoch = Double(v) }
        else { return nil }
        guard rawEpoch > 0 else { return nil }
        // Reject if more than 400 days in the future (likely milliseconds, not seconds)
        let maxEpoch = Date().timeIntervalSince1970 + 400 * 86400
        guard rawEpoch <= maxEpoch else { return nil }
        return PlanWindow(usedPct: pct, resetsAt: Date(timeIntervalSince1970: rawEpoch))
    }

    /// Effective % for display: 0 if the reset time is in the past.
    static func effectivePct(_ w: PlanWindow, now: Date = Date()) -> Double {
        w.resetsAt <= now ? 0 : w.usedPct
    }

    /// The higher of the two effective percentages. nil if both windows absent.
    static func dominantPct(_ usage: PlanUsage, now: Date = Date()) -> Double? {
        let p1 = usage.fiveHour.map { effectivePct($0, now: now) }
        let p2 = usage.sevenDay.map { effectivePct($0, now: now) }
        switch (p1, p2) {
        case (.none, .none): return nil
        case (let x?, .none): return x
        case (.none, let y?): return y
        case (let x?, let y?): return max(x, y)
        }
    }

    /// Hex color for a given percentage (nil → grey).
    static func color(for pct: Double?) -> String {
        guard let p = pct else { return "#6B7079" }
        if p < 50  { return "#22C55E" }
        if p < 80  { return "#F59E0B" }
        return "#F4505E"
    }

    /// Label of the plan pill in the notch header.
    static func pillLabel(_ usage: PlanUsage?, now: Date = Date()) -> String {
        guard let usage, let pct = dominantPct(usage, now: now) else { return "Claude —" }
        return "Claude \(Int(pct.rounded()))%"
    }
}

// MARK: - Screen models (what the plan card and pill draw; the `plan` screen)

/// One gauge row: label, bar, percentage and reset, ready to draw.
struct PlanGaugeRow: Codable, Equatable {
    let label: String
    let pct: Int?          // nil: no data, drawn as "—"
    let fill: Double       // bar width, 0…1
    let color: String
    let reset: String?

    private static let weeklyResetFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE H:mm"
        return fmt
    }()

    static func make(label: String, window: PlanWindow?, now: Date, weekly: Bool = false) -> PlanGaugeRow {
        guard let window else { return PlanGaugeRow(label: label, pct: nil, fill: 0, color: ClaudePlanGauge.color(for: nil), reset: nil) }
        let pct = ClaudePlanGauge.effectivePct(window, now: now)
        return PlanGaugeRow(label: label, pct: Int(pct.rounded()), fill: min(1, max(0, pct / 100)),
                            color: ClaudePlanGauge.color(for: pct), reset: resetLabel(window, now: now, weekly: weekly))
    }

    private static func resetLabel(_ w: PlanWindow, now: Date, weekly: Bool) -> String {
        let secs = w.resetsAt.timeIntervalSince(now)
        guard secs > 0 else { return String(localized: "plan.resetting") }
        if weekly { return weeklyResetFormatter.string(from: w.resetsAt) }
        let h = Int(secs / 3600)
        let m = Int((secs.truncatingRemainder(dividingBy: 3600)) / 60)
        if h > 0 { return String(format: String(localized: "plan.reset-in-hm %lld %lld"), Int64(h), Int64(m)) }
        return String(format: String(localized: "plan.reset-in-m %lld"), Int64(m))
    }
}

/// The Claude plan card in the notch, as drawn.
struct PlanCardScreen: Codable, Equatable {
    static let key = "card"

    let open: Bool              // showing in the notch now
    let title: String
    let subtitle: String
    let dotColor: String
    let rows: [PlanGaugeRow]
    let codexRow: PlanGaugeRow? // Claude and Codex both on: Codex is a third row

    static func build(open: Bool, usage: PlanUsage?, sourceNote: String?, codexRow: Bool,
                      codexWindow: PlanWindow?, codexWeekly: Bool, now: Date) -> PlanCardScreen {
        PlanCardScreen(
            open: open,
            title: String(localized: "plan.card.title"),
            subtitle: subtitle(usage: usage, sourceNote: sourceNote, now: now),
            dotColor: ClaudePlanGauge.color(for: usage.flatMap { ClaudePlanGauge.dominantPct($0, now: now) }),
            rows: [PlanGaugeRow.make(label: String(localized: "plan.5hours"), window: usage?.fiveHour, now: now),
                   PlanGaugeRow.make(label: String(localized: "plan.week"), window: usage?.sevenDay, now: now, weekly: true)],
            codexRow: codexRow ? PlanGaugeRow.make(label: "Codex", window: codexWindow, now: now, weekly: codexWeekly) : nil)
    }

    private static func subtitle(usage: PlanUsage?, sourceNote: String?, now: Date) -> String {
        guard let usage else { return sourceNote ?? String(localized: "plan.waiting") }
        let age = ageText(usage.updatedAt, now: now)
        return sourceNote.map { "\($0) · \(age)" } ?? age
    }

    private static func ageText(_ updatedAt: Date, now: Date) -> String {
        let diff = now.timeIntervalSince(updatedAt)
        if diff < 60 { return String(localized: "plan.just-now") }
        let mins = Int(diff / 60)
        if mins < 60 { return String(format: String(localized: "plan.mins-ago %lld"), Int64(mins)) }
        return String(format: String(localized: "plan.hours-ago %lld"), Int64(mins / 60))
    }
}

/// The plan pill in the notch header, as drawn.
struct PlanPillScreen: Codable, Equatable {
    static let key = "pill"

    let shown: Bool
    let kind: String     // claude | codex
    let label: String
    let color: String
    let open: Bool       // its card is showing
}
