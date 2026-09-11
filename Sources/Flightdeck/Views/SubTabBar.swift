import SwiftUI

/// A section within a top-level tab.
///
/// Flightdeck covers two domains that a user genuinely wants in one window — what
/// the machine is doing and what Claude Code is costing — which is a lot of surface.
/// Grouping related panels behind a second level keeps the top bar short enough to
/// scan without hiding anything.
protocol SubTab: Hashable, CaseIterable, Identifiable {
    var title: String { get }
    var icon: String { get }
}

extension SubTab {
    var id: Self { self }
}

/// Segmented selector for a tab's sections.
struct SubTabBar<Tab: SubTab>: View {
    @Binding var selection: Tab
    /// Optional badge per section, e.g. a count of things needing attention.
    var badge: (Tab) -> String? = { _ in nil }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Tab.allCases)) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = item }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11))
                        Text(item.title)
                            .font(Theme.ui(11.5, weight: selection == item ? .semibold : .regular))
                        if let badge = badge(item) {
                            Text(badge)
                                .font(Theme.mono(9, weight: .bold))
                                .foregroundStyle(Theme.warning)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Theme.warning.opacity(0.16), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(selection == item ? Theme.accent.opacity(0.18) : Color.white.opacity(0.03))
                    .foregroundStyle(selection == item ? Theme.accent : Theme.ink2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(3)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}
