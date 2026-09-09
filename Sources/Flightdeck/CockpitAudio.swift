import AppKit
import Foundation

/// Subtle audio cues for Cockpit interactions (sonar pings, alerts, and tool triggers).
public enum CockpitAudio {
    public static var isSoundEnabled: Bool = true

    public static func playPing() {
        guard isSoundEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    public static func playAlert() {
        guard isSoundEnabled else { return }
        NSSound(named: "Basso")?.play()
    }

    public static func playSuccess() {
        guard isSoundEnabled else { return }
        NSSound(named: "Pop")?.play()
    }
}
