import SwiftUI
import UIKit

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIActivityViewController 的 SwiftUI 包装。
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
