import SwiftUI

struct RenameSheet: View {
    let conversation: Conversation
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(conversation: Conversation, onSave: @escaping (String) -> Void) {
        self.conversation = conversation
        self.onSave = onSave
        _title = State(initialValue: conversation.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("对话标题", text: $title)
                }
            }
            .navigationTitle("重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? conversation.title : trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
