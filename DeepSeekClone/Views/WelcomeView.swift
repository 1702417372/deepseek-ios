import SwiftUI

/// 首页欢迎区：只保留鲸鱼和一句问候（对齐官方 App）。
struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 44)

            AssistantAvatar(size: 66)

            Text("欢迎回来，随时开始吧")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(DSTheme.textPrimary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }
}
