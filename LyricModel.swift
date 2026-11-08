import Foundation
import SwiftUI
import Translation

struct LyricRow: Identifiable {
    let id: UUID
    var original: String
    var translated: String?
    var error: String?
    var attempts: Int = 0
}

@MainActor
final class LyricModel: ObservableObject {
    @Published var rows: [LyricRow] = []
    @Published var status = "音乐与译文并排打开，然后点击开始翻译"
    @Published var translationStatus = "开始时会自动准备日语→中文翻译"
    @Published var configuration: TranslationSession.Configuration?
    @Published var side: String { didSet { saveSettings() } }
    @Published var fraction: Double { didSet { saveSettings() } }
    @Published var selectionMode: String { didSet { saveSettings() } }
    @Published var maxLines: Int { didSet { saveSettings() } }
    @Published var isReceiving = false
    @Published var translationReady = false
    @Published var wantsTranslation = false
    private let capture = VisualCapture()
    private var stabilizer = SentenceStabilizer()
    private var lastFrame = Date.distantPast
    private var acceptedAt = Date.distantPast
    private var watchdog: Task<Void, Never>?
    private var translationEpoch = UUID()
    private var translationStarted: Date?
    private var preparing = false
    private var stalledRestarts = 0
    private var cache: [String: String] = [:]
    private var cacheOrder: [String] = []
    private var historyEpoch = UUID()

    init() {
        let defaults = UserDefaults.standard
        side = defaults.string(forKey: "musicSide.v2") ?? "right"
        fraction = defaults.object(forKey: "musicWidth.v2") as? Double ?? 0.56
        selectionMode = defaults.string(forKey: "lyricSelection.v2") ?? "highlight"
        maxLines = defaults.object(forKey: "lyricLines.v2") as? Int ?? 3
        capture.onPacket = { [weak self] in self?.receive($0) }
        capture.onState = { [weak self] text, active in
            guard let self else { return }
            self.status = text
            self.isReceiving = active
            if active {
                self.lastFrame = Date()
                self.ensureTranslation()
            }
        }
        updateOptions()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if self.isReceiving && Date().timeIntervalSince(self.lastFrame) > 10 {
                    self.isReceiving = false
                    self.status = "暂时没有新画面，请检查系统屏幕读取状态或重新开始"
                }
                if let started = self.translationStarted,
                   Date().timeIntervalSince(started) > 18, self.wantsTranslation {
                    self.translationStarted = nil
                    self.translationEpoch = UUID()
                    self.translationReady = false
                    self.preparing = false
                    if self.stalledRestarts < 2 {
                        self.stalledRestarts += 1
                        self.translationStatus = "翻译响应较慢，正在重新连接（\(self.stalledRestarts)/2）"
                        self.configuration?.invalidate()
                    } else {
                        self.stalledRestarts = 3
                        self.configuration = nil
                        self.translationStatus = "翻译暂时无响应，请点重新连接"
                    }
                }
            }
        }
    }

    func start() {
        wantsTranslation = true
        updateOptions()
        capture.start()
    }

    func stop() {
        wantsTranslation = false
        configuration = nil
        translationEpoch = UUID()
        translationStarted = nil
        translationReady = false
        preparing = false
        stabilizer.reset()
        Task { await capture.stop() }
    }

    func ensureTranslation() {
        guard wantsTranslation, stalledRestarts < 3 else { return }
        if configuration == nil {
            configuration = .init(source: .init(identifier: "ja"), target: .init(identifier: "zh-Hans"))
        } else if !translationReady && !preparing { configuration?.invalidate() }
    }

    func retryTranslation() {
        wantsTranslation = true
        stalledRestarts = 0
        for index in rows.indices where rows[index].translated == nil {
            rows[index].error = nil
            rows[index].attempts = 0
        }
        translationEpoch = UUID()
        translationStarted = nil
        translationReady = false
        preparing = false
        if configuration == nil { ensureTranslation() } else { configuration?.invalidate() }
    }

    func clear() {
        historyEpoch = UUID()
        rows = []
        stabilizer.reset()
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(side, forKey: "musicSide.v2")
        defaults.set(fraction, forKey: "musicWidth.v2")
        defaults.set(selectionMode, forKey: "lyricSelection.v2")
        defaults.set(maxLines, forKey: "lyricLines.v2")
        stabilizer.reset()
        updateOptions()
    }

    private func updateOptions() {
        capture.configure(CaptureOptions(side: side, fraction: fraction,
            selectionMode: selectionMode, maxLines: maxLines))
    }

    private func receive(_ packet: RecognitionPacket) {
        guard wantsTranslation else { return }
        lastFrame = Date()
        isReceiving = true
        if let error = packet.error { status = error; return }
        let sentence = packet.lines.first ?? ""
        status = sentence.isEmpty ? "等待当前歌词变亮" : "正在确认完整歌词"
        guard let stable = stabilizer.observe(sentence, at: ProcessInfo.processInfo.systemUptime) else { return }
        status = "正在翻译整句歌词"
        let key = SentenceSelector.normalize(stable)
        if let last = rows.last, Date().timeIntervalSince(acceptedAt) < 3,
           min(last.original.count, stable.count) >= 4,
           (key.hasPrefix(SentenceSelector.normalize(last.original)) ||
            SentenceSelector.normalize(last.original).hasPrefix(key)) {
            guard stable.count > last.original.count else { return }
            rows[rows.count - 1].original = stable
            rows[rows.count - 1].translated = cache[key]
            rows[rows.count - 1].error = nil
            rows[rows.count - 1].attempts = 0
        } else if let last = rows.last, SentenceSelector.normalize(last.original) == key {
            return
        } else {
            rows.append(LyricRow(id: UUID(), original: stable, translated: cache[key]))
        }
        acceptedAt = Date()
        if rows.count > 40 { rows.removeFirst(rows.count - 40) }
        ensureTranslation()
    }

    func translate(using session: TranslationSession) async {
        let epoch = UUID()
        translationEpoch = epoch
        preparing = true
        translationReady = false
        translationStatus = "正在准备日语→中文；首次使用请确认语言下载"
        defer {
            if epoch == translationEpoch {
                preparing = false
                translationReady = false
                translationStarted = nil
            }
        }
        do {
            try await session.prepareTranslation()
            try Task.checkCancellation()
            guard epoch == translationEpoch else { return }
            preparing = false
            translationReady = true
            translationStatus = "日语→中文已就绪"
            while !Task.isCancelled, epoch == translationEpoch {
                guard let row = rows.reversed().first(where: { $0.translated == nil && $0.error == nil }) else {
                    try await Task.sleep(for: .milliseconds(250)); continue
                }
                let version = historyEpoch
                translationStarted = Date()
                do {
                    let response = try await session.translate(row.original)
                    try Task.checkCancellation()
                    guard epoch == translationEpoch else { return }
                    translationStarted = nil
                    guard version == historyEpoch,
                          let index = rows.firstIndex(where: { $0.id == row.id && $0.original == row.original }) else { continue }
                    rows[index].translated = response.targetText
                    let key = SentenceSelector.normalize(row.original)
                    if cache[key] == nil { cacheOrder.append(key) }
                    cache[key] = response.targetText
                    if cacheOrder.count > 200 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
                    stalledRestarts = 0
                    translationStatus = "日语→中文已就绪"
                } catch {
                    try Task.checkCancellation()
                    guard epoch == translationEpoch else { return }
                    translationStarted = nil
                    if version == historyEpoch, let index = rows.firstIndex(where: { $0.id == row.id && $0.original == row.original }) {
                        rows[index].attempts += 1
                        if rows[index].attempts >= 2 { rows[index].error = "本句暂时无法翻译，点重新连接可重试" }
                    }
                    translationStatus = "翻译暂时失败：\(error.localizedDescription)"
                    try await Task.sleep(for: .seconds(1))
                }
            }
        } catch is CancellationError {
        } catch {
            if epoch == translationEpoch { translationStatus = "翻译未就绪：\(error.localizedDescription)" }
        }
    }
}
