import SwiftUI

/// The "was it worth it?" view.
///
/// Usage meters answer how much was spent. This answers what the spend produced:
/// which sessions changed no code, which code survived into HEAD, and which files
/// Claude keeps having to rewrite. All of it needs the repository on disk, which is
/// why it can't be done from transcripts alone.
struct InsightsPanel: View {
    @Environment(DashboardStore.self) private var store
    @Environment(SessionOutcomeStore.self) private var outcomes

    /// Raw on purpose: every figure on this panel is measured against the real
    /// repository, so redacted paths would make the whole view read as empty.
    private var sessions: [SessionAgg] { store.rawActiveSessions }
    private var waste: WasteReport { WasteReport(sessions: sessions) }
    private var hotspots: [ChurnHotspot] { ChurnAnalyzer.hotspots(in: sessions) }

    /// Masking happens here, on the way to the screen, and nowhere earlier.
    private func shown(_ session: SessionAgg) -> SessionAgg {
        session.redacted(by: store.redactor)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                outcomeRibbon
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 16) {
                        survivalSection
                        wasteSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    churnSection.frame(width: 360)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { outcomes.refresh(sessions: sessions) }
        .onChange(of: sessions.count) { _, _ in outcomes.refresh(sessions: sessions) }
    }

    // MARK: - Cost per outcome

    private var outcomeRibbon: some View {
        let roll = outcomes.rollup(for: sessions)
        return HStack(spacing: 12) {
            metric(
                title: "CODE THAT SURVIVED",
                value: roll.filesConsidered > 0 ? "\(Int(roll.survivalRate * 100))%" : "—",
                subtitle: roll.filesConsidered > 0
                    ? "\(roll.filesInHead) of \(roll.filesConsidered) files still in HEAD"
                    : "no measured repositories yet",
                accent: Theme.good
            )
            metric(
                title: "COST PER SURVIVING FILE",
                value: roll.costPerSurvivingFile.map(Formatters.usd) ?? "—",
                subtitle: "\(roll.sessionsMeasured) sessions measured against git",
                accent: Theme.accent
            )
            metric(
                title: "COST PER COMMIT",
                value: roll.costPerCommit.map(Formatters.usd) ?? "—",
                subtitle: "\(roll.commits) commits touching files these sessions wrote",
                accent: Theme.accentSecondary
            )
            metric(
                title: "SPEND WITH NO CODE",
                value: Formatters.usd(waste.totalAttributableCost),
                subtitle: "\(waste.findings(ofKind: .noCodeChange).count) sessions changed nothing",
                accent: waste.totalAttributableCost > 0 ? Theme.warning : Theme.ink3
            )
        }
    }

    private func metric(title: String, value: String, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.mono(9.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.mono(20, weight: .bold))
                .foregroundStyle(Theme.ink1)
            Text(subtitle)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .glassPanel(accent: accent)
    }

    // MARK: - Waste

    private var wasteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("WHERE THE MONEY WENT", count: waste.findings.count)

            if waste.isEmpty {
                emptyState("Nothing flagged. Every session with real spend also produced code, kept its cache warm, and stayed clear of the context ceiling.")
            } else {
                VStack(spacing: 8) {
                    ForEach(waste.findings) { finding in
                        WasteFindingRow(finding: finding.redacted(by: store.redactor))
                    }
                }
            }
        }
    }

    // MARK: - Survival per session

    private var survivalSection: some View {
        let measured = sessions.compactMap { session -> (SessionAgg, GitOutcome)? in
            guard let outcome = outcomes.outcome(for: session.id), outcome.filesConsidered > 0 else { return nil }
            return (session, outcome)
        }
        .sorted { $0.1.filesConsidered > $1.1.filesConsidered }

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("DID THE CODE STICK?", count: measured.count)
            if measured.isEmpty {
                emptyState(outcomes.isProbing
                    ? "Measuring against git…"
                    : "No sessions with tracked file changes in a git repository yet.")
            } else {
                VStack(spacing: 7) {
                    ForEach(measured, id: \.0.id) { session, outcome in
                        SurvivalRow(session: shown(session), outcome: outcome)
                    }
                }
            }
        }
    }

    // MARK: - Churn

    private var churnSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("FILES CLAUDE KEEPS REWRITING", count: hotspots.count)
            if hotspots.isEmpty {
                emptyState("No file has been rewritten across multiple sessions yet.")
            } else {
                VStack(spacing: 6) {
                    ForEach(hotspots.prefix(10)) { spot in
                        HStack(spacing: 8) {
                            Text("\(spot.sessionCount)×")
                                .font(Theme.mono(11, weight: .bold))
                                .foregroundStyle(spot.sessionCount >= 4 ? Theme.warning : Theme.accentSecondary)
                                .frame(width: 26, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(store.redactor.fileName(spot.fileName))
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.ink1)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(spot.diagnosis.rawValue)
                                        .font(Theme.mono(8, weight: .bold))
                                        .foregroundStyle(diagnosisColor(spot.diagnosis))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(diagnosisColor(spot.diagnosis).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                }
                                Text(spot.projects.map(store.redactor.project).joined(separator: ", "))
                                    .font(Theme.mono(9))
                                    .foregroundStyle(Theme.ink3)
                                    .lineLimit(1)
                            }
                        }
                        .help("\(store.redactor.path(spot.path))\n\n\(spot.diagnosis.rawValue): \(spot.suggestedAction)")
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
    }

    private func diagnosisColor(_ diagnosis: ChurnDiagnosis) -> Color {
        switch diagnosis {
        case .missingInstructions: return Theme.warning
        case .taskTooLarge:        return Theme.critical
        case .architecturalCoupling: return Theme.accentSecondary
        case .activeIteration:     return Theme.good
        }
    }

    // MARK: - Shared pieces

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(Theme.mono(10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Theme.ink2)
            if count > 0 {
                Text("\(count)")
                    .font(Theme.mono(9, weight: .bold))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
            Spacer()
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(Theme.ui(11.5))
            .foregroundStyle(Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Rows

private struct WasteFindingRow: View {
    let finding: WasteFinding

    private var accent: Color {
        switch finding.kind {
        case .noCodeChange:    return Theme.warning
        case .toolFailures:    return Theme.critical
        case .cacheChurn:      return Theme.accentSecondary
        case .contextPressure: return Theme.warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(finding.title)
                    .font(Theme.mono(9.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(accent)
                Text(finding.project)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.ink3)
                Spacer()
                if let attributable = finding.attributableCost {
                    Text(Formatters.usd(attributable))
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(accent)
                } else {
                    // No honest split exists for this finding, so the session's own
                    // cost is shown as context rather than a fabricated share.
                    Text("in a \(Formatters.usd(finding.sessionCost)) session")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
            Text(finding.detail)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Text(finding.kind.advice)
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.22), lineWidth: 1))
    }
}

private struct SurvivalRow: View {
    let session: SessionAgg
    let outcome: GitOutcome

    private var color: Color {
        if outcome.survivalRate >= 0.9 { return Theme.good }
        if outcome.survivalRate >= 0.6 { return Theme.warning }
        return Theme.critical
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(session.displayTitle)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.ink1)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(outcome.survivalRate * 100))%")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(color)
            }
            HStack(spacing: 6) {
                Text("\(outcome.filesInHead)/\(outcome.filesConsidered) files in HEAD")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.ink3)
                if outcome.filesDropped > 0 {
                    Text("· \(outcome.filesDropped) dropped")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.critical)
                }
                if let commits = outcome.commits, commits > 0 {
                    Text("· \(commits) commits")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                if session.totalCost > 0 {
                    Text(Formatters.usd(session.totalCost))
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(color)
                        .frame(width: max(2, geo.size.width * outcome.survivalRate))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
    }
}
