import Foundation
import Combine

/// The screens Coucou publishes (docs/RPC.md).
enum Screen: String, CaseIterable, Sendable {
    case settings   // the Coucou window: page, status line, Settings sections
    case plan       // the plan card and the plan pill in the notch
}

/// What a reader sees of one screen: the parts its builders published, plus UI-only state.
struct ScreenEntry {
    struct Part {
        let value: Any   // what the view draws
        let json: Data   // the same value, encoded: what the RPC returns
    }

    let screen: Screen
    var revision: UInt64 = 0
    var updatedAt = Date()
    var parts: [String: Part] = [:]
    var ui: [String: Any] = [:]

    /// `{screen, revision, updated_at, view, ui}`.
    var json: [String: Any] {
        var view: [String: Any] = [:]
        for (key, part) in parts {
            view[key] = (try? JSONSerialization.jsonObject(with: part.json, options: [.fragmentsAllowed])) ?? NSNull()
        }
        return ["screen": screen.rawValue, "revision": revision,
                "updated_at": ISO8601DateFormatter().string(from: updatedAt), "view": view, "ui": ui]
    }
}

/// Every view a window renders is built from app state and published here; the view draws the
/// stored value and the debug RPC returns that same value, so the RPC shows what is on screen.
@MainActor
final class ScreenStore: ObservableObject {
    static let shared = ScreenStore()

    @Published private(set) var entries: [Screen: ScreenEntry] = [:]
    private var builders: [Screen: () -> Void] = [:]
    private var queued: Set<Screen> = []
    private var waiters: [UUID: (screen: Screen, minRevision: UInt64, resume: CheckedContinuation<Bool, Never>)] = [:]

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    // MARK: Building

    /// The builder that publishes every part of `screen` from the app's state.
    func register(_ screen: Screen, build: @escaping () -> Void) { builders[screen] = build }

    func refresh(_ screen: Screen) { builders[screen]?() }

    /// Rebuilds on the next turn of the main actor; requests in the same turn make one build.
    func schedule(_ screens: Screen...) {
        let wasIdle = queued.isEmpty
        queued.formUnion(screens)
        guard wasIdle, !queued.isEmpty else { return }
        Task { @MainActor in
            let due = self.queued
            self.queued = []
            for screen in Screen.allCases where due.contains(screen) { self.refresh(screen) }
        }
    }

    // MARK: Publishing

    /// Replaces one part; an identical value keeps the revision. True when it changed.
    @discardableResult
    func publish<T: Encodable>(_ screen: Screen, _ key: String, _ value: T) -> Bool {
        guard let json = try? Self.encoder.encode(value) else { return false }
        return update(screen) { entry in
            if entry.parts[key]?.json == json { return false }
            entry.parts[key] = .init(value: value, json: json)
            return true
        }
    }

    /// Shallow-merges UI-only state (JSON values; `NSNull()` clears a key). True when it changed.
    @discardableResult
    func mergeUI(_ screen: Screen, _ patch: [String: Any]) -> Bool {
        update(screen) { entry in
            var changed = false
            for (key, value) in patch where !Self.same(entry.ui[key], value) {
                entry.ui[key] = value
                changed = true
            }
            return changed
        }
    }

    private func update(_ screen: Screen, _ change: (inout ScreenEntry) -> Bool) -> Bool {
        var entry = entries[screen] ?? ScreenEntry(screen: screen)
        guard change(&entry) else { return false }
        entry.revision += 1
        entry.updatedAt = Date()
        entries[screen] = entry
        for (id, waiter) in waiters where waiter.screen == screen && entry.revision >= waiter.minRevision {
            waiters[id] = nil
            waiter.resume.resume(returning: true)
        }
        return true
    }

    private static func same(_ old: Any?, _ new: Any) -> Bool {
        guard let old else { return new is NSNull }
        return (old as AnyObject).isEqual(new as AnyObject)
    }

    // MARK: Reading

    func part<T>(_ screen: Screen, _ key: String, as type: T.Type = T.self) -> T? {
        entries[screen]?.parts[key]?.value as? T
    }

    func ui(_ screen: Screen, _ key: String) -> Any? {
        let value = entries[screen]?.ui[key]
        return value is NSNull ? nil : value
    }

    func revision(_ screen: Screen) -> UInt64 { entries[screen]?.revision ?? 0 }

    func entryJSON(_ screen: Screen) -> [String: Any] { (entries[screen] ?? ScreenEntry(screen: screen)).json }

    func summaries() -> [[String: Any]] {
        Screen.allCases.map { screen in
            let entry = entries[screen]
            return ["screen": screen.rawValue, "revision": entry?.revision ?? 0,
                    "updated_at": entry.map { ISO8601DateFormatter().string(from: $0.updatedAt) } ?? NSNull(),
                    "published": !(entry?.parts.isEmpty ?? true)]
        }
    }

    /// Waits until `screen` reaches `minRevision`; false on timeout.
    func wait(_ screen: Screen, minRevision: UInt64, timeout: Duration) async -> Bool {
        if revision(screen) >= minRevision { return true }
        let id = UUID()
        return await withCheckedContinuation { resume in
            waiters[id] = (screen, minRevision, resume)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if let waiter = self.waiters.removeValue(forKey: id) { waiter.resume.resume(returning: false) }
            }
        }
    }
}
