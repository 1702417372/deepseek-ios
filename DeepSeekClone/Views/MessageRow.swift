import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isLastAssistant: Bool
    var onCopy: () -> Void
    var onRegenerate: () -> Void

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBlock
        }
    }

    private var userBubble: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 52)
            Text(message.content)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [DSTheme.accent, DSTheme.accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: DSTheme.bubbleRadius, style: .continuous)
                )
        }
    }

    private var assistantBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            AssistantAvatar(size: 26)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                if let reasoning = message.reasoning, !reasoning.isEmpty {
                    ReasoningBlock(text: reasoning, isThinking: isStreaming && message.content.isEmpty)
                }

                if message.content.isEmpty {
                    if isStreaming {
                        TypingIndicator()
                            .padding(.vertical, 6)
                    }
                } else {
                    MarkdownText(content: message.content)
                }

                if !isStreaming, !message.content.isEmpty {
                    actionRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 20) {
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            if isLastAssistant {
                Button(action: onRegenerate) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(DSTheme.textSecondary)
        .buttonStyle(.plain)
        .padding(.top, 1)
    }
}

/// 推理模型的思维链折叠块。
struct ReasoningBlock: View {
    let text: String
    let isThinking: Bool

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isThinking ? "正在深度思考…" : "已深度思考")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .foregroundStyle(DSTheme.textSecondary)
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(DSTheme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSTheme.surfaceStrong.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 等待首个 token 时的三点动画。
struct TypingIndicator: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
            let tick = Int(timeline.date.timeIntervalSince1970 * 2.5) % 3
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DSTheme.textSecondary.opacity(index == tick ? 0.9 : 0.3))
                        .frame(width: 6, height: 6)
                        .scaleEffect(index == tick ? 1.25 : 0.9)
                }
            }
        }
    }
}
