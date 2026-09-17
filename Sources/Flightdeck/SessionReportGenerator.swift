import Foundation

/// Compiles comprehensive post-mortem reports for Claude Code sessions, combining
/// cost, token burn rate, Git outcome code survival, and file churn diagnostics.
enum SessionReportGenerator {

    /// Generates a GitHub-flavored Markdown post-mortem document.
    static func generateMarkdown(
        session: SessionAgg,
        outcome: GitOutcome? = nil,
        hotspots: [ChurnHotspot] = [],
        waste: WasteReport? = nil
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dateStr = formatter.string(from: session.startedAt ?? Date())

        var md = """
        # ⚡️ Claude Code Session Post-Mortem Report

        **Session ID:** `\(session.id)`  
        **Project:** `\(session.project)`  
        **Branch:** `\(session.branch.isEmpty ? "HEAD" : session.branch)`  
        **Model:** `\(session.model.isEmpty ? "claude-3-7-sonnet" : session.model)`  
        **Generated At:** \(dateStr)  

        ---

        ## 📊 Executive Summary & Spend

        | Metric | Value |
        | :--- | :--- |
        | **Total Session Spend** | `\(Formatters.usd(session.totalCost))` |
        | **Context Fill** | `\(Formatters.tokens(session.contextTokens)) / \(Formatters.tokens(session.contextTotalTokens)) (\(Int(session.contextFraction * 100))%)` |
        | **Files Modified** | `\(session.filesModifiedCount)` |
        | **Lines Added / Removed** | `+\(session.linesAdded) / -\(session.linesRemoved)` |
        | **Tool Invocations** | `\(session.toolUseCount) calls (\(session.toolErrorCount) failed)` |

        """

        // Git Code Survival Section
        md += "\n## 🧬 Git Outcome & Code Survival in HEAD\n\n"
        if let outcome {
            let survivalPct = Int(outcome.survivalRate * 100)
            md += """
            * **Survival Rate in HEAD:** `\(survivalPct)%`
            * **Files Tracked:** `\(outcome.filesConsidered)`
            * **Files Still in HEAD:** `\(outcome.filesInHead)`
            * **Files Dropped / Reverted:** `\(outcome.filesDropped)`
            * **Attributed Commits:** `\(outcome.commits ?? 0)`
            * **Net Committed Lines:** `\(outcome.netLines.map(String.init) ?? "—")`

            """
            if survivalPct < 50 {
                md += "> ⚠️ **Low Survival Warning:** Over half the files written in this session were subsequently reverted or deleted. Check for oscillating diffs or unclear specifications.\n\n"
            }
        } else {
            md += "*Working directory was not a recognized Git repository or files were outside repository root.*\n\n"
        }

        // Token Breakdown
        md += """
        ## 🪙 Token Breakdown & Cache Efficiency

        * **Input Tokens:** `\(Formatters.tokens(session.inputTokens))`
        * **Output Tokens:** `\(Formatters.tokens(session.outputTokens))`
        * **Thinking Tokens:** `\(Formatters.tokens(session.thinkingTokens))`
        * **Cache Read Tokens:** `\(Formatters.tokens(session.cacheReadTokens))`
        * **Cache Creation Tokens:** `\(Formatters.tokens(session.cacheCreationTokens))`

        """

        let cacheTotal = session.cacheReadTokens + session.cacheCreationTokens
        if cacheTotal > 0 {
            let readRatio = Double(session.cacheReadTokens) / Double(cacheTotal)
            md += "* **Cache Hit Rate:** `\(Int(readRatio * 100))%`\n\n"
        }

        // Files Modified & Churn
        md += "## 📁 Modified Files & Churn Diagnostics\n\n"
        if session.filesModified.isEmpty {
            md += "*No tracked files were modified in this session.*\n\n"
        } else {
            md += "| File Path | Total Cross-Session Churn | Diagnosis | Actionable Advice |\n"
            md += "| :--- | :--- | :--- | :--- |\n"
            for file in session.filesModified {
                let spot = hotspots.first { $0.path == file }
                let churnCount = spot?.sessionCount ?? 1
                let diag = spot?.diagnosis.rawValue ?? "ACTIVE ITERATION"
                let advice = spot?.suggestedAction ?? "Healthy ongoing development."
                let fileName = URL(fileURLWithPath: file).lastPathComponent
                md += "| `\(fileName)` | `\(churnCount)×` | `\(diag)` | \(advice) |\n"
            }
            md += "\n"
        }

        // Waste Findings
        if let waste, !waste.findings.isEmpty {
            md += "## 🔍 Waste & Inefficiency Findings\n\n"
            for finding in waste.findings where finding.sessionId == session.id {
                md += "### ⚠️ \(finding.title)\n"
                md += "* **Detail:** \(finding.detail)\n"
                md += "* **Advice:** \(finding.kind.advice)\n\n"
            }
        }

        md += "---\n*Report compiled locally by Flightdeck Developer Cockpit.*\n"
        return md
    }

    /// Generates a structured JSON representation of the post-mortem.
    static func generateJSON(
        session: SessionAgg,
        outcome: GitOutcome? = nil,
        hotspots: [ChurnHotspot] = []
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "sessionId": session.id,
            "project": session.project,
            "branch": session.branch,
            "model": session.model,
            "totalCostUsd": session.totalCost,
            "contextTokens": session.contextTokens,
            "contextTotalTokens": session.contextTotalTokens,
            "contextFraction": session.contextFraction,
            "filesModifiedCount": session.filesModifiedCount,
            "linesAdded": session.linesAdded,
            "linesRemoved": session.linesRemoved,
            "toolUseCount": session.toolUseCount,
            "toolErrorCount": session.toolErrorCount,
            "tokens": [
                "input": session.inputTokens,
                "output": session.outputTokens,
                "thinking": session.thinkingTokens,
                "cacheRead": session.cacheReadTokens,
                "cacheCreation": session.cacheCreationTokens
            ]
        ]

        if let outcome {
            dict["gitOutcome"] = [
                "survivalRate": outcome.survivalRate,
                "filesConsidered": outcome.filesConsidered,
                "filesInHead": outcome.filesInHead,
                "filesDropped": outcome.filesDropped,
                "commits": outcome.commits ?? 0,
                "netLines": outcome.netLines ?? 0
            ]
        }

        dict["files"] = session.filesModified.map { file -> [String: Any] in
            let spot = hotspots.first { $0.path == file }
            return [
                "path": file,
                "churnCount": spot?.sessionCount ?? 1,
                "diagnosis": spot?.diagnosis.rawValue ?? "ACTIVE ITERATION",
                "advice": spot?.suggestedAction ?? "Normal ongoing development."
            ]
        }

        return dict
    }
}
