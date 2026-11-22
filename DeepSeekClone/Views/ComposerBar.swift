import SwiftUI

struct ComposerBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let isStreaming: Bool
    let model: DeepSeekModel

    var onSend: () -> Void
    var onStop: () -> Void
    var onSelectModel: (DeepSeekModel) -> Void
    var onNewChat: () -> Void
    var onClear: () -> Void
    var onOpenSettings: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(DeepSeekModel.allCases) { option in
                        Button {
                            onSelectModel(option)
                        } label: {
                            Label("\(option.title) · \(option.subtitle)", systemImage: option.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(model.title)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(DSTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DSTheme.accent.opacity(0.12), in: Capsule())
                }

                Spacer(minLength: 0)

                if isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在生成…")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(DSTheme.textSecondary)
                }
            }
            .padding(.horizontal, 4)

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button {
                        onNewChat()
                    } label: {
                        Label("新建对话", systemImage: "square.and.pencil")
                    }
                    Button {
                        onClear()
                    } label: {
                        Label("清空当前对话", systemImage: "trash")
                    }
                    Divider()
                    Button {
                        onOpenSettings()
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DSTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(DSTheme.surfaceStrong.opacity(0.9), in: Circle())
                }

                TextField("给 DeepSeek 发送消息", text: $text, axis: .vertical)
                    .focused($isFocused)
                    .font(.system(size: 16))
                    .lineLimit(1...6)
                    .padding(.vertical, 5)

                Button {
                    if isStreaming {
                        onStop()
                    } else {
                        onSend()
                    }
                } label: {
                    Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            (isStreaming || canSend) ? DSTheme.accent : Color.gray.opacity(0.35),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isStreaming && !canSend)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DSTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(DSTheme.hairline.opacity(0.35), lineWidth: 0.6)
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }
}
