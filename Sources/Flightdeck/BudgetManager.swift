import Foundation
import Observation

/// Status of current spend against the configured daily budget.
enum BudgetStatus: String, Sendable {
    case safe = "ON TRACK"
    case warning = "NEARING BUDGET (80%+)"
    case exceeded = "BUDGET EXCEEDED"
}

/// Manages daily spending guardrails and threshold calculations.
@Observable
final class BudgetManager {
    static let shared = BudgetManager()

    private let userDefaultsKey = "flightdeck.daily_budget"
    private let defaultBudget: Double = 20.0

    var dailyBudget: Double {
        didSet {
            UserDefaults.standard.set(dailyBudget, forKey: userDefaultsKey)
        }
    }

    init() {
        let saved = UserDefaults.standard.double(forKey: "flightdeck.daily_budget")
        self.dailyBudget = saved > 0 ? saved : 20.0
    }

    func setDailyBudget(_ amount: Double) {
        let clamped = max(1.0, amount)
        self.dailyBudget = clamped
    }

    func budgetFraction(spent: Double) -> Double {
        guard dailyBudget > 0 else { return 0 }
        return min(2.0, max(0, spent / dailyBudget))
    }

    func remainingBudget(spent: Double) -> Double {
        max(0, dailyBudget - spent)
    }

    func status(spent: Double) -> BudgetStatus {
        let fraction = spent / dailyBudget
        if fraction >= 1.0 {
            return .exceeded
        } else if fraction >= 0.8 {
            return .warning
        } else {
            return .safe
        }
    }
}
