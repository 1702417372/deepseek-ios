import SwiftUI

struct WelcomeView: View {
    var onPick: (String) -> Void

    private struct Suggestion: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
    }

    private let suggestions: [Suggestion] = [
        Suggestion(title: "帮我写一封求职邮件", icon: "envelope.fill"),
        Suggestion(title: "用通俗的语言解释量子纠缠", icon: "atom"),
        Suggestion(title: "用 SwiftUI 写一个待办清单 App", icon: "chevron.left.forwardslash.chevron.right"),
        Suggestion(title: "如何在一个月内提高英语口语？", icon: "text.bubble.fill")
    ]

    var body: some View {
        VStack(spacing: 24) {
            AssistantAvatar(size: 64)
                .padding(.top, 28)

            VStack(spacing: 10) {
                Text("我是 DeepSeek，很高兴见到你！")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DSTheme.textPrimary)

                Text("我可以帮你写代码、写作、分析问题，也可以陪你聊聊天。把任务交给我吧～")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DSTheme.textSecondary)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(suggestions) { suggestion in
                    Button {
                        onPick(suggestion.title)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DSTheme.accent)
                            Text(suggestion.title)
                                .font(.system(size: 14, weight: .medium))
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(DSTheme.textPrimary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                        .padding(12)
                        .background(
                            DSTheme.surface,
                            in: RoundedRectangle(cornerRadius: DSTheme.cardRadius, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
