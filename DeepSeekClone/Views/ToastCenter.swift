import SwiftUI

/// 轻量提示条（复制成功、已新建对话等）。
@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var message: String?

    private var workItem: DispatchWorkItem?

    func show(_ text: String) {
        message = text
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.2)) {
                self?.message = nil
            }
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: item)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.black.opacity(0.78), in: Capsule())
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
