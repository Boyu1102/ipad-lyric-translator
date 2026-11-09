import Foundation

enum LyricsLookupError: LocalizedError {
    case notFound, network, tooLarge
    case throttled(Int)
    var errorDescription: String? {
        switch self {
        case .notFound: return "暂时没找到这首歌的歌词，可以手动找歌或导入 LRC"
        case .network: return "歌词服务暂时无法连接，请稍后重试或导入 LRC"
        case .tooLarge: return "歌词数据过大，暂时无法读取"
        case .throttled(let seconds): return "歌词服务请求较多，请至少等待 \(seconds) 秒再试"
        }
    }
}

struct LyricsLookup: Sendable {
    var selected: LyricsRecord?
    var alternatives: [LyricsRecord]
    var fallback: LyricsDocument? = nil
}

actor LyricsService {
    private let session: URLSession
    private var cache: [String: LyricsLookup] = [:]
    private var lastRequest = Date.distantPast
    private var blockedUntil = Date.distantPast
    // Actor methods are reentrant across await. Chain requests to keep service access sequential.
    private var tail: Task<Void, Never>?
    private var catalogCache: [String: MusicTrack] = [:]
    private var lastCatalogRequest = Date.distantPast

    init(session suppliedSession: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        session = suppliedSession ?? URLSession(configuration: config)
    }

    func lookup(_ track: MusicTrack, refresh: Bool = false) async throws -> LyricsLookup {
        if !refresh, let cached = cache[track.key] { return cached }
        guard !track.title.isEmpty, !track.artist.isEmpty else { throw LyricsLookupError.notFound }
        var records: [LyricsRecord] = []
        // Search the displayed names first; only resolve localized names when necessary.
        let original = try await find(track, japaneseOnly: LyricLanguage.detect(track.title + " " + track.artist) == .japanese)
        records += original.alternatives
        if original.selected != nil { store(original, for: track.key); return original }
        try Task.checkCancellation()
        if let localized = try await localizedTrack(track), localized.title != track.title || localized.artist != track.artist {
            let translatedName = try await find(localized, japaneseOnly: LyricLanguage.detect(localized.title + " " + localized.artist) == .japanese)
            records += translatedName.alternatives
            if translatedName.selected != nil { store(translatedName, for: track.key); return translatedName }
        }
        if let text = track.libraryLyrics, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let document = LRCParser.parse(text, source: "音乐资料库歌词")
            if document.language == .japanese || document.language == .english {
                let result = LyricsLookup(selected: nil, alternatives: [], fallback: document)
                store(result, for: track.key)
                return result
            }
        }
        var ids: Set<Int> = []
        records = records.filter { ids.insert($0.id).inserted }
        records.sort { $0.likelyJapanese && !$1.likelyJapanese }
        let result = LyricsLookup(selected: nil, alternatives: Array(records.prefix(10)))
        guard !result.alternatives.isEmpty else { throw LyricsLookupError.notFound }
        store(result, for: track.key)
        return result
    }

    private func find(_ track: MusicTrack, japaneseOnly: Bool) async throws -> LyricsLookup {
        var parameters = ["track_name": track.title, "artist_name": track.artist]
        if !track.album.isEmpty { parameters["album_name"] = track.album }
        if track.duration >= 1 && track.duration <= 3600 { parameters["duration"] = String(track.duration) }
        let canMatchAutomatically = track.duration > 0 || !track.album.isEmpty
        if canMatchAutomatically { do {
            let data = try await request("/api/get", parameters)
            let record = try JSONDecoder().decode(LyricsRecord.self, from: data)
            if LyricsMatcher.score(record, for: track, japaneseOnly: japaneseOnly) != nil {
                let result = LyricsLookup(selected: record, alternatives: [])
                return result
            }
        } catch LyricsLookupError.notFound {
        } }
        try Task.checkCancellation()
        let data = try await request("/api/search", ["track_name": track.title, "artist_name": track.artist])
        let records = try JSONDecoder().decode([LyricsRecord].self, from: data).filter(\.hasLyrics)
        let result = LyricsLookup(selected: canMatchAutomatically ? LyricsMatcher.best(records, for: track, japaneseOnly: japaneseOnly) : nil,
            alternatives: Array(records.prefix(10)))
        return result
    }

    private struct CatalogResponse: Decodable { let results: [CatalogSong] }

    private func localizedTrack(_ track: MusicTrack) async throws -> MusicTrack? {
        if let cached = catalogCache[track.key] { return cached }
        do {
            var identifier = Int(track.storeID).flatMap { $0 > 0 ? $0 : nil }
            if identifier == nil {
                // Search in English first so artist/title/duration can be verified before accepting an ID.
                let songs = try await catalog("/search", ["term": track.title + " " + track.artist,
                    "entity": "song", "country": "us", "lang": "en_us", "limit": "10"])
                identifier = songs.first(where: { $0.matches(track) })?.trackId
            }
            guard let identifier else { return nil }
            let songs = try await catalog("/lookup", ["id": String(identifier), "country": "jp", "lang": "ja_jp"])
            guard let song = songs.first(where: { $0.trackId == identifier }),
                track.duration <= 0 || abs(song.track.duration - track.duration) <= 3 else { return nil }
            var localized = song.track
            if track.duration > 0 { localized.duration = track.duration }
            if catalogCache.count >= 100 { catalogCache.removeAll() }
            catalogCache[track.key] = localized
            return localized
        } catch is CancellationError { throw CancellationError() }
        catch { return nil } // Name lookup is optional; a failure must not discard lyric alternatives.
    }

    private func catalog(_ path: String, _ parameters: [String: String]) async throws -> [CatalogSong] {
        // Apple's public catalog search has a smaller request budget than the lyrics service.
        let wait = 3.1 - Date().timeIntervalSince(lastCatalogRequest)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        try Task.checkCancellation()
        lastCatalogRequest = Date()
        var url = URLComponents(string: "https://itunes.apple.com" + path)!
        url.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let (data, response) = try await session.data(from: url.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000 else { throw LyricsLookupError.network }
        return try JSONDecoder().decode(CatalogResponse.self, from: data).results
    }

    private func store(_ result: LyricsLookup, for key: String) {
        if cache.count >= 30 { cache.removeAll() }
        cache[key] = result
    }

    private func request(_ path: String, _ parameters: [String: String]) async throws -> Data {
        let previous = tail
        let finished = AsyncGate()
        tail = Task { await finished.wait() }
        if let previous { await previous.value }
        do {
            try Task.checkCancellation()
            let remaining = blockedUntil.timeIntervalSinceNow
            if remaining > 0 { throw LyricsLookupError.throttled(Int(ceil(remaining))) }
            let wait = 0.5 - Date().timeIntervalSince(lastRequest)
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            try Task.checkCancellation()
            var components = URLComponents(string: "https://lrclib.net" + path)!
            components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            var request = URLRequest(url: components.url!)
            request.setValue("LyricBridge/0.4 (https://github.com/Boyu1102/ipad-lyric-translator)", forHTTPHeaderField: "User-Agent")
            lastRequest = Date()
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw LyricsLookupError.network }
            if response.statusCode == 404 { throw LyricsLookupError.notFound }
            if response.statusCode == 429 || response.statusCode == 503 {
                let delay = max(1, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "30") ?? 30)
                blockedUntil = Date().addingTimeInterval(delay + Double.random(in: 0...delay * 0.2))
                throw LyricsLookupError.throttled(Int(ceil(blockedUntil.timeIntervalSinceNow)))
            }
            guard response.statusCode == 200 else { throw LyricsLookupError.network }
            guard data.count <= 2_000_000 else { throw LyricsLookupError.tooLarge }
            await finished.open()
            return data
        } catch {
            await finished.open()
            throw error
        }
    }
}

private actor AsyncGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
