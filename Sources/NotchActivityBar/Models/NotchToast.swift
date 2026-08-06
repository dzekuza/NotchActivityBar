import Foundation

struct NotchToast: Identifiable, Equatable {
    let id = UUID()
    let systemImage: String
    let title: String

    static let screenshotSaved = NotchToast(systemImage: "camera.fill", title: "Screenshot saved")
    static let clipboardCopied = NotchToast(systemImage: "doc.on.clipboard.fill", title: "Copied to clipboard")
}
