import Testing
import Foundation
@testable import Flightdeck

@Suite("BudgetManagerTests")
struct BudgetManagerTests {

    @Test("BudgetManager computes budget fractions accurately")
    func testBudgetFraction() {
        let manager = BudgetManager()
        manager.setDailyBudget(20.0)

        #expect(manager.budgetFraction(spent: 0.0) == 0.0)
        #expect(abs(manager.budgetFraction(spent: 10.0) - 0.5) < 0.001)
        #expect(abs(manager.budgetFraction(spent: 20.0) - 1.0) < 0.001)
        #expect(abs(manager.budgetFraction(spent: 30.0) - 1.5) < 0.001)
    }

    @Test("BudgetManager status transitions from safe to warning to exceeded")
    func testBudgetStatusTransitions() {
        let manager = BudgetManager()
        manager.setDailyBudget(20.0)

        #expect(manager.status(spent: 5.0) == .safe)
        #expect(manager.status(spent: 15.0) == .safe)
        #expect(manager.status(spent: 16.0) == .warning) // 80%
        #expect(manager.status(spent: 19.5) == .warning)
        #expect(manager.status(spent: 20.0) == .exceeded) // 100%
        #expect(manager.status(spent: 25.0) == .exceeded)
    }

    @Test("BudgetManager calculates remaining headroom correctly")
    func testRemainingHeadroom() {
        let manager = BudgetManager()
        manager.setDailyBudget(25.0)

        #expect(abs(manager.remainingBudget(spent: 10.0) - 15.0) < 0.001)
        #expect(abs(manager.remainingBudget(spent: 25.0) - 0.0) < 0.001)
        #expect(abs(manager.remainingBudget(spent: 30.0) - 0.0) < 0.001) // does not return negative
    }
}
