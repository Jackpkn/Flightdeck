import Foundation

/// Fixed-locale formatting so token counts and currency read the same everywhere,
/// regardless of the machine's region setting (e.g. Indian digit grouping).
enum Formatters {
    private static let group: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.groupingSize = 3
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f
    }()

    static func tokens(_ n: Int) -> String {
        group.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func usd(_ n: Double) -> String {
        let negative = n < 0
        let totalCents = Int((abs(n) * 100).rounded())
        let dollars = totalCents / 100
        let cents = totalCents % 100
        let dollarsStr = group.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
        return (negative ? "-$" : "$") + dollarsStr + String(format: ".%02d", cents)
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
