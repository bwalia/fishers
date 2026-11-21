import SwiftUI
import UIKit

/// System share sheet so a live scoreboard URL can go to WhatsApp, Mail,
/// Messages, and anything else the person already has installed.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// Left out of the sheet — Copy, for bank details, so the account number
    /// only ever reaches the pasteboard through the pay screen's own
    /// local-only, expiring copy.
    var excluded: [UIActivity.ActivityType] = []
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excluded
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
