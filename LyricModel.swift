import Foundation
import SwiftUI
import Translation

@MainActor
final class LyricModel: ObservableObject {
    @Published private(set) var track: MusicTrack?
    @Published private(set) var document: LyricsDocument?
    @Published private(set) var currentIndex: Int?
    @Published private(set) var translations: [Int: String] = [:]
    @Published private(set) var translationErrors: [Int: String] = [:]
    @Published private(set) var alternatives: [LyricsRecord] = []
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var fetching = false
    @Published private(set) var position: Double = 0
    @Published private(set) var positionAvailable = false
    @Published private(set) var isPlaying = false
    @Published private(set) var status = "先在 Apple Music 播放歌曲，再点连接"
    @Published private(set) var translationStatus = "不需要共享屏幕、录音或分屏"
    @Published var configuration: TranslationSession.Configuration?
    @Published var offset: Double = 0 { didSet { updateIndex(); saveOffset() } }
    private let monitor = MusicMonitor()
    private let service = LyricsService()
    private var lookupTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var lookupEpoch = UUID()
    private var documentEpoch = UUID()
    private var translationEpoch = UUID()
    private var translationStarted: Date?
    private var translationReady = false
    private var preparingTranslation = false
    private var wantsTranslation = false
    private var following = false
    private var stalledRestarts = 0
    private var translationAttempts: [Int: Int] = [:]
    private var translatedTextCache: [String: String] = [:]
    private var manualCursor = 0
    private var manualTrackPinned = false
    private var lastObservedTrackKey: String?

    var currentCue: LyricCue? {
        guard let document, let index = currentIndex, document.cues.indices.contains(index) else { return nil }
        return document.cues[index]
    }
    var currentTranslation: String? { currentIndex.flatMap { translations[$0] } }
    var currentError: String? { currentIndex.flatMap { translationErrors[$0] } }
    var upcoming: [LyricCue] {
        guard let document else { return [] }
        let start = min(document.cues.count, max(0, (currentIndex ?? -1) + 1))
        return Array(document.cues.dropFirst(start).filter { !$0.text.isEmpty }.prefix(2))
    }
    var automaticTimeline: Bool { document?.isTimed == true && connected && positionAvailable }

    init() {
        monitor.onSnapshot = { [weak self] in self?.receive($0) }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if let started = self.translationStarted, Date().timeIntervalSince(started) > 20 {
                    self.translationStarted = nil
                    self.translationEpoch = UUID()
                    self.translationReady = false
                    self.preparingTranslation = false
                    self.stalledRestarts += 1
                    if self.stalledRestarts <= 2 {
                        self.translationStatus = "翻译响应慢，正在重连（\(self.stalledRestarts)/2）"
                        self.configuration?.invalidate()
                    } else {
                        self.configuration = nil
                        self.translationStatus = "翻译暂时无响应，请点重试翻译"
                    }
                }
            }
        }
    }

    func connect() async {
        guard !connecting else { return }
        connecting = true
        following = true
        defer { connecting = false }
        if await monitor.start() {
            connected = true
            wantsTranslation = true
            ensureTranslation()
            updateIndex()
        } else {
            following = false
            connected = false
            status = "未获得“媒体与 Apple Music”访问权限；仍可手动找歌或导入歌词"
        }
    }

    func stopFollowing() {
        following = false
        manualCursor = currentIndex ?? 0
        connected = false
        monitor.stop()
        lookupTask?.cancel()
        lookupEpoch = UUID()
        fetching = false
        wantsTranslation = false
        configuration = nil
        translationEpoch = UUID()
        translationStarted = nil
        translationReady = false
        preparingTranslation = false
        status = "已停止跟随；Music 继续正常播放"
    }

    func refresh() {
        monitor.refresh()
        if let track { lookup(track, refresh: true) }
    }

    func resumed() {
        if connected { monitor.refresh() }
        ensureTranslation()
    }

    private func receive(_ snapshot: MusicSnapshot) {
        guard following else { return }
        positionAvailable = snapshot.position != nil
        if let time = snapshot.position { position = time }
        isPlaying = snapshot.isPlaying
        if let current = snapshot.track {
            if manualTrackPinned, let previous = lastObservedTrackKey, previous != current.key { manualTrackPinned = false }
            lastObservedTrackKey = current.key
            if !manualTrackPinned && track?.key != current.key { adopt(current) }
        } else if !manualTrackPinned {
            if track != nil || document != nil {
                track = nil
                lookupTask?.cancel()
                lookupEpoch = UUID()
                fetching = false
                resetDocument()
            }
            status = "未读到当前曲目；请先在 Apple Music 播放，或使用手动找歌"
        }
        if connected, document?.isTimed == true, snapshot.position == nil {
            status = "Music 暂未提供更新的播放时间；当前可手动切句，稍后会自动恢复"
        }
        updateIndex()
    }

    private func adopt(_ newTrack: MusicTrack) {
        track = newTrack
        resetDocument()
        let saved = UserDefaults.standard.dictionary(forKey: "lyricsOffsets.v3") as? [String: Double]
        offset = saved?[newTrack.key] ?? 0
        lookup(newTrack)
    }

    private func resetDocument() {
        documentEpoch = UUID()
        document = nil
        currentIndex = nil
        manualCursor = 0
        translations = [:]
        translationErrors = [:]
        translationAttempts = [:]
        alternatives = []
    }

    func searchManually(title: String, artist: String, duration: Double) {
        let song = MusicTrack(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines), album: "",
            duration: duration.isFinite && duration >= 1 && duration <= 3600 ? duration : 0)
        guard !song.title.isEmpty, !song.artist.isEmpty else { status = "请填写歌名和歌手"; return }
        manualTrackPinned = true
        wantsTranslation = true
        adopt(song)
        ensureTranslation()
    }

    private func lookup(_ track: MusicTrack, refresh: Bool = false) {
        lookupTask?.cancel()
        lookupEpoch = UUID()
        let epoch = lookupEpoch
        fetching = true
        alternatives = []
        status = "正在匹配当前歌曲的同步歌词"
        let service = service
        lookupTask = Task { [weak self] in
            do {
                let result = try await service.lookup(track, refresh: refresh)
                try Task.checkCancellation()
                guard let self, epoch == self.lookupEpoch else { return }
                self.fetching = false
                if let selected = result.selected { self.choose(selected) }
                else {
                    self.alternatives = result.alternatives
                    self.status = "没有足够可靠的自动匹配，请选择正确的歌曲版本"
                }
            } catch is CancellationError {
            } catch {
                guard let self, epoch == self.lookupEpoch else { return }
                self.fetching = false
                self.status = error.localizedDescription
            }
        }
    }

    func choose(_ record: LyricsRecord) {
        install(record.document)
    }

    func importLyrics(from url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 1_000_000 else { status = "歌词文件过大"; return }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                status = "无法读取文件编码，请使用 UTF-8 或 UTF-16 歌词文件"; return
            }
            let imported = LRCParser.parse(text, source: "导入 · \(url.lastPathComponent)")
            guard !imported.cues.isEmpty else { status = "文件里没有可读取的歌词"; return }
            lookupTask?.cancel()
            lookupEpoch = UUID()
            fetching = false
            manualTrackPinned = true
            if track == nil { track = MusicTrack(title: url.deletingPathExtension().lastPathComponent, artist: "导入歌词", album: "", duration: 0) }
            install(imported)
        } catch { status = "导入失败：\(error.localizedDescription)" }
    }

    private func install(_ newDocument: LyricsDocument) {
        documentEpoch = UUID()
        document = newDocument
        manualCursor = 0
        translations = [:]
        translationErrors = [:]
        translationAttempts = [:]
        alternatives = []
        wantsTranslation = true
        stalledRestarts = 0
        status = newDocument.instrumental ? "歌词服务将这首歌标记为纯音乐" :
            (newDocument.isTimed ? "同步歌词已载入，按 Music 播放时间跟随" : "只有无时间轴歌词，请手动切换句子")
        updateIndex()
        ensureTranslation()
    }

    private func updateIndex() {
        guard let document else { currentIndex = nil; return }
        if automaticTimeline { currentIndex = document.index(at: position, offset: offset) }
        else { currentIndex = document.cues.indices.contains(manualCursor) ? manualCursor : nil }
    }

    func moveManually(_ difference: Int) {
        guard let document, !document.cues.isEmpty else { return }
        manualCursor = min(document.cues.count - 1, max(0, manualCursor + difference))
        currentIndex = manualCursor
    }

    private func saveOffset() {
        guard let track else { return }
        var saved = UserDefaults.standard.dictionary(forKey: "lyricsOffsets.v3") as? [String: Double] ?? [:]
        saved[track.key] = offset
        UserDefaults.standard.set(saved, forKey: "lyricsOffsets.v3")
    }

    private func ensureTranslation() {
        guard wantsTranslation, stalledRestarts <= 2 else { return }
        if configuration == nil {
            configuration = .init(source: .init(identifier: "ja"), target: .init(identifier: "zh-Hans"))
        } else if !translationReady && !preparingTranslation { configuration?.invalidate() }
    }

    func retryTranslation() {
        wantsTranslation = true
        stalledRestarts = 0
        translationErrors = [:]
        translationAttempts = [:]
        translationEpoch = UUID()
        translationStarted = nil
        translationReady = false
        preparingTranslation = false
        if configuration == nil { ensureTranslation() } else { configuration?.invalidate() }
    }

    private func pendingIndex() -> Int? {
        guard let document, !document.cues.isEmpty else { return nil }
        let start = currentIndex ?? 0
        let candidates = Array(start..<min(document.cues.count, start + 4))
        return candidates.first { index in
            !document.cues[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            translations[index] == nil && translationErrors[index] == nil
        }
    }

    func translate(using session: TranslationSession) async {
        let epoch = UUID()
        translationEpoch = epoch
        preparingTranslation = true
        translationReady = false
        translationStatus = "正在准备日语→中文翻译；首次使用按提示下载语言"
        defer {
            if epoch == translationEpoch {
                preparingTranslation = false
                translationReady = false
                translationStarted = nil
            }
        }
        do {
            try await session.prepareTranslation()
            try Task.checkCancellation()
            guard epoch == translationEpoch else { return }
            preparingTranslation = false
            translationReady = true
            translationStatus = "日语→中文已就绪"
            while !Task.isCancelled, epoch == translationEpoch {
                guard let index = pendingIndex(), let document else {
                    try await Task.sleep(for: .milliseconds(200)); continue
                }
                let text = document.cues[index].text
                let cacheKey = (track?.key ?? "") + "|" + document.source + "|" + text
                if let cached = translatedTextCache[cacheKey] { translations[index] = cached; continue }
                let version = documentEpoch
                translationStarted = Date()
                do {
                    let response = try await session.translate(text)
                    try Task.checkCancellation()
                    guard epoch == translationEpoch else { return }
                    translationStarted = nil
                    guard version == documentEpoch else { continue }
                    translations[index] = response.targetText
                    translatedTextCache[cacheKey] = response.targetText
                    if translatedTextCache.count > 400 { translatedTextCache = [cacheKey: response.targetText] }
                    stalledRestarts = 0
                    translationStatus = "日语→中文已就绪"
                } catch {
                    try Task.checkCancellation()
                    guard epoch == translationEpoch else { return }
                    translationStarted = nil
                    guard version == documentEpoch else { continue }
                    translationAttempts[index, default: 0] += 1
                    if translationAttempts[index, default: 0] >= 2 { translationErrors[index] = "这句暂时无法翻译，可点重试翻译" }
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
