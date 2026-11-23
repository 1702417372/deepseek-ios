import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var conversationStore: ConversationStore
    @EnvironmentObject private var catalog: ModelCatalog
    @EnvironmentObject private var sync: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var draft = AppSettings()
    @State private var loaded = false
    @State private var revealKey = false
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testFailed = false
    @State private var confirmClear = false
    @State private var isRefreshingModels = false
    @State private var shareItem: ShareItem?
    @State private var importStatus: String?
    @State private var showImporter = false
    @State private var isSyncing = false
    @State private var syncStatus: String?

    private var thinkingLocksSampling: Bool {
        draft.thinkingEnabled || draft.webSearchEnabled || draft.safetyCheckEnabled || draft.autoTitleEnabled
    }

    var body: some View {
        NavigationStack {
            Form {
                apiSection
                modelSection
                thinkingSection
                capabilitySection
                generationSection
                personalizationSection
                voiceSection
                dataSection
                syncSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("清空全部对话？", isPresented: $confirmClear) {
                Button("清空", role: .destructive) {
                    conversationStore.deleteAll()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("清空后无法恢复。API Key 与其它设置不会被删除。")
            }
            .onAppear {
                if !loaded {
                    draft = settingsStore.settings
                    loaded = true
                }
            }
            .onDisappear { save() }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
            }
            .task {
                if catalog.options.isEmpty {
                    await catalog.refresh(apiKey: draft.apiKey, baseURL: draft.baseURL)
                }
            }
        }
    }

    // MARK: - Sections

    private var apiSection: some View {
        Section {
            HStack(spacing: 8) {
                if revealKey {
                    TextField("sk-...", text: $draft.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("sk-...", text: $draft.apiKey)
                }
                Button {
                    revealKey.toggle()
                } label: {
                    Image(systemName: revealKey ? "eye.slash" : "eye")
                        .foregroundStyle(DSTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            TextField("https://api.deepseek.com", text: $draft.baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            Button {
                testConnection()
            } label: {
                HStack {
                    Text(isTesting ? "正在测试…" : "测试连接")
                    Spacer()
                    if isTesting {
                        ProgressView()
                    }
                }
            }
            .disabled(isTesting || draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("API 配置")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let testMessage {
                    Text(testMessage)
                        .foregroundStyle(testFailed ? .red : .green)
                }
                Text("API Key 只保存在本机钥匙串，不会上传到第三方服务器。可在 platform.deepseek.com 创建。")
            }
        }
    }

    private var modelSection: some View {
        Section {
            ForEach(catalog.options) { option in
                Button {
                    draft.model = option.id
                    if let effort = option.defaultEffort {
                        draft.reasoningEffort = effort
                    }
                    if option.id == "deepseek-v4-pro" {
                        draft.webSearchEnabled = false
                        draft.readURLEnabled = false
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.shortName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DSTheme.textPrimary)
                            Text(option.capabilityText)
                                .font(.system(size: 11))
                                .foregroundStyle(DSTheme.textSecondary)
                        }
                        Spacer()
                        if draft.model == option.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DSTheme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("模型 ID")
                Spacer()
                TextField("deepseek-flash", text: $draft.model)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(DSTheme.textSecondary)
            }

            Button {
                refreshModels()
            } label: {
                HStack {
                    Text("刷新模型列表")
                    Spacer()
                    if isRefreshingModels {
                        ProgressView()
                    } else if let updated = catalog.lastUpdated {
                        Text(DSTheme.dateString(updated))
                            .font(.system(size: 12))
                            .foregroundStyle(DSTheme.textSecondary)
                    }
                }
            }
            .disabled(isRefreshingModels)
        } header: {
            Text("模型")
        } footer: {
            if let error = catalog.errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                Text("列表来自 GET /models；只有 DeepSeek-V4.1-Flash 支持图片与联网工具。")
            }
        }
    }

    private var thinkingSection: some View {
        Section {
            Toggle("深度思考", isOn: $draft.thinkingEnabled)
            if draft.thinkingEnabled {
                Picker("思考强度", selection: $draft.reasoningEffort) {
                    Text("低").tag("low")
                    Text("高").tag("high")
                    Text("极高").tag("max")
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("思考模式")
        } footer: {
            Text("思考模式下 temperature 不生效；强度越高越慢、越贵，但推理更充分。")
        }
    }

    private var capabilitySection: some View {
        Section {
            Toggle("联网搜索", isOn: $draft.webSearchEnabled)
            Toggle("阅读链接", isOn: $draft.readURLEnabled)
        } header: {
            Text("联网能力")
        } footer: {
            Text("由服务端执行检索与抓取；开启后 temperature 等采样参数由服务端决定。")
        }
    }

    private var generationSection: some View {
        Section {
            Toggle("自动生成会话标题", isOn: $draft.autoTitleEnabled)
            Toggle("内容安全校验", isOn: $draft.safetyCheckEnabled)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("温度")
                    Spacer()
                    Text(String(format: "%.1f", draft.temperature))
                        .foregroundStyle(DSTheme.textSecondary)
                }
                Slider(value: $draft.temperature, in: 0...2, step: 0.1)
                    .disabled(thinkingLocksSampling)
                if thinkingLocksSampling {
                    Text("当前配置下服务端会忽略温度")
                        .font(.system(size: 11))
                        .foregroundStyle(DSTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("上下文上限")
                    Spacer()
                    Text("\(draft.contextCharacterLimit / 1000)K 字")
                        .foregroundStyle(DSTheme.textSecondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(draft.contextCharacterLimit) },
                        set: { draft.contextCharacterLimit = Int($0) }
                    ),
                    in: 20000...200000,
                    step: 20000
                )
            }
        } header: {
            Text("生成")
        }
    }

    private var personalizationSection: some View {
        Section {
            Picker("消息字号", selection: $draft.fontScale) {
                Text("小").tag(0.9)
                Text("标准").tag(1.0)
                Text("大").tag(1.15)
                Text("特大").tag(1.3)
            }
            .pickerStyle(.segmented)

            TextEditor(text: $draft.systemPrompt)
                .frame(minHeight: 88)
        } header: {
            Text("个性化")
        } footer: {
            Text("系统提示词会作为 system 消息加在每次请求最前面。")
        }
    }

    private var voiceSection: some View {
        Section {
            Picker("朗读音色", selection: $draft.ttsVoice) {
                Text("女声 · stella").tag("stella")
                Text("男声 · tide").tag("tide")
            }
            Toggle("回答生成后自动朗读", isOn: $draft.autoReadAnswers)
        } header: {
            Text("语音")
        } footer: {
            Text("每条回答下方的「朗读」按钮会用这个音色合成语音；输入框的麦克风按钮把录音转成文字（ASR）。")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                exportAll()
            } label: {
                HStack {
                    Label("导出全部对话（JSON）", systemImage: "square.and.arrow.up")
                    Spacer()
                    Text("\(conversationStore.all.count) 个会话")
                        .font(.system(size: 12))
                        .foregroundStyle(DSTheme.textSecondary)
                }
            }

            Button {
                showImporter = true
            } label: {
                Label("导入对话文件", systemImage: "square.and.arrow.down")
            }

            if let importStatus {
                Text(importStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(DSTheme.textSecondary)
            }

            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Text("清空全部对话")
            }
        } header: {
            Text("数据")
        } footer: {
            Text("导出的 JSON 与网页版通用；也能导入 {title, messages} 结构的第三方历史或 Markdown 文本，按会话 id 合并。")
        }
    }

    private var syncSection: some View {
        Section {
            TextField("同步地址（https://…）", text: $draft.syncURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            SecureField("同步密钥", text: $draft.syncKey)
            Toggle("启动时自动同步", isOn: $draft.autoSyncEnabled)

            HStack(spacing: 12) {
                Button("上传") { syncUpload() }
                Button("下载") { syncDownload() }
                Button("双向同步") { syncBoth() }
                Spacer()
                if isSyncing {
                    ProgressView().controlSize(.mini)
                }
            }
            .disabled(isSyncing)

            if let syncStatus {
                Text(syncStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(DSTheme.textSecondary)
            } else if let last = sync.lastSyncDate {
                Text("上次同步：\(DSTheme.dateString(last))")
                    .font(.system(size: 12))
                    .foregroundStyle(DSTheme.textSecondary)
            }
        } header: {
            Text("多端同步")
        } footer: {
            Text("配合自建同步服务使用（仓库里的 docs/sync-worker.js，部署到 Cloudflare Workers，免费）。App 与网页版共用同一份 JSON 和 X-Sync-Key 协议。")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text("1.5.0").foregroundStyle(DSTheme.textSecondary)
            }
            HStack {
                Text("接口")
                Spacer()
                Text("DeepSeek Chat Completions").foregroundStyle(DSTheme.textSecondary)
            }
            HStack {
                Text("说明")
                Spacer()
                Text("非官方客户端").foregroundStyle(DSTheme.textSecondary)
            }
        } header: {
            Text("关于")
        } footer: {
            Text("本项目是第三方学习示例，与 DeepSeek 官方无关。API 费用由你自己的账号承担。")
        }
    }

    // MARK: - Actions

    private func save() {
        guard loaded else { return }
        var value = draft
        value.apiKey = value.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = value.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        value.baseURL = url.isEmpty ? "https://api.deepseek.com" : url
        value.fontScale = min(max(value.fontScale, 0.8), 1.5)
        settingsStore.settings = value
    }

    private func exportAll() {
        do {
            let data = try ConversationArchive.exportData(conversationStore.all)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(ConversationArchive.suggestedFileName())
            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
            importStatus = "已生成导出文件，选择「存储到文件」或分享即可"
        } catch {
            importStatus = "导出失败：\(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importStatus = "导入失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let incoming = try ConversationArchive.decode(data)
                let merged = ConversationArchive.merge(incoming, into: conversationStore.all)
                conversationStore.replaceAll(merged)
                importStatus = "已导入 \(incoming.count) 个会话（当前共 \(merged.count) 个）"
            } catch {
                importStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func syncUpload() {
        save()
        let url = draft.syncURL
        let key = draft.syncKey
        guard SyncService.isReady(urlString: url, key: key) else {
            syncStatus = "请先填写 https:// 开头的同步地址和同步密钥"
            return
        }
        isSyncing = true
        syncStatus = nil
        Task { @MainActor in
            do {
                try await sync.push(conversationStore.all, urlString: url, key: key)
                syncStatus = "已上传 \(conversationStore.all.count) 个会话"
            } catch {
                syncStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSyncing = false
        }
    }

    private func syncDownload() {
        save()
        let url = draft.syncURL
        let key = draft.syncKey
        guard SyncService.isReady(urlString: url, key: key) else {
            syncStatus = "请先填写 https:// 开头的同步地址和同步密钥"
            return
        }
        isSyncing = true
        syncStatus = nil
        Task { @MainActor in
            do {
                let remote = try await sync.pull(urlString: url, key: key)
                let merged = ConversationArchive.merge(remote, into: conversationStore.all)
                conversationStore.replaceAll(merged)
                syncStatus = "已下载 \(remote.count) 个会话（合并后共 \(merged.count) 个）"
            } catch {
                syncStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSyncing = false
        }
    }

    private func syncBoth() {
        save()
        let url = draft.syncURL
        let key = draft.syncKey
        guard SyncService.isReady(urlString: url, key: key) else {
            syncStatus = "请先填写 https:// 开头的同步地址和同步密钥"
            return
        }
        isSyncing = true
        syncStatus = nil
        Task { @MainActor in
            do {
                let merged = try await sync.syncBoth(local: conversationStore.all, urlString: url, key: key)
                conversationStore.replaceAll(merged)
                syncStatus = "双向同步完成，当前共 \(merged.count) 个会话"
            } catch {
                syncStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSyncing = false
        }
    }

    private func refreshModels() {
        isRefreshingModels = true
        Task { @MainActor in
            await catalog.refresh(apiKey: draft.apiKey, baseURL: draft.baseURL)
            isRefreshingModels = false
        }
    }

    private func testConnection() {
        let key = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isTesting = true
        testMessage = nil
        let client = DeepSeekClient(apiKey: key, baseURL: draft.baseURL)
        let modelID = draft.model
        Task { @MainActor in
            do {
                let message = try await client.testConnection(model: modelID)
                testMessage = message
                testFailed = false
            } catch {
                testMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                testFailed = true
            }
            isTesting = false
        }
    }
}
