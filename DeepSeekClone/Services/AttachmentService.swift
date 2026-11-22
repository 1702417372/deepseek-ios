import Foundation
import UIKit
import Vision
import PDFKit
import UniformTypeIdentifiers

enum AttachmentError: LocalizedError {
    case unsupportedType
    case unreadable
    case tooLarge
    case emptyContent
    case needsAPIKey

    var errorDescription: String? {
        switch self {
        case .unsupportedType: return "不支持这种文件类型，试试 PDF、txt、md、代码文件或图片。"
        case .unreadable: return "读取失败，文件可能已损坏或没有访问权限。"
        case .tooLarge: return "文件太大了（上限 20MB），请换一个小一点的。"
        case .emptyContent: return "没有提取到任何文字内容。"
        case .needsAPIKey: return "Word / PowerPoint 需要先在设置里填好 API Key，交给云端解析。"
        }
    }
}

/// 本地处理附件：图片压缩 + OCR；纯文本本地提取；PDF / Office 走 Files API 云端解析。
enum AttachmentService {
    static let maxTextCharacters = 20000
    static let maxImageDimension: CGFloat = 1400
    static let maxFileBytes = 20 * 1024 * 1024

    static let importableTypes: [UTType] = [
        .pdf, .plainText, .utf8PlainText, .rtf, .json, .commaSeparatedText, .xml, .html,
        .sourceCode, .swiftSource, .pythonScript, .cSource, .cPlusPlusSource, .shellScript,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        UTType(filenameExtension: "yaml") ?? .plainText,
        UTType(filenameExtension: "yml") ?? .plainText,
        UTType(filenameExtension: "log") ?? .plainText,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "pptx") ?? .data
    ]

    private static let cloudDocumentExtensions: Set<String> = ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx"]

    // MARK: - 图片

    static func makeImageAttachment(from image: UIImage, name: String) async -> ChatAttachment? {
        let resized = resize(image: image, maxDimension: maxImageDimension)
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        let thumbnail = resize(image: image, maxDimension: 120).jpegData(compressionQuality: 0.7)
        let recognized = await recognizeText(in: resized)
        return ChatAttachment(
            kind: .image,
            name: name,
            text: recognized,
            imageBase64JPEG: jpeg.base64EncodedString(),
            thumbnailData: thumbnail,
            byteCount: jpeg.count
        )
    }

    static func resize(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image }
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                let lines = (request.results ?? []).compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }

    // MARK: - 文件

    static func isCloudDocument(_ url: URL) -> Bool {
        cloudDocumentExtensions.contains(url.pathExtension.lowercased())
    }

    /// 统一入口：Office/PDF 优先上传云端解析（需要 API Key），否则本地提取文本。
    static func makeAttachment(from url: URL, apiKey: String, baseURL: String) async throws -> ChatAttachment {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let extensionName = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > maxFileBytes { throw AttachmentError.tooLarge }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if cloudDocumentExtensions.contains(extensionName), !trimmedKey.isEmpty {
            guard let data = try? Data(contentsOf: url) else { throw AttachmentError.unreadable }
            let purpose = (extensionName == "pdf") ? "text_recognition" : "rich_layout_recognition"
            let fileID = try await DeepSeekClient.uploadFile(
                data: data,
                filename: name,
                purpose: purpose,
                apiKey: trimmedKey,
                baseURL: baseURL
            )
            return ChatAttachment(kind: .document, name: name, text: "", imageBase64JPEG: nil, fileID: fileID, thumbnailData: nil, byteCount: size)
        }

        if ["doc", "docx", "ppt", "pptx", "xls", "xlsx"].contains(extensionName) {
            throw AttachmentError.needsAPIKey
        }

        return try makeLocalTextAttachment(from: url, name: name, size: size)
    }

    static func makeLocalTextAttachment(from url: URL, name: String, size: Int) throws -> ChatAttachment {
        let extensionName = url.pathExtension.lowercased()
        var text = ""
        switch extensionName {
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw AttachmentError.unreadable }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                if let page = document.page(at: index), let content = page.string {
                    pages.append(content)
                }
            }
            text = pages.joined(separator: "\n\n")
        case "rtf", "rtfd":
            guard let data = try? Data(contentsOf: url),
                  let attributed = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                  ) else { throw AttachmentError.unreadable }
            text = attributed.string
        default:
            guard let data = try? Data(contentsOf: url) else { throw AttachmentError.unreadable }
            if let utf8 = String(data: data, encoding: .utf8) {
                text = utf8
            } else if let utf16 = String(data: data, encoding: .utf16) {
                text = utf16
            } else if let latin = String(data: data, encoding: .isoLatin1) {
                text = latin
            } else {
                throw AttachmentError.unsupportedType
            }
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AttachmentError.emptyContent }

        var truncated = false
        if text.count > maxTextCharacters {
            text = String(text.prefix(maxTextCharacters))
            truncated = true
        }

        return ChatAttachment(kind: .text, name: name, text: text, imageBase64JPEG: nil, fileID: nil, thumbnailData: nil, byteCount: size, isTruncated: truncated)
    }

    // MARK: - 拼进 prompt（只拼本地文本附件；图片走多模态 part，文档走 file_id）

    static func promptBlock(for attachments: [ChatAttachment]) -> String {
        let textAttachments = attachments.filter { $0.kind == .text && !$0.text.isEmpty }
        guard !textAttachments.isEmpty else { return "" }
        var lines: [String] = []
        var remaining = maxTextCharacters
        for attachment in textAttachments {
            let body = String(attachment.text.prefix(max(0, remaining)))
            remaining -= body.count
            lines.append("【附件：\(attachment.name)（本机提取的文件内容）】\n" + body)
            if remaining <= 0 { break }
        }
        return lines.joined(separator: "\n\n")
    }
}
