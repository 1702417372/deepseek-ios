import SwiftUI

/// 轻量提示条（复制成功、已新建对话等）。
@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var message: String?

    private var hideTask: Task<Void, Never>?

    func show(_ text: String) {
        message = text
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self?.message = nil
            }
        }
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
