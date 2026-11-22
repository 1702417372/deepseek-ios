import SwiftUI
import UIKit

struct MarkdownBlock: Identifiable {
    enum Kind {
        case text(String)
        case code(language: String, code: String)
    }
    /// 用下标作为身份，流式重算时 SwiftUI 才能复用已有视图。
    let id: Int
    let kind: Kind
}

/// 轻量 Markdown：代码块单独渲染，其余行内语法交给 AttributedString。
enum MarkdownParser {
    private static let fence = String(repeating: "\u{0060}", count: 3)

    static func blocks(from content: String) -> [MarkdownBlock] {
        guard !content.isEmpty else { return [] }
        var blocks: [MarkdownBlock] = []
        var textBuffer = ""
        var codeBuffer = ""
        var language = ""
        var inCode = false

        let lines = content.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix(fence) {
                if inCode {
                    blocks.append(MarkdownBlock(id: blocks.count, kind: .code(language: language, code: codeBuffer)))
                    codeBuffer = ""
                    language = ""
                    inCode = false
                } else {
                    flushText(&textBuffer, into: &blocks)
                    inCode = true
                    language = String(line.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if inCode {
                codeBuffer += line + "\n"
            } else {
                textBuffer += line + "\n"
            }
        }

        if inCode, !codeBuffer.isEmpty {
            blocks.append(MarkdownBlock(id: blocks.count, kind: .code(language: language, code: codeBuffer)))
        }
        flushText(&textBuffer, into: &blocks)
        if blocks.isEmpty {
            blocks.append(MarkdownBlock(id: blocks.count, kind: .text(content)))
        }
        return blocks
    }

    private static func flushText(_ buffer: inout String, into blocks: inout [MarkdownBlock]) {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            blocks.append(MarkdownBlock(id: blocks.count, kind: .text(trimmed)))
        }
        buffer = ""
    }

    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return attributed
        }
        return AttributedString(text)
    }
}

struct MarkdownText: View {
    let content: String
    var fontSize: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkdownParser.blocks(from: content)) { block in
                switch block.kind {
                case .text(let text):
                    Text(MarkdownParser.attributed(text))
                        .font(.system(size: fontSize))
                        .lineSpacing(4)
                        .foregroundStyle(DSTheme.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code, fontSize: max(11, fontSize - 3))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    var fontSize: CGFloat = 13

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "代码" : language)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DSTheme.textSecondary)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "已复制" : "复制")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DSTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle()
                .fill(DSTheme.hairline.opacity(0.4))
                .frame(height: 0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(DSTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DSTheme.hairline.opacity(0.3), lineWidth: 0.6)
        )
    }
}
