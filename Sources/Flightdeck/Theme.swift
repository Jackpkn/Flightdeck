import SwiftUI

/// Color tokens ported from the Flightdeck web mockup — same palette,
/// validated for CVD-safety against this exact dark surface.
/// "Cockpit" direction — void black + neon glow. Chosen deliberately over the
/// Raycast (neutral gray) direction; do not drift back without that being an
/// explicit, separate decision.
enum Theme {
    static let page      = Color(hex: 0x050508) // void black
    static let panel     = Color(hex: 0x0c0c12)
    static let raised    = Color(hex: 0x15151d)
    static let track     = Color(hex: 0x1c1c26)
    static let hairline  = Color.white.opacity(0.08)
    static let hairline2 = Color.white.opacity(0.05)

    static let ink1 = Color(hex: 0xf0f2f5)
    static let ink2 = Color(hex: 0x9aa3ad)
    static let ink3 = Color(hex: 0x5c6570)

    /// Brand / interactive accent — the cockpit's signature cyan glow.
    static let accent = Color(hex: 0x00f0ff)
    /// Paired with `accent` only for the active-card edge gradient (cyan → purple).
    static let accentSecondary = Color(hex: 0xb026ff)

    /// Fixed categorical order, one per known agent source — kept distinct from
    /// the cyan accent and from the amber/red status colors.
    static let claudeColor  = Color(hex: 0x00f0ff) // cyan
    static let cursorColor  = Color(hex: 0xb026ff) // purple
    static let copilotColor = Color(hex: 0x39ff88) // neon green
    static let gpuColor     = Color(hex: 0xff2a85) // neon magenta/pink

    private static let projectPalette = [claudeColor, cursorColor, copilotColor]

    /// All real data today comes from a single agent (Claude Code) across many
    /// projects — so identity that matters is the PROJECT, not an arbitrary
    /// position in an array. Same project always gets the same color, everywhere.
    static func colorForProject(_ name: String) -> Color {
        projectPalette[abs(name.hashValue) % projectPalette.count]
    }

    /// An ordered cyan-to-purple ramp for composition charts. Slices are
    /// sorted by size, so the ramp encodes magnitude rather than acting as a
    /// categorical palette — and it stays clear of the reserved status colors.
    static let sizeRamp: [Color] = [
        Color(hex: 0x00f0ff),
        Color(hex: 0x35c8ff),
        Color(hex: 0x5fa3ff),
        Color(hex: 0x7f7cff),
        Color(hex: 0x9a52ff),
        Color(hex: 0xb026ff),
    ]

    static let good     = copilotColor
    static let warning  = Color(hex: 0xffb800) // amber — cost/budget semantics
    static let critical = Color(hex: 0xff3b3b)

    /// Real bundled Inter / JetBrains Mono (registered by FontLoader at launch) —
    /// falls back to the system sans/mono if registration ever fails.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }
    /// Blocky technical display face for section titles/labels only —
    /// JetBrains Mono stays reserved for the actual data readouts.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("Orbitron", size: size).weight(weight)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }
}

/// Real macOS vibrancy (blur + translucency) tinted with the panel color,
/// instead of a flat fill — this is the one texture every card in the app shares.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 12
    var accent: Color? = nil

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.panel.opacity(0.35),
                                    Theme.panel.opacity(0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    if let accent {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(accent.opacity(0.025))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                (accent ?? Color.white).opacity(0.32),
                                (accent ?? Color.white).opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// `accent` tints the panel's border with an instrument's identity color —
    /// leave nil for the neutral hairline every non-instrument panel uses.
    func glassPanel(cornerRadius: CGFloat = 12, accent: Color? = nil) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, accent: accent))
    }
}
