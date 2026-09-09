import SwiftUI

/// Four L-shaped tick marks at a panel's corners — a viewfinder/reticle frame,
/// layered over the existing glass panel rather than replacing it.
private struct CornerBracketOverlay: View {
    var color: Color
    var length: CGFloat = 18
    var thickness: CGFloat = 1.8
    var inset: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                bracket(at: CGPoint(x: inset, y: inset), dx: 1, dy: 1)
                bracket(at: CGPoint(x: w - inset, y: inset), dx: -1, dy: 1)
                bracket(at: CGPoint(x: inset, y: h - inset), dx: 1, dy: -1)
                bracket(at: CGPoint(x: w - inset, y: h - inset), dx: -1, dy: -1)
            }
        }
        .allowsHitTesting(false)
    }

    private func bracket(at point: CGPoint, dx: CGFloat, dy: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: point.x, y: point.y + length * dy))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x + length * dx, y: point.y))
        }
        .stroke(color.opacity(0.9), lineWidth: thickness)
        .shadow(color: color.opacity(0.7), radius: 3)
    }
}

extension View {
    func cornerBracket(color: Color) -> some View {
        overlay(CornerBracketOverlay(color: color))
    }
}
