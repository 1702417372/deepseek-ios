import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isLastAssistant: Bool
    let fontScale: CGFloat

    var onCopy: () -> Void
    var onDelete: () -> Void
    var onRegenerate: () -> Void

    private var textSize: CGFloat { 16 * fontScale }
    private var smallSize: CGFloat { 13 * fontScale }

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBlock
        }
    }

    // MARK: - 用户

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let attachments = message.attachments, !attachments.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(attachments) { attachment in
                        attachmentChip(attachment)
                    }
                }
            }
            if !message.content.isEmpty {
                HStack(spacing: 0) {
                    Spacer(minLength: 52)
                    Text(message.content)
                        .font(.system(size: textSize))
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
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contextMenu {
            if !message.content.isEmpty {
                Button { onCopy() } label: { Label("复制", systemImage: "doc.on.doc") }
            }
            Button(role: .destructive) { onDelete() } label: { Label("删除这条消息", systemImage: "trash") }
        }
    }

    private func attachmentChip(_ attachment: ChatAttachment) -> some View {
        HStack(spacing: 7) {
            if let data = attachment.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: attachment.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DSTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(DSTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DSTheme.textPrimary)
                    .lineLimit(1)
                Text(attachment.badgeText)
                    .font(.system(size: 10))
                    .foregroundStyle(DSTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(6)
        .background(DSTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - AI

    private var assistantBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            AssistantAvatar(size: 26)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                if let reasoning = message.reasoning, !reasoning.isEmpty {
                    ReasoningBlock(text: reasoning, isThinking: isStreaming && message.content.isEmpty)
                }

                if let queries = message.searchQueries, !queries.isEmpty, isStreaming,
                   (message.sources ?? []).isEmpty, message.content.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在联网搜索：\(queries.prefix(2).joined(separator: " · "))")
                            .font(.system(size: smallSize))
                            .foregroundStyle(DSTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                }

                if message.isRefused {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield")
                            .foregroundStyle(.orange)
                        Text(message.refusalText ?? "内容被安全策略拦截，请换一种说法再试。")
                            .font(.system(size: smallSize))
                            .foregroundStyle(DSTheme.textSecondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if message.content.isEmpty {
                    if isStreaming {
                        TypingIndicator()
                            .padding(.vertical, 6)
                    }
                } else {
                    MarkdownText(content: message.content, fontSize: textSize)
                }

                if let sources = message.sources, !sources.isEmpty {
                    SourcesCard(sources: sources, fontSize: smallSize)
                }

                if let citations = message.citations, !citations.isEmpty {
                    citationRow(citations)
                }

                if !isStreaming, !message.content.isEmpty {
                    actionRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            if !message.content.isEmpty {
                Button { onCopy() } label: { Label("复制", systemImage: "doc.on.doc") }
            }
            if isLastAssistant {
                Button { onRegenerate() } label: { Label("重新生成", systemImage: "arrow.clockwise") }
            }
            Button(role: .destructive) { onDelete() } label: { Label("删除这条消息", systemImage: "trash") }
        }
    }

    private func citationRow(_ citations: [Citation]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                Text("引用来源")
                    .font(.system(size: smallSize - 1, weight: .medium))
            }
            .foregroundStyle(DSTheme.textSecondary)

            ForEach(Array(citations.prefix(6).enumerated()), id: \.element.id) { index, citation in
                if let url = URL(string: citation.url) {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            Text("[\(index + 1)]")
                                .font(.system(size: smallSize - 1, weight: .semibold))
                            Text(citation.title)
                                .font(.system(size: smallSize - 1))
                                .lineLimit(1)
                        }
                        .foregroundStyle(DSTheme.accent)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: smallSize))
        .foregroundStyle(DSTheme.textSecondary)
        .buttonStyle(.plain)
        .padding(.top, 1)
    }
}

/// 联网搜索的来源卡片。
struct SourcesCard: View {
    let sources: [SearchSource]
    let fontSize: CGFloat

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .semibold))
                    Text("联网搜索 · \(sources.count) 条来源")
                        .font(.system(size: fontSize, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DSTheme.textSecondary)
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(Array(sources.prefix(10).enumerated()), id: \.element.id) { index, source in
                    if let url = URL(string: source.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). \(source.title)")
                                    .font(.system(size: fontSize, weight: .medium))
                                    .foregroundStyle(DSTheme.textPrimary)
                                    .lineLimit(2)
                                if let site = source.siteName, !site.isEmpty {
                                    Text(site)
                                        .font(.system(size: fontSize - 1))
                                        .foregroundStyle(DSTheme.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSTheme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
