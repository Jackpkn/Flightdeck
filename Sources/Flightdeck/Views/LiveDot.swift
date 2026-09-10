import SwiftUI

/// A glowing dot marking a panel as a live instrument, with an expanding
/// radar-ping ring — a real "recording/live" broadcast convention, driven by
/// a Core Animation implicit animation rather than a per-frame timer.
struct LiveDot: View {
    var color: Color = Theme.good
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(pulse ? 0 : 0.6), lineWidth: 1.4)
                .frame(width: pulse ? 20 : 6, height: pulse ? 20 : 6)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.85), radius: 4)
        }
        .frame(width: 20, height: 20)
        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
        .onAppear {
            pulse = true
        }
    }
}
