import Testing
import Foundation
@testable import Flightdeck

@Suite("HardwareVitalsTests")
struct HardwareVitalsTests {
    @Test("Battery status is queryable and returns valid metrics")
    func batteryStatus() {
        let battery = HardwareVitals.fetchBattery()
        if battery.hasBattery {
            #expect(battery.percent >= 0 && battery.percent <= 100)
            if let health = battery.healthPercent {
                #expect(health >= 0 && health <= 100)
            }
            if let cycles = battery.cycleCount {
                #expect(cycles >= 0)
            }
        } else {
            #expect(battery.percent == 100)
            #expect(battery.isPluggedIn == true)
        }
        #expect(!battery.statusDescription.isEmpty)
    }

    @Test("Swap status returns non-negative memory values")
    func swapStatus() {
        let swap = HardwareVitals.fetchSwap()
        #expect(swap.usedBytes >= 0)
        #expect(swap.totalBytes >= 0)
        #expect(!swap.pressureLevel.isEmpty)
    }

    @Test("Chip info identifies active cores and valid uptime")
    func chipInfo() {
        let chip = HardwareVitals.fetchChip()
        #expect(!chip.name.isEmpty)
        #expect(chip.cores > 0)
        #expect(!chip.uptimeString.isEmpty)
    }

    @Test("Network vitals return valid interface and IP string")
    func networkVitals() {
        let network = HardwareVitals.fetchNetwork()
        #expect(!network.interface.isEmpty)
        #expect(!network.ipAddress.isEmpty)
    }

    @Test("Uptime formatter formats seconds correctly")
    func uptimeFormatter() {
        let minutesOnly = HardwareVitals.formatUptime(180) // 3m
        #expect(minutesOnly == "3m")

        let hoursAndMinutes = HardwareVitals.formatUptime(3720) // 1h 2m
        #expect(hoursAndMinutes == "1h 2m")

        let daysAndHours = HardwareVitals.formatUptime(90000) // 1d 1h
        #expect(daysAndHours == "1d 1h")
    }
}
