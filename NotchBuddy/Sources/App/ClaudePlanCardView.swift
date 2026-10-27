import SwiftUI

// MARK: - Claude Plan Card View

/// Draws the `card` part of the `plan` screen (ClaudePlanGauge.swift builds it from app state).
struct ClaudePlanCardView: View {
    let card: PlanCardScreen
    var onCodex: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: card.dotColor))
                    .frame(width: 7, height: 7)
                Text(card.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text(card.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Gauge rows
            VStack(alignment: .leading, spacing: 5) {
                ForEach(card.rows, id: \.label) { GaugeRowView(row: $0) }
                if let codex = card.codexRow {
                    // The Codex window closest to its limit; a click opens the Codex card.
                    Button(action: onCodex) {
                        GaugeRowView(row: codex).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

// MARK: - Gauge Row

struct GaugeRowView: View {
    let row: PlanGaugeRow

    init(row: PlanGaugeRow) { self.row = row }

    init(label: String, window: PlanWindow?, now: Date, weekly: Bool = false) {
        row = PlanGaugeRow.make(label: label, window: window, now: now, weekly: weekly)
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(row.label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .frame(width: 40, alignment: .leading)
            if let pct = row.pct {
                // Fixed-width bar (~50pt)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 50, height: 4)
                    Capsule()
                        .fill(Color(hex: row.color))
                        .frame(width: 50 * CGFloat(row.fill), height: 4)
                }
                .frame(width: 50, height: 4)
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
                if let reset = row.reset {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "#6B7079"))
                    Text(reset)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .fixedSize()
                }
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                Spacer()
            }
        }
    }
}
