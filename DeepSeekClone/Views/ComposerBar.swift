import SwiftUI
import Foundation
import PhotosUI
import UIKit
import AVFoundation

struct ComposerBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var attachments: [ChatAttachment]

    let isStreaming: Bool
    let modelOption: ModelOption?
    let settings: AppSettings

    var onSend: () -> Void
    var onStop: () -> Void
    var onSelectModel: () -> Void
    var onToggleThinking: () -> Void
    var onToggleWebSearch: () -> Void
    var onNewChat: () -> Void
    var onClear: () -> Void
    var onOpenSettings: () -> Void
    var onToast: (String) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isProcessing = false
    @State private var isTranscribing = false
    @State private var showCamera = false
    @StateObject private var recorder = VoiceRecorder()

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedText.isEmpty || !attachments.isEmpty
    }

    private var modelName: String {
        modelOption?.shortName ?? settings.resolvedModel.title
    }

    var body: some View {
        VStack(spacing: 8) {
            if recorder.isRecording {
                recordingRow
            } else {
                chipRow
                inputRow
                if !attachments.isEmpty {
                    attachmentRow
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            processPhoto(item)
        }
        .onChange(of: recorder.elapsed) { value in
            if value >= VoiceRecorder.maxDuration, recorder.isRecording {
                finishRecordingAndTranscribe()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onImage: { image in
                    showCamera = false
                    handleCapturedPhoto(image)
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: AttachmentService.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                processFiles(urls)
            case .failure(let error):
                onToast(error.localizedDescription)
            }
        }
    }

    // MARK: - 顶部工具 chip

    private var chipRow: some View {
        HStack(spacing: 8) {
            Button(action: onSelectModel) {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10, weight: .semibold))
                    Text(modelName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(DSTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DSTheme.accent.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            toggleChip(
                title: "深度思考",
                icon: "brain",
                active: settings.thinkingEnabled,
                action: onToggleThinking
            )

            toggleChip(
                title: "联网",
                icon: "globe",
                active: settings.webSearchEnabled,
                action: onToggleWebSearch
            )

            Spacer(minLength: 0)

            if isProcessing || isTranscribing {
                ProgressView().controlSize(.mini)
            } else if isStreaming {
                Text("正在生成…")
                    .font(.system(size: 11))
                    .foregroundStyle(DSTheme.textSecondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private func toggleChip(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(active ? DSTheme.accent : DSTheme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                active ? DSTheme.accent.opacity(0.13) : DSTheme.surfaceStrong.opacity(0.7),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 输入行

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                composerIcon("photo")
            }
            .disabled(isProcessing)

            Button {
                openCamera()
            } label: {
                composerIcon("camera")
            }
            .disabled(isProcessing || isTranscribing)

            Menu {
                Button { showFileImporter = true } label: { Label("选择文件", systemImage: "paperclip") }
                Divider()
                Button { onNewChat() } label: { Label("新建对话", systemImage: "square.and.pencil") }
                Button { onClear() } label: { Label("清空当前对话", systemImage: "trash") }
                Divider()
                Button { onOpenSettings() } label: { Label("设置", systemImage: "gearshape") }
            } label: {
                composerIcon("plus")
            }

            TextField("给 DeepSeek 发送消息", text: $text, axis: .vertical)
                .focused($isFocused)
                .font(.system(size: 16))
                .lineLimit(1...6)
                .padding(.vertical, 5)

            Button {
                startRecording()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DSTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(DSTheme.surfaceStrong.opacity(0.9), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isProcessing || isTranscribing || isStreaming)

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
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(DSTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DSTheme.hairline.opacity(0.35), lineWidth: 0.6)
        )
    }

    private func composerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DSTheme.textSecondary)
            .frame(width: 30, height: 30)
            .background(DSTheme.surfaceStrong.opacity(0.9), in: Circle())
            .contentShape(Circle())
    }

    // MARK: - 附件预览

    private var attachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 7) {
                        if let data = attachment.thumbnailData, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 30, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        } else {
                            Image(systemName: attachment.iconName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DSTheme.accent)
                                .frame(width: 30, height: 30)
                                .background(DSTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(attachment.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(attachment.badgeText)
                                .font(.system(size: 10))
                                .foregroundStyle(DSTheme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 150, alignment: .leading)

                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(DSTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .background(DSTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - 拍照

    private func openCamera() {
        guard CameraPicker.isAvailable else {
            onToast("这台设备没有可用相机（iOS 模拟器不支持拍照）")
            return
        }
        guard attachments.count < 5 else {
            onToast("最多一次附带 5 个附件")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        showCamera = true
                    } else {
                        onToast("没有相机权限：设置 → 隐私与安全性 → 相机 → 打开 DeepSeek")
                    }
                }
            }
        default:
            onToast("没有相机权限：设置 → 隐私与安全性 → 相机 → 打开 DeepSeek")
        }
    }

    private func handleCapturedPhoto(_ image: UIImage) {
        guard attachments.count < 5 else { return }
        isProcessing = true
        Task { @MainActor in
            defer { isProcessing = false }
            let name = "照片-\(attachments.count + 1).jpg"
            if let attachment = await AttachmentService.makeImageAttachment(from: image, name: name) {
                attachments.append(attachment)
                onToast("已拍照并识别文字")
            } else {
                onToast("照片处理失败")
            }
        }
    }

    // MARK: - 录音

    private var recordingRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
            Text(Self.durationText(recorder.elapsed))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(DSTheme.textPrimary)
            Text("正在录音，说完点完成")
                .font(.system(size: 12))
                .foregroundStyle(DSTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                recorder.cancel()
            } label: {
                Text("取消")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DSTheme.textSecondary)
            }
            .buttonStyle(.plain)
            Button {
                finishRecordingAndTranscribe()
            } label: {
                Text(isTranscribing ? "识别中…" : "完成")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(DSTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isTranscribing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DSTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
    }

    private func startRecording() {
        guard !isProcessing, !isTranscribing else { return }
        guard settings.hasAPIKey else {
            onToast("先在设置里填 API Key 才能语音输入")
            return
        }
        isFocused = false
        Task { @MainActor in
            let started = await recorder.start()
            if !started, let message = recorder.errorMessage {
                onToast(message)
                recorder.errorMessage = nil
            }
        }
    }

    private func finishRecordingAndTranscribe() {
        guard let data = recorder.finish() else {
            onToast("没有录到声音，请重试")
            return
        }
        isTranscribing = true
        Task { @MainActor in
            do {
                let text = try await DeepSeekClient.transcribeAudio(
                    data,
                    filename: "speech.wav",
                    apiKey: settings.apiKey,
                    baseURL: settings.baseURL
                )
                if self.text.isEmpty {
                    self.text = text
                } else {
                    self.text += "\n" + text
                }
                onToast("已转成文字")
            } catch {
                onToast((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            isTranscribing = false
        }
    }

    private static func durationText(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - 处理附件

    private func processPhoto(_ item: PhotosPickerItem) {
        guard attachments.count < 5 else {
            onToast("最多一次附带 5 个附件")
            return
        }
        isProcessing = true
        Task { @MainActor in
            defer {
                isProcessing = false
                photoItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    onToast("读取图片失败")
                    return
                }
                let name = "图片-\(attachments.count + 1).jpg"
                if let attachment = await AttachmentService.makeImageAttachment(from: image, name: name) {
                    attachments.append(attachment)
                } else {
                    onToast("图片处理失败")
                }
            } catch {
                onToast("读取图片失败：\(error.localizedDescription)")
            }
        }
    }

    private func processFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isProcessing = true
        Task { @MainActor in
            defer { isProcessing = false }
            for url in urls {
                guard attachments.count < 5 else {
                    onToast("最多一次附带 5 个附件")
                    break
                }
                do {
                    let attachment = try await AttachmentService.makeAttachment(
                        from: url,
                        apiKey: settings.apiKey,
                        baseURL: settings.baseURL
                    )
                    attachments.append(attachment)
                } catch {
                    onToast((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }
        }
    }
}
