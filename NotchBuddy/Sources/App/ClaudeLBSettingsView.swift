#if !APPSTORE
import SwiftUI

/// Settings → Agents → Plan usage: read the Claude gauge from a claude-lb load balancer.
struct ClaudeLBPlanSourceView: View {
    @Binding var statusMessage: String
    @ObservedObject private var state = AppState.shared
    @State private var url: String = AppState.shared.claudeLBURL
    @State private var key: String = KeychainStore.shared.get(ClaudeLB.keychainKey) ?? ""
    @State private var connecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(String(localized: "claudelb.toggle"), isOn: Binding(
                get: { state.planFromClaudeLB },
                set: { on in
                    state.planFromClaudeLB = on
                    if on {
                        state.showPlanInNotch = true   // the source is only useful with the pill showing
                        Task { await state.loadClaudeLB() }
                    }
                }
            ))
            Text(String(localized: "claudelb.description"))
                .coucouFont(size: 14)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state.planFromClaudeLB {
                HStack(spacing: 8) {
                    TextField(ClaudeLB.defaultURL, text: $url)
                        .coucouField(icon: "link", monospaced: true)
                    SecureField(String(localized: "claudelb.key"), text: $key)
                        .coucouField(icon: "key.fill")
                        .frame(maxWidth: 240)
                }
                HStack(spacing: 10) {
                    Button(connecting ? String(localized: "chat.connecting") : String(localized: "chat.connect"),
                           action: connect)
                        .coucouButton(primary: true)
                        .disabled(connecting)
                    if let error = state.claudeLBError {
                        Text(Self.message(for: error))
                            .coucouFont(size: 14)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !state.claudeLBAccounts.isEmpty {
                    Picker(String(localized: "claudelb.meaning"), selection: $state.claudeLBAggregation) {
                        Text(String(localized: "claudelb.mode.average")).tag(ClaudeLB.Aggregation.average)
                        Text(String(localized: "claudelb.mode.most-used")).tag(ClaudeLB.Aggregation.mostUsed)
                        Text(String(localized: "claudelb.mode.single")).tag(ClaudeLB.Aggregation.single)
                    }
                    .pickerStyle(.segmented)
                    Text(String(localized: state.claudeLBAggregation == .single
                                ? "claudelb.accounts.hint-single" : "claudelb.accounts.hint"))
                        .coucouFont(size: 14)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(state.claudeLBAccounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }
        }
    }

    private func accountRow(_ account: ClaudeLB.Account) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { state.claudeLBSelected.contains(account.id) },
                set: { on in
                    if state.claudeLBAggregation == .single {
                        state.claudeLBSelected = on ? [account.id] : []
                    } else if on {
                        state.claudeLBSelected.insert(account.id)
                    } else {
                        state.claudeLBSelected.remove(account.id)
                    }
                }
            )) {
                Text(account.label).coucouFont(size: 15)
            }
            .toggleStyle(.checkbox)
            Text(account.planTier)
                .coucouFont(size: 13, weight: .medium)
                .foregroundColor(.secondary)
            Spacer()
            Text(Self.windowText(account.fiveHour, "5h") + "   " + Self.windowText(account.sevenDay, "7d"))
                .coucouFont(size: 14, design: .monospaced)
                .foregroundColor(.secondary)
        }
    }

    private func connect() {
        let base = url.trimmingCharacters(in: .whitespacesAndNewlines)
        state.claudeLBURL = base.isEmpty ? ClaudeLB.defaultURL : base
        url = state.claudeLBURL
        KeychainStore.shared.set(ClaudeLB.keychainKey, value: key.trimmingCharacters(in: .whitespacesAndNewlines))
        connecting = true
        Task {
            await state.loadClaudeLB()
            connecting = false
            if state.claudeLBError == nil {
                statusMessage = String(format: String(localized: "claudelb.connected %lld"),
                                       Int64(state.claudeLBAccounts.count))
            }
        }
    }

    private static func windowText(_ w: ClaudeLB.Window?, _ name: String) -> String {
        guard let w else { return "\(name) —" }
        return "\(name) \(Int(w.usedPct.rounded()))%"
    }

    private static func message(for failure: ClaudeLB.Failure) -> String {
        switch failure {
        case .badURL:       return String(localized: "claudelb.error.url")
        case .noKey:        return String(localized: "claudelb.error.no-key")
        case .unauthorized: return String(localized: "claudelb.error.key")
        case .forbidden:    return String(localized: "claudelb.error.analytics")
        case .unreachable:  return String(localized: "claudelb.error.unreachable")
        case .malformed:    return String(localized: "claudelb.error.malformed")
        case .http(let code): return "claude-lb: HTTP \(code)"
        }
    }
}
#endif
