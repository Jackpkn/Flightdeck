import Foundation
import IOKit.pwr_mgt

/// Manages macOS power assertions to prevent idle sleep (Caffeine/Amphetamine mode).
/// Safe, native, and releases immediately on toggle or application termination.
@Observable
public final class SleepPreventer {
    public static let shared = SleepPreventer()

    public private(set) var isAwake: Bool = false
    private var assertionID: IOPMAssertionID = 0

    public init() {}

    deinit {
        deactivate()
    }

    public func toggle() {
        if isAwake {
            deactivate()
        } else {
            activate()
        }
    }

    public func activate() {
        guard !isAwake else { return }
        let reason = "Flightdeck Keep Awake active" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isAwake = true
        }
    }

    public func deactivate() {
        guard isAwake else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isAwake = false
    }
}
