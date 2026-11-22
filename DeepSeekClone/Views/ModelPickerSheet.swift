import SwiftUI

struct ModelPickerSheet: View {
    @EnvironmentObject private var catalog: ModelCatalog
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var customModelID = ""
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(catalog.options) { option in
                        Button {
                            select(option)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.shortName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(DSTheme.textPrimary)
                                    Text(option.id)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(DSTheme.textSecondary)
                                    Text(option.capabilityText)
                                        .font(.system(size: 11))
                                        .foregroundStyle(DSTheme.textSecondary)
                                }
                                Spacer()
                                if settingsStore.settings.model == option.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(DSTheme.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("可用模型")
                        Spacer()
                        Button {
                            refresh()
                        } label: {
                            if isRefreshing {
                                ProgressView().controlSize(.mini)
                            } else {
                                Label("刷新", systemImage: "arrow.clockwise")
                                    .labelStyle(.titleAndIcon)
                                    .font(.system(size: 12))
                            }
                        }
                        .disabled(isRefreshing)
                    }
                } footer: {
                    if let error = catalog.errorMessage {
                        Text(error).foregroundStyle(.red)
                    } else if let updated = catalog.lastUpdated {
                        Text("上次同步：\(DSTheme.dateString(updated))")
                    } else {
                        Text("从 GET /models 读取，需在设置中填好 API Key")
                    }
                }

                Section {
                    Toggle("深度思考", isOn: Binding(
                        get: { settingsStore.settings.thinkingEnabled },
                        set: { value in
                            var updated = settingsStore.settings
                            updated.thinkingEnabled = value
                            settingsStore.settings = updated
                        }
                    ))

                    if settingsStore.settings.thinkingEnabled {
                        Picker("思考强度", selection: Binding(
                            get: { settingsStore.settings.reasoningEffort },
                            set: { value in
                                var updated = settingsStore.settings
                                updated.reasoningEffort = value
                                settingsStore.settings = updated
                            }
                        )) {
                            Text("low").tag("low")
                            Text("high").tag("high")
                            Text("max").tag("max")
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("联网搜索", isOn: Binding(
                        get: { settingsStore.settings.webSearchEnabled },
                        set: { value in
                            var updated = settingsStore.settings
                            updated.webSearchEnabled = value
                            settingsStore.settings = updated
                        }
                    ))

                    Toggle("阅读链接", isOn: Binding(
                        get: { settingsStore.settings.readURLEnabled },
                        set: { value in
                            var updated = settingsStore.settings
                            updated.readURLEnabled = value
                            settingsStore.settings = updated
                        }
                    ))
                } header: {
                    Text("本次对话能力")
                } footer: {
                    Text("联网搜索与阅读链接由服务端执行，只有 DeepSeek-V4.1-Flash 支持。")
                }

                Section {
                    TextField("自定义模型 ID", text: $customModelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("使用这个模型") {
                        let trimmed = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        var updated = settingsStore.settings
                        updated.model = trimmed
                        settingsStore.settings = updated
                        dismiss()
                    }
                    .disabled(customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("自定义")
                } footer: {
                    Text("接入第三方 OpenAI 兼容服务时可以手动填模型 ID。")
                }
            }
            .navigationTitle("模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                if catalog.options.isEmpty {
                    refresh()
                }
            }
        }
    }

    private func select(_ option: ModelOption) {
        var updated = settingsStore.settings
        updated.model = option.id
        settingsStore.settings = updated
        if let defaultEffort = option.defaultEffort {
            updated.reasoningEffort = defaultEffort
            settingsStore.settings = updated
        }
        dismiss()
    }

    private func refresh() {
        isRefreshing = true
        Task { @MainActor in
            await catalog.refresh(apiKey: settingsStore.settings.apiKey, baseURL: settingsStore.settings.baseURL)
            isRefreshing = false
        }
    }
}
