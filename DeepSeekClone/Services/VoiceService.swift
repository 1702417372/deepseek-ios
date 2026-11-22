import Foundation
import AVFoundation

/// 朗读回答：调用 DeepSeek TTS 合成 wav 并用 AVAudioPlayer 播放。
@MainActor
final class TTSPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var speakingMessageID: UUID?
    @Published var errorMessage: String?

    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?

    func speak(messageID: UUID, text: String, voice: String, apiKey: String, baseURL: String) {
        if speakingMessageID == messageID {
            stop()
            return
        }
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "还没有填写 API Key，无法朗读。"
            return
        }
        speakingMessageID = messageID
        errorMessage = nil
        task = Task { [weak self] in
            do {
                let data = try await DeepSeekClient.textToSpeech(
                    text: trimmed,
                    voice: voice,
                    apiKey: apiKey,
                    baseURL: baseURL
                )
                guard let self else { return }
                guard !Task.isCancelled else { return }
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio, options: [])
                try session.setActive(true)
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.player = player
                player.play()
            } catch {
                guard let self else { return }
                if Task.isCancelled { return }
                self.speakingMessageID = nil
                self.player = nil
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        speakingMessageID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.speakingMessageID = nil
            self.player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

/// 语音输入：录音成 16k 单声道 WAV，交给 ASR 转文字。
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?

    static let maxDuration: TimeInterval = 110

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?
    private var fileURL: URL?

    func start() async -> Bool {
        guard !isRecording else { return true }
        let granted = await Self.requestPermission()
        guard granted else {
            errorMessage = "没有麦克风权限：设置 → 隐私与安全性 → 麦克风 → 打开 DeepSeek。"
            return false
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-\(UUID().uuidString).wav")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else {
                errorMessage = "录音启动失败，请重试。"
                return false
            }
            self.recorder = recorder
            self.fileURL = url
            self.startedAt = Date()
            self.elapsed = 0
            self.isRecording = true
            self.errorMessage = nil

            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let startedAt = self.startedAt else { return }
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
            }
            return true
        } catch {
            errorMessage = "录音初始化失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 停止录音并返回 WAV 数据；没有录到内容时返回 nil。
    func finish() -> Data? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        startedAt = nil
        defer {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        guard let url = fileURL else { return nil }
        fileURL = nil
        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        guard let data, data.count > 1024 else { return nil }
        return data
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        startedAt = nil
        elapsed = 0
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
