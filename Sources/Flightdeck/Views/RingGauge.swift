import SwiftUI

/// A radial percentage dial — real telemetry software (drone/flight
/// controllers) favors these over linear bars for a single 0-100 reading.
/// `showTicks` draws a fixed ring of minor/major tick marks outside the arc
/// (Canvas + trig, not a rotated-view hack) and `centerLabel` turns it into
/// a hero instrument with the number burned into the middle of the dial.
struct RingGauge: View {
    let fraction: Double
    var color: Color = Theme.claudeColor
    var lineWidth: CGFloat = 3.5
    var diameter: CGFloat = 28
    var showTicks: Bool = false
    var centerLabel: String? = nil

    private var ringInset: CGFloat { showTicks ? 8 : 0 }

    var body: some View {
        ZStack {
            if showTicks {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = size.width / 2
                    for i in 0..<24 {
                        let angle = Double(i) / 24 * 2 * .pi - .pi / 2
                        let isMajor = i % 6 == 0
                        let outer = radius
                        let inner = radius - (isMajor ? 6 : 3)
                        var path = Path()
                        path.move(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
                        path.addLine(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
                        context.stroke(path, with: .color(Theme.ink3.opacity(isMajor ? 0.6 : 0.35)), lineWidth: isMajor ? 1.4 : 1)
                    }
                }
            }
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
                .padding(ringInset)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.75), radius: 5)
                .padding(ringInset)
            if let centerLabel {
                Text(centerLabel)
                    .font(Theme.mono(diameter * 0.22, weight: .bold))
                    .foregroundStyle(Theme.ink1)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
