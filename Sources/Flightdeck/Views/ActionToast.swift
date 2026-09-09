import SwiftUI

/// Window-level confirmation for destructive actions. Slides up from the
/// bottom, names what happened, and — while it's still up — offers the way
/// back.
///
/// Deliberately not a modal "are you sure?" in front of the click. A
/// confirmation dialog costs something on every delete, including the hundreds
/// that were exactly what you meant; an undo costs nothing until you need it.
struct ActionToast: View {
    let banner: ActionCenter.Banner
    let onUndo: () -> Void
    let onSettings: () -> Void
    let onDismiss: () -> Void

    @State private var entered = false
    /// Drives the one-shot ring that expands out of the icon on arrival.
    @State private var pinged = false

    private var accent: Color {
        switch banner.tone {
        case .success: return Theme.good
        case .blocked: return Theme.warning
        case .failure: return Theme.critical
        }
    }

    private var symbol: String {
        switch banner.tone {
        case .success: return "checkmark.circle.fill"
        case .blocked: return "lock.shield.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(pinged ? 0 : 0.7), lineWidth: 1.5)
                    .scaleEffect(pinged ? 2.4 : 1)
                    .animation(.easeOut(duration: 0.7), value: pinged)
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.9), radius: 8)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(banner.title)
                    .font(Theme.ui(12.5, weight: .semibold))
                    .foregroundStyle(Theme.ink1)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = banner.detail {
                    Text(detail)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if banner.receipt != nil {
                    action("UNDO", tint: accent, filled: true, onUndo)
                        .keyboardShortcut("z", modifiers: .command)
                }
                if banner.offersSettings {
                    action("OPEN SETTINGS", tint: Theme.warning, filled: true, onSettings)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink3)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.raised)
                RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.45), lineWidth: 1)
                // A single lit edge, so the tone reads before the words do.
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.16), .clear],
                            startPoint: .leading,
                            endPoint: .center
                        )
                    )
            }
        )
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
        .shadow(color: accent.opacity(0.22), radius: 16)
        .padding(.bottom, 26)
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 22)
        .scaleEffect(entered ? 1 : 0.97)
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.76)) { entered = true }
            pinged = true
        }
    }

    private func action(
        _ label: String,
        tint: Color,
        filled: Bool,
        _ perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Text(label)
                .font(Theme.mono(9.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(tint.opacity(filled ? 0.18 : 0), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5).stroke(tint.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
