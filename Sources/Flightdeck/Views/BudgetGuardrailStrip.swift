import SwiftUI
import AppKit

/// HUD strip showing real-time daily spend against budget limit and context window warnings.
struct BudgetGuardrailStrip: View {
    @Environment(DashboardStore.self) private var store
    @State private var budgetManager = BudgetManager.shared
    @State private var showBudgetPopover = false
    @State private var customBudgetText = ""

    private var todaySpend: Double {
        store.todaySpend
    }

    private var status: BudgetStatus {
        budgetManager.status(spent: todaySpend)
    }

    private var fraction: Double {
        budgetManager.budgetFraction(spent: todaySpend)
    }

    private var statusColor: Color {
        switch status {
        case .safe: return Theme.good
        case .warning: return Theme.warning
        case .exceeded: return Theme.critical
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            budgetCard
            contextCard
        }
    }

    // MARK: - Daily spend vs budget

    private var budgetCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                budgetHeader
                budgetAmounts
                budgetBar.frame(height: 5)
            }
            editBudgetButton
        }
        .padding(10)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(statusColor.opacity(0.25), lineWidth: 1))
    }

    private var budgetHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(statusColor)

            Text("DAILY SPEND BUDGET")
                .font(Theme.mono(9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)

            Spacer()

            Text(status.rawValue)
                .font(Theme.mono(8.5, weight: .bold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(statusColor.opacity(0.14), in: Capsule())
        }
    }

    private var budgetAmounts: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(Formatters.usd(todaySpend))
                .font(Theme.mono(16, weight: .bold))
                .foregroundStyle(Theme.ink1)

            Text("/ \(Formatters.usd(budgetManager.dailyBudget))")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.ink3)

            Spacer()

            remainder
        }
    }

    @ViewBuilder
    private var remainder: some View {
        let remaining = budgetManager.remainingBudget(spent: todaySpend)
        if remaining > 0 {
            Text("\(Formatters.usd(remaining)) left today")
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.good)
        } else {
            Text("+\(Formatters.usd(todaySpend - budgetManager.dailyBudget)) over")
                .font(Theme.mono(10.5, weight: .bold))
                .foregroundStyle(Theme.critical)
        }
    }

    private var budgetBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(statusColor)
                    .frame(width: Self.barWidth(in: geo.size.width, fraction: fraction))
            }
        }
    }

    /// Clamped to the track, with a 3pt stub so a near-zero spend still reads.
    private static func barWidth(in available: CGFloat, fraction: Double) -> CGFloat {
        let clamped = min(1, max(0, fraction))
        return max(3, min(available, available * CGFloat(clamped)))
    }

    private var editBudgetButton: some View {
        Button {
            customBudgetText = String(format: "%.0f", budgetManager.dailyBudget)
            showBudgetPopover.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                Text("BUDGET")
                    .font(Theme.mono(8.5, weight: .bold))
            }
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showBudgetPopover) {
            budgetSettingsPopover
        }
    }

    // MARK: - Context window headroom

    private var contextCard: some View {
        HStack(spacing: 10) {
            if let high = store.highContextSessions.first {
                contextAlert(high)
            } else {
                contextNominal
            }
        }
        .padding(10)
        .frame(maxWidth: 420)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(contextBorder, lineWidth: 1))
    }

    private var contextBorder: Color {
        store.highContextSessions.isEmpty ? Theme.good.opacity(0.2) : Theme.warning.opacity(0.4)
    }

    @ViewBuilder
    private func contextAlert(_ high: SessionAgg) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 16))
            .foregroundStyle(Theme.warning)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("CONTEXT ALERT")
                    .font(Theme.mono(9.5, weight: .bold))
                    .foregroundStyle(Theme.warning)

                Text("· \(high.project)")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.ink1)
            }

            Text(Self.contextSummary(high))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink2)
        }

        Spacer()

        Text("RUN /compact")
            .font(Theme.mono(9, weight: .bold))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }

    private static func contextSummary(_ high: SessionAgg) -> String {
        let used = Formatters.tokens(high.contextTokens)
        let total = Formatters.tokens(high.contextTotalTokens)
        let percent = Int(high.contextFraction * 100)
        return "\(used) of \(total) (\(percent)%)"
    }

    @ViewBuilder
    private var contextNominal: some View {
        Image(systemName: "checkmark.shield.fill")
            .font(.system(size: 16))
            .foregroundStyle(Theme.good)

        VStack(alignment: .leading, spacing: 2) {
            Text("CONTEXT WINDOW NOMINAL")
                .font(Theme.mono(9.5, weight: .bold))
                .foregroundStyle(Theme.good)

            Text("All active sessions within standard capacity (<70%)")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.ink3)
        }

        Spacer()
    }

    private var budgetSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SET DAILY SPEND BUDGET")
                .font(Theme.mono(10.5, weight: .bold))
                .foregroundStyle(Theme.ink1)

            Text("Set daily spending guardrail. Flightdeck monitors turns across all projects.")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)

            // Preset Chips
            HStack(spacing: 6) {
                ForEach([5.0, 10.0, 20.0, 50.0], id: \.self) { amount in
                    Button {
                        budgetManager.setDailyBudget(amount)
                        showBudgetPopover = false
                    } label: {
                        Text("$\(Int(amount))")
                            .font(Theme.mono(10.5, weight: .bold))
                            .foregroundStyle(budgetManager.dailyBudget == amount ? Theme.ink1 : Theme.ink3)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                budgetManager.dailyBudget == amount ? Theme.accent.opacity(0.25) : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(budgetManager.dailyBudget == amount ? Theme.accent : Theme.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Custom Input
            HStack(spacing: 6) {
                Text("$")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.ink3)
                TextField("Custom", text: $customBudgetText)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .frame(width: 80)

                Button {
                    if let val = Double(customBudgetText), val > 0 {
                        budgetManager.setDailyBudget(val)
                        showBudgetPopover = false
                    }
                } label: {
                    Text("SAVE")
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.good, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(6)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .frame(width: 280)
        .background(Theme.page)
    }
}
