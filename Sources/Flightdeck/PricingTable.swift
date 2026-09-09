import Foundation

/// Approximate USD-per-million-token rates. Keep in sync with current vendor pricing —
/// these are for relative cost tracking, not billing reconciliation.
enum PricingTable {
    struct Rates {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
    }

    static let rates: [String: Rates] = [
        "claude-opus-5":            Rates(input: 5,   output: 25, cacheRead: 0.5,  cacheWrite: 6.25),
        "claude-sonnet-5":          Rates(input: 3,   output: 15, cacheRead: 0.3,  cacheWrite: 3.75),
        "claude-haiku-4-5-20251001": Rates(input: 0.8, output: 4,  cacheRead: 0.08, cacheWrite: 1.0),
    ]
    static let fallback = Rates(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75)

    static func cost(model: String?, usage: ClaudeLogLine.Usage?) -> Double {
        guard let usage else { return 0 }
        let r = rates[model ?? ""] ?? fallback
        let input      = Double(usage.input_tokens ?? 0)
        let output     = Double(usage.output_tokens ?? 0)
        let cacheRead  = Double(usage.cache_read_input_tokens ?? 0)
        let cacheWrite = Double(usage.cache_creation_input_tokens ?? 0)
        return (input * r.input + output * r.output + cacheRead * r.cacheRead + cacheWrite * r.cacheWrite) / 1_000_000
    }
}
