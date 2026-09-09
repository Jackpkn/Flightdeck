import Foundation
import Observation

/// One place that says what just happened.
///
/// A destructive action with no visible result is the worst combination: you
/// can't tell whether it worked, and you can't take it back. Every delete now
/// reports here, the banner names the item and the bytes involved, and while
/// the banner is up the move is still reversible.
@Observable
final class ActionCenter {
    enum Tone: Sendable {
        case success
        /// Refused up front. Nothing was touched.
        case blocked
        case failure
    }

    struct Banner: Identifiable {
        let id = UUID()
        let tone: Tone
        let title: String
        let detail: String?
        let receipt: TrashReceipt?
        let offersSettings: Bool
    }

    private(set) var banner: Banner?
    /// Deletes since launch, so the strip can show that things are happening
    /// even after a banner has faded.
    private(set) var deletions = 0
    private(set) var bytesReclaimed: Int64 = 0

    private var undoWork: (() -> Void)?
    private var dismissTask: Task<Void, Never>?

    /// A success banner has to outlive a glance, because it carries the undo.
    private static let successLifetime: Duration = .seconds(9)
    /// A refusal is read, not acted on in a hurry — and it should stay long
    /// enough to read the whole reason.
    private static let noticeLifetime: Duration = .seconds(11)

    /// - Parameter reload: re-reads whatever list the item came from, so an
    ///   undo puts the row back without the user hunting for a refresh button.
    func report(_ outcome: TrashOutcome, reload: @escaping () -> Void) {
        switch outcome {
        case let .moved(receipt):
            deletions += 1
            bytesReclaimed += receipt.bytes
            undoWork = reload
            show(
                Banner(
                    tone: .success,
                    title: "Moved \(receipt.name) to Trash",
                    detail: receipt.isDirectory
                        ? "Folder and everything in it"
                        : ByteCountFormatter.string(fromByteCount: receipt.bytes, countStyle: .file)
                            + " freed once the Trash is emptied",
                    receipt: receipt.canUndo ? receipt : nil,
                    offersSettings: false
                ),
                lifetime: Self.successLifetime
            )

        case let .blocked(verdict):
            undoWork = nil
            show(
                Banner(
                    tone: .blocked,
                    title: "Can't delete this — \(verdict.badge)",
                    detail: verdict.explanation,
                    receipt: nil,
                    offersSettings: verdict.settingsFix
                ),
                lifetime: Self.noticeLifetime
            )

        case let .failed(message):
            undoWork = nil
            show(
                Banner(tone: .failure, title: "Delete failed", detail: message, receipt: nil, offersSettings: false),
                lifetime: Self.noticeLifetime
            )
        }
    }

    /// Reports a refusal for an action that was never attempted — used when a
    /// row's guard is already known, so nothing touches the disk at all.
    func reportBlocked(_ verdict: FileGuard) {
        report(.blocked(verdict), reload: {})
    }

    func undo() {
        guard let receipt = banner?.receipt else { return }
        let reload = undoWork
        if let problem = TrashService.restore(receipt) {
            show(
                Banner(tone: .failure, title: "Couldn't undo", detail: problem, receipt: nil, offersSettings: false),
                lifetime: Self.noticeLifetime
            )
            return
        }
        deletions = max(0, deletions - 1)
        bytesReclaimed = max(0, bytesReclaimed - receipt.bytes)
        reload?()
        show(
            Banner(
                tone: .success,
                title: "Put \(receipt.name) back",
                detail: receipt.originalURL.deletingLastPathComponent().path,
                receipt: nil,
                offersSettings: false
            ),
            lifetime: .seconds(4)
        )
    }

    func openSettings() {
        FileGuard.openFullDiskAccessSettings()
        dismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        banner = nil
    }

    private func show(_ next: Banner, lifetime: Duration) {
        dismissTask?.cancel()
        banner = next
        let id = next.id
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled, self?.banner?.id == id else { return }
            self?.banner = nil
        }
    }
}
