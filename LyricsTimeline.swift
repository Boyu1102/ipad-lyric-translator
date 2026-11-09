import Foundation
import NaturalLanguage

enum LyricLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja", english = "en", romanized, unknown
    var id: String { rawValue }
    var label: String {
        switch self {
        case .japanese: return "日语"
        case .english: return "英语"
        case .romanized: return "罗马音"
        case .unknown: return "未识别语言"
        }
    }
    static func detect(_ text: String) -> LyricLanguage {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let japanese = letters.filter { (0x3040...0x30FF).contains($0.value) || (0xFF66...0xFF9F).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }.count
        let kana = letters.filter { (0x3040...0x30FF).contains($0.value) || (0xFF66...0xFF9F).contains($0.value) }.count
        // A few kana in an otherwise romanized song do not make it Japanese original text.
        if kana > 0 && Double(japanese) / Double(max(1, letters.count)) >= 0.12 { return .japanese }
        if kana > 0 { return .romanized }
        let words = text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let markers: Set<String> = ["wa", "wo", "ga", "ni", "desu", "masu", "kimi", "boku", "watashi", "anata", "kokoro", "sekai", "kedo", "shite", "sore", "kore", "koto", "kara", "nani", "iru", "naru", "yume"]
        let matches = words.filter { markers.contains($0) }.count
        if matches >= 3 && Double(matches) / Double(max(1, words.count)) >= 0.10 { return .romanized }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage == .english ? .english : .unknown
    }
}

enum TranslationTarget: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans", english = "en"
    var id: String { rawValue }
    var label: String { self == .chinese ? "中文" : "English" }
    static func cacheKey(source: String, target: String, text: String) -> String {
        source + "|" + target + "|" + text
    }
}

struct MusicTrack: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var storeID: String = ""
    var libraryLyrics: String? = nil
    var key: String {
        [storeID, title, artist, album, String(duration.isFinite ? Int(min(864000, max(0, duration)).rounded()) : 0)].joined(separator: "|")
    }
}

struct LyricCue: Identifiable, Equatable, Sendable {
    let id: Int
    let time: Double?
    let text: String
}

struct LyricsDocument: Sendable {
    var cues: [LyricCue]
    var isTimed: Bool
    var source: String
    var instrumental: Bool = false
    var language: LyricLanguage { LyricLanguage.detect(cues.map(\.text).joined(separator: "\n")) }

    func index(at playbackTime: Double, offset: Double = 0) -> Int? {
        guard isTimed, playbackTime.isFinite else { return nil }
        let target = playbackTime + offset
        var low = 0
        var high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if (cues[middle].time ?? .infinity) <= target { low = middle + 1 }
            else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }
}

enum LRCParser {
    static func parse(_ rawInput: String, source: String) -> LyricsDocument {
        let input = rawInput.replacingOccurrences(of: "\u{FEFF}", with: "")
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):([0-5]?\d)(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:\s*(-?\d+)\s*\]"#, options: .caseInsensitive)
        let wordTimestamp = try! NSRegularExpression(pattern: #"<\d{1,3}:[0-5]?\d(?:[.:]\d{1,3})?>"#)
        let fullRange = NSRange(input.startIndex..., in: input)
        var offset = 0.0
        if let match = offsetPattern.firstMatch(in: input, range: fullRange),
           let range = Range(match.range(at: 1), in: input), let milliseconds = Double(input[range]) {
            offset = milliseconds / 1000
        }
        var timed: [(time: Double, text: String, order: Int)] = []
        var plain: [String] = []
        for raw in input.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..., in: line)
            let matches = timestamp.matches(in: line, range: range)
            if let first = matches.first, first.range.location == 0, let last = matches.last,
               let textRange = Range(NSRange(location: NSMaxRange(last.range), length: (line as NSString).length - NSMaxRange(last.range)), in: line) {
                let content = String(line[textRange]).trimmingCharacters(in: .whitespaces)
                let text = wordTimestamp.stringByReplacingMatches(in: content,
                    range: NSRange(content.startIndex..., in: content), withTemplate: "")
                for match in matches {
                    func number(_ group: Int) -> String? {
                        guard let r = Range(match.range(at: group), in: line) else { return nil }
                        return String(line[r])
                    }
                    guard let minute = number(1).flatMap(Double.init), let second = number(2).flatMap(Double.init) else { continue }
                    let fraction = number(3).flatMap { Double("0." + $0) } ?? 0
                    timed.append((max(0, minute * 60 + second + fraction + offset), text, timed.count))
                }
            } else if !(line.hasPrefix("[") && line.hasSuffix("]")) {
                plain.append(line)
            }
        }
        if !timed.isEmpty {
            timed.sort { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }
            var merged: [(Double, String)] = []
            for item in timed {
                if let last = merged.last, abs(last.0 - item.time) < 0.001 {
                    if !item.text.isEmpty && !last.1.components(separatedBy: "\n").contains(item.text) {
                        merged[merged.count - 1].1 = last.1.isEmpty ? item.text : last.1 + "\n" + item.text
                    }
                } else { merged.append((item.time, item.text)) }
            }
            return LyricsDocument(cues: merged.enumerated().map { LyricCue(id: $0.offset, time: $0.element.0, text: $0.element.1) },
                isTimed: true, source: source)
        }
        return LyricsDocument(cues: plain.enumerated().map { LyricCue(id: $0.offset, time: nil, text: $0.element) },
            isTimed: false, source: source)
    }
}

struct LyricsRecord: Decodable, Identifiable, Sendable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?

    private var usesPlainOriginal: Bool {
        LyricLanguage.detect(plainLyrics ?? "") == .japanese && LyricLanguage.detect(syncedLyrics ?? "") != .japanese
    }
    var hasSyncedLyrics: Bool { !usesPlainOriginal && !(syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    var hasLyrics: Bool { instrumental || hasSyncedLyrics || !(plainLyrics?.isEmpty ?? true) }
    var likelyJapanese: Bool {
        if instrumental { return true }
        return language == .japanese
    }
    var language: LyricLanguage { LyricLanguage.detect(hasSyncedLyrics ? (syncedLyrics ?? "") : (plainLyrics ?? "")) }
    var document: LyricsDocument {
        if instrumental { return LyricsDocument(cues: [], isTimed: true, source: "LRCLIB", instrumental: true) }
        let raw = hasSyncedLyrics ? syncedLyrics! : (plainLyrics ?? "")
        return LRCParser.parse(raw, source: "LRCLIB · \(albumName)")
    }
}

enum LyricsMatcher {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    static func score(_ record: LyricsRecord, for track: MusicTrack, japaneseOnly: Bool = true) -> Double? {
        guard record.hasLyrics else { return nil }
        if !record.instrumental {
            guard record.language == .japanese || (!japaneseOnly && record.language == .english) else { return nil }
        }
        let title = normalized(track.title), otherTitle = normalized(record.trackName)
        let artist = normalized(track.artist), otherArtist = normalized(record.artistName)
        guard !title.isEmpty, !artist.isEmpty,
              title == otherTitle || (title.count >= 4 && otherTitle.contains(title)),
              artist == otherArtist || (artist.count >= 4 && otherArtist.contains(artist)) else { return nil }
        let requestedVersion = normalized(track.title + " " + track.album)
        let suppliedVersion = normalized(record.trackName + " " + record.albumName)
        for marker in ["live", "ライブ", "ライヴ", "remix", "リミックス", "karaoke", "カラオケ", "acoustic", "アコースティック", "piano", "ピアノ", "instrumental", "gamever", "tvsize"] {
            if requestedVersion.contains(marker) != suppliedVersion.contains(marker) { return nil }
        }
        let difference = abs(record.duration - track.duration)
        if track.duration > 0 && difference > 3 { return nil }
        var score = title == otherTitle ? 60.0 : 45.0
        score += artist == otherArtist ? 35 : 20
        if track.duration > 0 { score += max(0, 20 - difference * 5) }
        if !track.album.isEmpty && normalized(record.albumName) == normalized(track.album) { score += 20 }
        if record.hasSyncedLyrics { score += 15 }
        return score
    }

    static func best(_ records: [LyricsRecord], for track: MusicTrack, japaneseOnly: Bool = true) -> LyricsRecord? {
        var selected: LyricsRecord?
        var highest = -Double.infinity
        for record in records {
            guard let value = score(record, for: track, japaneseOnly: japaneseOnly) else { continue }
            if value > highest || (value == highest && record.id < (selected?.id ?? Int.max)) {
                selected = record
                highest = value
            }
        }
        return selected
    }
}

struct CatalogSong: Decodable {
    var trackId: Int
    var trackName: String
    var artistName: String
    var collectionName: String?
    var trackTimeMillis: Double?
    var track: MusicTrack {
        MusicTrack(title: trackName, artist: artistName, album: collectionName ?? "",
            duration: (trackTimeMillis ?? 0) / 1000, storeID: String(trackId))
    }
    func matches(_ requested: MusicTrack) -> Bool {
        LyricsMatcher.normalized(trackName) == LyricsMatcher.normalized(requested.title) &&
        LyricsMatcher.normalized(artistName) == LyricsMatcher.normalized(requested.artist) &&
        (requested.duration <= 0 || abs(track.duration - requested.duration) <= 3)
    }
}
