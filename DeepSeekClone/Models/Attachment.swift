import Foundation

enum AttachmentKind: String, Codable {
    case image
    case text
    /// 通过 Files API 上传的文档（PDF / Word / PPT 等），请求里用 file_id 引用。
    case document
}

/// 一条消息里的附件。
struct ChatAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: AttachmentKind
    var name: String
    /// 图片为 OCR 结果；纯文本文件为提取出的正文；文档为空。
    var text: String = ""
    /// 图片压缩后的 base64（不含 data: 前缀）。
    var imageBase64JPEG: String?
    /// Files API 返回的 file_id。
    var fileID: String?
    /// 本地展示用的缩略图（JPEG）。
    var thumbnailData: Data?
    var byteCount: Int = 0
    var isTruncated: Bool = false

    var badgeText: String {
        switch kind {
        case .image:
            return text.isEmpty ? "图片" : "图片 · 已识别 \(text.count) 字"
        case .text:
            return isTruncated ? "文件 · 已截断" : "文件 · \(text.count) 字"
        case .document:
            return "文档 · 云端解析"
        }
    }

    var iconName: String {
        switch kind {
        case .image: return "photo"
        case .text: return "doc.text"
        case .document: return "doc.richtext"
        }
    }
}
