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
        let absN = abs(n)
        if absN == 0 {
            return "$0.00"
        }
        if absN < 0.01 {
            // Sub-cent amounts: show up to 4 decimal places (e.g. $0.0007)
            let formatted = String(format: "%.4f", absN)
            return (negative ? "-$" : "$") + formatted
        } else if absN < 100.0 {
            // If fractional cents exist (e.g. $1.7424 or $27.7558), display 4 decimal places
            let cents = absN * 100
            let centsRound = cents.rounded()
            if abs(cents - centsRound) < 0.0001 {
                let dollars = Int(absN)
                let c = Int(centsRound) % 100
                let dollarsStr = group.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
                return (negative ? "-$" : "$") + dollarsStr + String(format: ".%02d", c)
            } else {
                let dollars = Int(absN)
                let dollarsStr = group.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
                let fractionStr = String(format: "%.4f", absN - Double(dollars)).dropFirst(2)
                return (negative ? "-$" : "$") + dollarsStr + "." + fractionStr
            }
        } else {
            let totalCents = Int((absN * 100).rounded())
            let dollars = totalCents / 100
            let cents = totalCents % 100
            let dollarsStr = group.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
            return (negative ? "-$" : "$") + dollarsStr + String(format: ".%02d", cents)
        }
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
