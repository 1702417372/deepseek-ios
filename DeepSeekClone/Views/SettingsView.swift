import SwiftUI
import Foundation

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var conversationStore: ConversationStore
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var baseURL = "https://api.deepseek.com"
    @State private var model: DeepSeekModel = .chat
    @State private var temperature = 1.0
    @State private var systemPrompt = ""
    @State private var revealKey = false
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testFailed = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        if revealKey {
                            TextField("sk-...", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("sk-...", text: $apiKey)
                        }

                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                                .foregroundStyle(DSTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("https://api.deepseek.com", text: $baseURL)
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
                    .disabled(isTesting || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

                Section {
                    Picker("默认模型", selection: $model) {
                        ForEach(DeepSeekModel.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("温度")
                            Spacer()
                            Text(String(format: "%.1f", temperature))
                                .foregroundStyle(DSTheme.textSecondary)
                        }
                        Slider(value: $temperature, in: 0...2, step: 0.1)
                    }

                    Text(model.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(DSTheme.textSecondary)
                } header: {
                    Text("模型")
                }

                Section {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 84)
                } header: {
                    Text("系统提示词（可选）")
                } footer: {
                    Text("会作为 system 消息加在每次请求最前面，用来固定回答风格。")
                }

                Section {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Text("清空全部对话")
                    }
                } header: {
                    Text("数据")
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0").foregroundStyle(DSTheme.textSecondary)
                    }
                    HStack {
                        Text("说明")
                        Spacer()
                        Text("非官方客户端").foregroundStyle(DSTheme.textSecondary)
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("本项目是第三方学习示例，界面仅用于交流学习，与 DeepSeek 官方无关。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
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
            .onAppear(perform: load)
        }
    }

    private func load() {
        let settings = settingsStore.settings
        apiKey = settings.apiKey
        baseURL = settings.baseURL
        model = settings.resolvedModel
        temperature = settings.temperature
        systemPrompt = settings.systemPrompt
    }

    private func save() {
        var updated = settingsStore.settings
        updated.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.baseURL = url.isEmpty ? "https://api.deepseek.com" : url
        updated.model = model.rawValue
        updated.temperature = temperature
        updated.systemPrompt = systemPrompt
        settingsStore.settings = updated
        dismiss()
    }

    private func testConnection() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isTesting = true
        testMessage = nil
        let client = DeepSeekClient(apiKey: key, baseURL: baseURL)

        Task { @MainActor in
            do {
                // 连接测试固定用 V3：快、便宜
                let message = try await client.testConnection(model: DeepSeekModel.chat.rawValue)
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
