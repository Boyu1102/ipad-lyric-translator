import Foundation
import SwiftUI
import Translation

struct LyricRow: Identifiable {
    let id: String
    let original: String
    var translated: String?
    var error: String?
}

@MainActor
final class LyricModel: ObservableObject {
    @Published var rows: [LyricRow] = []
    @Published var status = "请将音乐放在左边，本 App 放在右边"
    @Published var translationStatus = "先启用翻译，按提示下载语言"
    @Published var configuration: TranslationSession.Configuration?
    @Published var side = "left" { didSet { updateOptions() } }
    @Published var fraction = 0.62 { didSet { updateOptions() } }
    @Published var isReceiving = false
    @Published var translationReady = false
    private let bridge = LocalBridge()
    private var previous: [String] = []
    private var lastPacket = Date.distantPast
    private var acceptsPackets = true
    private var watchdog: Task<Void, Never>?
    private var historyVersion = UUID()

    init() {
        bridge.onPacket = { [weak self] packet in
            Task { @MainActor in self?.receive(packet) }
        }
        bridge.onError = { [weak self] error in
            Task { @MainActor in self?.status = error }
        }
        bridge.start()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if self.isReceiving && Date().timeIntervalSince(self.lastPacket) > 8 {
                    self.isReceiving = false
                    self.status = "未收到新画面，请保持两个 App 并排并检查录屏状态"
                }
            }
        }
    }

    func enableTranslation() {
        if configuration == nil {
            configuration = .init(source: .init(identifier: "ja"), target: .init(identifier: "zh-Hans"))
        } else {
            configuration?.invalidate()
        }
    }

    func armCapture() {
        acceptsPackets = true
        previous = []
        updateOptions()
        bridge.start()
        status = "在系统弹窗中选择“歌词译伴识别”并开始直播"
    }

    func stopCapture() {
        acceptsPackets = false
        bridge.configure(CaptureOptions(side: side, fraction: fraction, stop: true))
        isReceiving = false
        status = "已请求停止识别；也可在控制中心停止录屏"
    }

    func clear() {
        historyVersion = UUID()
        rows = []
        previous = []
    }

    func retryTranslation() {
        for index in rows.indices where rows[index].translated == nil {
            rows[index].error = nil
        }
        enableTranslation()
    }

    private func updateOptions() {
        previous = []
        bridge.configure(CaptureOptions(side: side, fraction: fraction, stop: !acceptsPackets))
    }

    private func receive(_ packet: RecognitionPacket) {
        guard acceptsPackets else { return }
        lastPacket = Date()
        isReceiving = packet.status == "capturing"
        if let error = packet.error { status = error; return }
        if packet.status == "stopped" {
            isReceiving = false
            status = "识别已停止"
            previous = []
            return
        }
        if packet.status == "paused" {
            status = "识别已暂停，请在系统录屏控制中恢复"
            previous = []
            return
        }
        let lines = packet.lines.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        status = lines.isEmpty ? "已连接，等待歌词；没有文字时请调整识别区域" : "正在识别歌词"
        // Require the same line in two successive captures to reject scrolling transitions.
        let stable = lines.filter { previous.contains($0) }
        previous = lines
        for line in stable where !rows.contains(where: { $0.id == line }) {
            rows.append(LyricRow(id: line, original: line))
        }
        if rows.count > 80 { rows.removeFirst(rows.count - 80) }
    }

    func translate(using session: TranslationSession) async {
        translationReady = false
        translationStatus = "正在准备日语→简体中文翻译"
        do {
            try await session.prepareTranslation()
            try Task.checkCancellation()
            translationReady = true
            translationStatus = "日语→中文已就绪"
            while !Task.isCancelled {
                let pending = rows.filter { $0.translated == nil && $0.error == nil }.prefix(8)
                if pending.isEmpty {
                    try await Task.sleep(for: .milliseconds(400))
                    continue
                }
                let version = historyVersion
                let requests = pending.map {
                    TranslationSession.Request(sourceText: $0.original, clientIdentifier: $0.id)
                }
                do {
                    let responses = try await session.translations(from: requests)
                    try Task.checkCancellation()
                    guard version == historyVersion else { continue }
                    for response in responses {
                        if let id = response.clientIdentifier,
                           let index = rows.firstIndex(where: { $0.id == id }) {
                            rows[index].translated = response.targetText
                        }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    guard version == historyVersion else { continue }
                    for row in pending {
                        if let index = rows.firstIndex(where: { $0.id == row.id }) {
                            rows[index].error = "翻译失败，点击“重试翻译”"
                        }
                    }
                    translationStatus = "翻译暂时失败：\(error.localizedDescription)"
                }
            }
        } catch is CancellationError {
            translationReady = false
        } catch {
            translationReady = false
            translationStatus = "无法启用翻译：\(error.localizedDescription)"
        }
    }
}
