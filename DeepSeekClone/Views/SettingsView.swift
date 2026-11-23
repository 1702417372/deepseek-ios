import SwiftUI
import Foundation
import UniformTypeIdentifiers

/// 设置页：对齐官方 App 的分组结构（账户 / 应用 / 语音 / 关于），点击进入子页面。
struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var conversationStore: ConversationStore
    @EnvironmentObject private var catalog: ModelCatalog
    @EnvironmentObject private var sync: SyncService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsCloseAction) private var closeSettings

    @State private var draft = AppSettings()
    @State private var loaded = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountSettingsView(draft: $draft)
                    } label: {
                        dsRow("账号管理", icon: "person")
                    }
                    NavigationLink {
                        DataSettingsView(draft: $draft)
                    } label: {
                        dsRow("数据管理", icon: "externaldrive")
                    }
                } header: {
                    Text("账户")
                }

                Section {
                    HStack {
                        dsRow("语言", icon: "globe")
                        Text("简体中文")
                            .font(.system(size: 14))
                            .foregroundStyle(DSTheme.textSecondary)
                    }
                    NavigationLink {
                        ModelSettingsView(draft: $draft)
                    } label: {
                        dsRow("模型与生成", icon: "cpu")
                    }
                    NavigationLink {
                        FontSettingsView(draft: $draft)
                    } label: {
                        dsRow("字体大小", icon: "textformat.size")
                    }
                    NavigationLink {
                        PersonalizationSettingsView(draft: $draft)
                    } label: {
                        dsRow("个性化", icon: "slider.horizontal.3")
                    }
                } header: {
                    Text("应用")
                }

                Section {
                    NavigationLink {
                        VoiceSettingsView(draft: $draft)
                    } label: {
                        dsRow("朗读音色", icon: "speaker.wave.2", value: draft.ttsVoice == "stella" ? "女声 · stella" : "男声 · tide")
                    }
                } header: {
                    Text("语音")
                }

                Section {
                    HStack {
                        dsRow("检查更新", icon: "info.circle")
                        Text("1.8.0 (7)")
                            .font(.system(size: 14))
                            .foregroundStyle(DSTheme.textSecondary)
                    }
                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        dsRow("服务协议", icon: "doc.text")
                    }
                } header: {
                    Text("关于")
                }

                Section {
                    NavigationLink {
                        HelpSettingsView()
                    } label: {
                        dsRow("帮助与反馈", icon: "questionmark.circle")
                    }
                }

                Section {
                    Button {
                        confirmLogout = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 22)
                            Text("退出登录")
                                .font(.system(size: 15))
                        }
                        .foregroundStyle(.red)
                    }
                }

                Section {
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("内容由 AI 生成，请仔细甄别，并合法使用。")
                        Text("非官方客户端 · 与 DeepSeek 官方无关")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(DSTheme.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        save()
                        closeSettings()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DSTheme.textSecondary)
                    }
                }
            }
            .onAppear {
                if !loaded {
                    draft = settingsStore.settings
                    loaded = true
                }
            }
            .onDisappear { save() }
            .confirmationDialog("退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("退出并清除 API Key", role: .destructive) {
                    draft.apiKey = ""
                    save()
                    closeSettings()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("只会清除本机保存的 API Key，对话记录和其它设置会保留。")
            }
        }
    }

    private func save() {
        guard loaded else { return }
        var value = draft
        value.apiKey = value.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = value.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        value.baseURL = url.isEmpty ? "https://api.deepseek.com" : url
        value.fontScale = min(max(value.fontScale, 0.8), 1.5)
        settingsStore.settings = value
    }
}

// MARK: - 通用行

private func dsRow(_ title: String, icon: String, value: String? = nil) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(DSTheme.textSecondary)
            .frame(width: 22)
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(DSTheme.textPrimary)
        Spacer(minLength: 0)
        if let value {
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(DSTheme.textSecondary)
        }
    }
}

// MARK: - 账号管理（API Key / 服务地址）

private struct AccountSettingsView: View {
    @Binding var draft: AppSettings
    @State private var revealKey = false
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testFailed = false

    var body: some View {
        Form {
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
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(isTesting || draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("API 配置")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let testMessage {
                        Text(testMessage)
                            .foregroundStyle(testFailed ? Color.red : Color.green)
                    }
                    Text("使用你自己的 DeepSeek API Key，费用由你的账号承担。")
                }
            }
        }
        .navigationTitle("账号管理")
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - 数据管理（导出 / 导入 / 清空 / 多端同步）

private struct DataSettingsView: View {
    @EnvironmentObject private var conversationStore: ConversationStore
    @EnvironmentObject private var sync: SyncService
    @Binding var draft: AppSettings

    @State private var confirmClear = false
    @State private var shareItem: ShareItem?
    @State private var importStatus: String?
    @State private var showImporter = false
    @State private var isSyncing = false
    @State private var syncStatus: String?

    var body: some View {
        Form {
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
                Text("本地数据")
            } footer: {
                Text("导出的 JSON 与网页版通用；也能导入 {title, messages} 结构的第三方历史或 Markdown 文本，按会话 id 合并。")
            }

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
                    if isSyncing { ProgressView().controlSize(.mini) }
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
                Text("App 与网页版共用同一份 JSON 和 X-Sync-Key 协议。国内直连需要代理。")
            }
        }
        .navigationTitle("数据管理")
        .navigationBarTitleDisplayMode(.inline)
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
        .alert("清空全部对话？", isPresented: $confirmClear) {
            Button("清空", role: .destructive) { conversationStore.deleteAll() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("清空后无法恢复。API Key 与其它设置不会被删除。")
        }
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
        syncRun { try await self.sync.push(self.conversationStore.all, urlString: self.draft.syncURL, key: self.draft.syncKey); return "已上传 \(self.conversationStore.all.count) 个会话" }
    }

    private func syncDownload() {
        syncRun {
            let remote = try await self.sync.pull(urlString: self.draft.syncURL, key: self.draft.syncKey)
            let merged = ConversationArchive.merge(remote, into: self.conversationStore.all)
            self.conversationStore.replaceAll(merged)
            return "已下载 \(remote.count) 个会话（合并后共 \(merged.count) 个）"
        }
    }

    private func syncBoth() {
        syncRun {
            let merged = try await self.sync.syncBoth(local: self.conversationStore.all, urlString: self.draft.syncURL, key: self.draft.syncKey)
            self.conversationStore.replaceAll(merged)
            return "双向同步完成，当前共 \(merged.count) 个会话"
        }
    }

    private func syncRun(_ work: @escaping () async throws -> String) {
        guard SyncService.isReady(urlString: draft.syncURL, key: draft.syncKey) else {
            syncStatus = "请先填写 https:// 开头的同步地址和同步密钥"
            return
        }
        isSyncing = true
        syncStatus = nil
        Task { @MainActor in
            do {
                syncStatus = try await work()
            } catch {
                syncStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSyncing = false
        }
    }
}

// MARK: - 模型与生成

private struct ModelSettingsView: View {
    @EnvironmentObject private var catalog: ModelCatalog
    @Binding var draft: AppSettings
    @State private var isRefreshingModels = false

    private var thinkingLocksSampling: Bool {
        draft.thinkingEnabled || draft.webSearchEnabled || draft.safetyCheckEnabled || draft.autoTitleEnabled
    }

    var body: some View {
        Form {
            Section {
                Picker("模型", selection: $draft.model) {
                    ForEach(catalog.options) { option in
                        Text(option.shortName).tag(option.id)
                    }
                }
                Button {
                    refreshModels()
                } label: {
                    HStack {
                        Text(isRefreshingModels ? "正在刷新…" : "刷新模型列表")
                        Spacer()
                        if isRefreshingModels { ProgressView() }
                    }
                }
                .disabled(isRefreshingModels)
            } header: {
                Text("模型")
            } footer: {
                ForEach(catalog.options) { option in
                    if option.id == draft.model {
                        Text(option.capabilityText)
                    }
                }
            }

            Section {
                Toggle("深度思考", isOn: $draft.thinkingEnabled)
                if draft.thinkingEnabled {
                    Picker("思考强度", selection: $draft.reasoningEffort) {
                        Text("低").tag("low")
                        Text("高").tag("high")
                        Text("最大").tag("max")
                    }
                }
            } header: {
                Text("思考")
            }

            Section {
                Toggle("联网搜索", isOn: $draft.webSearchEnabled)
                Toggle("阅读链接", isOn: $draft.readURLEnabled)
                Toggle("自动生成标题", isOn: $draft.autoTitleEnabled)
                Toggle("内容安全校验", isOn: $draft.safetyCheckEnabled)
            } header: {
                Text("能力")
            } footer: {
                Text("联网搜索、阅读链接、自动标题只支持 DeepSeek-V4.1-Flash。")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("温度")
                        Spacer()
                        Text(String(format: "%.2f", draft.temperature))
                            .foregroundStyle(DSTheme.textSecondary)
                    }
                    Slider(value: $draft.temperature, in: 0...2, step: 0.1)
                        .disabled(thinkingLocksSampling)
                }
                Stepper("历史字符上限：\(draft.contextCharacterLimit)", value: $draft.contextCharacterLimit, in: 10000...400000, step: 10000)
            } header: {
                Text("生成")
            } footer: {
                Text("开启深度思考时，温度参数会被服务端忽略。")
            }
        }
        .navigationTitle("模型与生成")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func refreshModels() {
        isRefreshingModels = true
        Task { @MainActor in
            await catalog.refresh(apiKey: draft.apiKey, baseURL: draft.baseURL)
            isRefreshingModels = false
        }
    }
}

// MARK: - 字体 / 个性化 / 语音 / 关于 / 帮助

private struct FontSettingsView: View {
    @Binding var draft: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("消息字号", selection: $draft.fontScale) {
                    Text("小").tag(0.9)
                    Text("标准").tag(1.0)
                    Text("大").tag(1.15)
                    Text("特大").tag(1.3)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("只影响消息正文的显示大小。")
            }
        }
        .navigationTitle("字体大小")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PersonalizationSettingsView: View {
    @Binding var draft: AppSettings

    var body: some View {
        Form {
            Section {
                TextEditor(text: $draft.systemPrompt)
                    .frame(minHeight: 140)
            } header: {
                Text("系统提示词")
            } footer: {
                Text("会作为 system 消息加在每次请求最前面。")
            }
        }
        .navigationTitle("个性化")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct VoiceSettingsView: View {
    @Binding var draft: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("朗读音色", selection: $draft.ttsVoice) {
                    Text("女声 · stella").tag("stella")
                    Text("男声 · tide").tag("tide")
                }
                Toggle("回答生成后自动朗读", isOn: $draft.autoReadAnswers)
            } footer: {
                Text("每条回答下方的「朗读」按钮会用这个音色合成语音；输入框的麦克风按钮把录音转成文字。")
            }
        }
        .navigationTitle("朗读音色")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack { Text("版本"); Spacer(); Text("1.8.0 (7)").foregroundStyle(DSTheme.textSecondary) }
                HStack { Text("接口"); Spacer(); Text("DeepSeek Chat Completions").foregroundStyle(DSTheme.textSecondary) }
                HStack { Text("说明"); Spacer(); Text("非官方客户端").foregroundStyle(DSTheme.textSecondary) }
            }
            Section {
                Text("本项目是第三方学习示例，与 DeepSeek 官方无关。API 费用由你自己的账号承担。内容由 AI 生成，请仔细甄别，并合法使用。")
                    .font(.system(size: 13))
                    .foregroundStyle(DSTheme.textSecondary)
            }
        }
        .navigationTitle("服务协议")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HelpSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text("遇到问题先检查：API Key 是否有效、网络能否访问 api.deepseek.com、同步是否需要代理。")
                    .font(.system(size: 13))
                Text("反馈渠道：直接在对话里描述现象和复现步骤即可。")
                    .font(.system(size: 13))
            }
        }
        .navigationTitle("帮助与反馈")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 关闭设置页（供 RootView 覆盖层使用）

private struct SettingsCloseActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = { }
}

extension EnvironmentValues {
    var settingsCloseAction: () -> Void {
        get { self[SettingsCloseActionKey.self] }
        set { self[SettingsCloseActionKey.self] = newValue }
    }
}
