import SwiftUI

/// Cyberpunk shimmering skeleton bar for initial panel data loading.
public struct SkeletonBar: View {
    let height: CGFloat
    let width: CGFloat?

    @State private var phase: CGFloat = -1

    public init(width: CGFloat? = nil, height: CGFloat = 14) {
        self.width = width
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            let w = width ?? geo.size.width
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.track.opacity(0.6))
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Theme.accent.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .init(x: phase - 0.3, y: 0.5),
                        endPoint: .init(x: phase + 0.3, y: 0.5)
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: w, height: height)
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 2.0
            }
        }
    }
}
