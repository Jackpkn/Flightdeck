import SwiftUI

/// "View on GitHub" pill. Its own view so the nested button label does not
/// land inside a parent card's ViewBuilder, where it type-checks slowly.
struct GitHubLinkButton: View {
    let url: URL
    var title: String = "VIEW ON GITHUB"
    var tint: Color = .purple

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            label
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
    }

    private var label: some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "arrow.up.right")
        }
        .font(Theme.mono(10.5, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tint.opacity(0.4), lineWidth: 1))
    }
}
