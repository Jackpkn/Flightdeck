import SwiftUI

/// Which Claude Code skills actually get used, from the `skillUsage` tally Claude
/// Code keeps in `~/.claude.json`. Counts are lifetime totals, not per-session.
struct SkillUsageStrip: View {
    @State private var skills: [ClaudeSkillUsage] = []

    /// Enough to see the shape of usage without turning the strip into a list.
    private static let displayLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accentSecondary)
                Text("SKILLS USED")
                    .font(Theme.mono(9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink3)
                Spacer()
                if !skills.isEmpty {
                    Text("\(skills.count) total")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.ink3)
                }
            }

            if skills.isEmpty {
                Text("No skill invocations recorded yet.")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink3)
            } else {
                FlowRow(spacing: 5, lineSpacing: 5) {
                    ForEach(skills.prefix(Self.displayLimit)) { skill in
                        HStack(spacing: 4) {
                            Text(skill.name)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.ink2)
                            Text("\(skill.usageCount)")
                                .font(Theme.mono(9.5, weight: .bold))
                                .foregroundStyle(Theme.accentSecondary)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.04), in: Capsule())
                        .help(helpText(for: skill))
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(accent: Theme.accentSecondary)
        .onAppear { skills = ClaudeSkillUsageReader.load() }
    }

    private func helpText(for skill: ClaudeSkillUsage) -> String {
        guard let last = skill.lastUsedAt else {
            return "\(skill.name) · used \(skill.usageCount)×"
        }
        let age = Formatters.relativeAge(Date().timeIntervalSince(last))
        return "\(skill.name) · used \(skill.usageCount)× · last \(age)"
    }
}
