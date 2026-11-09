import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let timed = LRCParser.parse("[ar:Example]\n[00:01.20][00:03.45]朝の光\n[00:04.00]\n[00:06.00]歩いていこう", source: "test")
check(timed.isTimed, "LRC timestamps should be detected")
check(timed.cues.count == 4, "Multiple tags and blank instrumental markers must be retained")
check(timed.index(at: 0) == nil, "Intro must not display the first sentence early")
check(timed.index(at: 1.2) == 0, "Exact timestamp should select the current sentence")
check(timed.index(at: 3.5) == 1, "Playback progress must advance past the first sentence")
check(timed.index(at: 4.1) == 2 && timed.cues[2].text.isEmpty, "Instrumental must clear stale text")
check(timed.index(at: 6.2) == 3, "Lyrics must resume after an instrumental")
check(timed.index(at: 1.3) == 0, "Seeking backward must select an earlier sentence")
check(timed.index(at: 3.0, offset: 0.5) == 1, "Positive timing correction advances lyrics")
check(timed.index(at: .nan) == nil, "Invalid player timestamps must not select a sentence")

let shifted = LRCParser.parse("[offset:-500]\n[00:01.000]空の色\n[00:02:25]雲の形", source: "test")
check(abs((shifted.cues.first?.time ?? -1) - 0.5) < 0.0001, "LRC metadata offset must be applied")
check(abs((shifted.cues.last?.time ?? -1) - 1.75) < 0.0001, "Colon-style fractions must be read correctly")
let duplicates = LRCParser.parse("[00:02.00]一行目\n[00:02.00]二行目\n[00:02.00]一行目", source: "test")
check(duplicates.cues.count == 1 && duplicates.cues[0].text == "一行目\n二行目", "Same-time visual lines must form one cue without duplicates")
let enhanced = LRCParser.parse("[00:01.00]<00:01.00>朝<00:01.50>です", source: "test")
check(enhanced.cues[0].text == "朝です", "Word timing tags must not fragment a sentence")
let plain = LRCParser.parse("[ti:Example]\n一つの文です\n次の文です", source: "test")
check(!plain.isTimed && plain.cues.count == 2, "Plain text must stay manual, without fabricated timestamps")
check(plain.index(at: 30) == nil, "Unsynced lyrics must not pretend to follow Music")
check(LRCParser.parse("\u{FEFF}[00:01.00]朝の光", source: "test").cues.first?.time == 1, "UTF-8 BOM must not hide the first timestamp")

func record(_ id: Int, duration: Double, album: String = "Studio", title: String = "Example Song", artist: String = "Example Artist", sync: String? = "[00:01.00]一つの文です") -> LyricsRecord {
    LyricsRecord(id: id, trackName: title, artistName: artist, albumName: album, duration: duration,
        instrumental: false, plainLyrics: "一つの文です", syncedLyrics: sync)
}
let studio = MusicTrack(title: "Example Song", artist: "Example Artist", album: "Studio", duration: 214)
let wrongDuration = record(1, duration: 241, album: "Live")
let alternate = record(2, duration: 217)
let correct = record(3, duration: 214)
check(LyricsMatcher.best([wrongDuration, alternate, correct], for: studio)?.id == 3, "Version selection must use duration rather than first search result")
check(LyricsMatcher.best([record(5, duration: 214, artist: "Someone Else")], for: studio) == nil, "A different artist must not be auto-selected")
check(LyricsMatcher.best([record(6, duration: 214, album: "Live")], for: studio) == nil, "Live and studio editions must not be silently substituted")
check(LyricsMatcher.best([record(7, duration: 214, sync: nil), correct], for: studio)?.id == 3, "Timed lyrics should win when metadata matches")
check(LyricsMatcher.normalized("Ｅxample - Song") == LyricsMatcher.normalized("Example Song"), "Metadata normalization should handle punctuation and width")
let decoded = try JSONDecoder().decode(LyricsRecord.self, from: Data(#"{"id":9,"trackName":"Example Song","artistName":"Example Artist","albumName":"Studio","duration":214,"instrumental":false,"plainLyrics":null,"syncedLyrics":"[00:01.00]一つの文です"}"#.utf8))
check(decoded.document.isTimed && decoded.document.cues.count == 1, "Provider JSON must decode into timed full-line cues")
let translatedInsteadOfOriginal = record(10, duration: 214, sync: "[00:01.00]This is a translated line")
check(translatedInsteadOfOriginal.language == .japanese && !translatedInsteadOfOriginal.document.isTimed,
    "Japanese plain original should replace translated/romanized sync without fabricating timestamps")
let romanized = LyricsRecord(id: 11, trackName: "Example Song", artistName: "Example Artist", albumName: "Studio", duration: 214,
    instrumental: false, plainLyrics: "Kimi wa boku no kokoro ni iru ね", syncedLyrics: "[00:01.00]Kimi wa boku no kokoro ni iru ね")
check(!romanized.likelyJapanese && LyricsMatcher.best([romanized], for: studio) == nil,
    "Sparse kana must not disguise romanized lyrics as Japanese original")
check(LyricLanguage.detect("Kimi wa boku no kokoro ni iru") == .romanized, "Pure Latin romaji must not be translated as English")
let englishText = "The morning light is shining through the window. I remember every moment we spent together."
let english = LyricsRecord(id: 12, trackName: "Example Song", artistName: "Example Artist", albumName: "Studio", duration: 214,
    instrumental: false, plainLyrics: englishText, syncedLyrics: "[00:01.00]" + englishText)
check(english.language == .english, "English song lyrics should be detected")
check(LyricsMatcher.best([english], for: studio) == nil, "English translations must not override Japanese original selection")
check(LyricsMatcher.best([english], for: studio, japaneseOnly: false)?.id == 12, "English songs should be available for translation to Chinese")
check(TranslationTarget.cacheKey(source: "ja", target: "en", text: "朝です") != TranslationTarget.cacheKey(source: "ja", target: "zh-Hans", text: "朝です"),
    "Switching translation target must never reuse the other language's cached result")
let catalogSong = CatalogSong(trackId: 123, trackName: "Example Song", artistName: "Example Artist", collectionName: "Studio", trackTimeMillis: 214000)
check(catalogSong.matches(studio), "Catalog search must validate English title, artist and duration before accepting an ID")
check(!catalogSong.matches(MusicTrack(title: "Example Song", artist: "Another Artist", album: "", duration: 214)), "Catalog localization must reject another artist")
check(!catalogSong.matches(MusicTrack(title: "Example Song", artist: "Example Artist", album: "", duration: 160)), "Catalog localization must reject short/game versions")
print("Timeline parsing, seek/advance/instrumental behavior, full-line lyrics and version matching tests passed.")

// Exercise the real service with deterministic HTTP fixtures, never real song lyrics.
final class FixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        var code = 200
        var object: Any = [:]
        if url.host == "itunes.apple.com" {
            let localized = url.path == "/lookup"
            check(values["country"] == (localized ? "jp" : "us"), "Catalog search must use the correct metadata storefront")
            check(values["lang"] == (localized ? "ja_jp" : "en_us"), "Catalog localization must request the intended name language")
            object = ["results": [["trackId": 123, "trackName": localized ? "朝のうた" : "Example Song",
                "artistName": localized ? "テスト歌手" : "Example Artist", "collectionName": "Studio", "trackTimeMillis": 214000]]]
        } else if values["track_name"] == "朝のうた" {
            object = ["id": 99, "trackName": "朝のうた", "artistName": "テスト歌手", "albumName": "Studio", "duration": 214,
                "instrumental": false, "plainLyrics": "朝の光が見える", "syncedLyrics": "[00:01.00]朝の光が見える"]
        } else if url.path == "/api/get" {
            code = 404
        } else {
            object = [] as [String]
        }
        let data = try! JSONSerialization.data(withJSONObject: object)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let fixtureConfig = URLSessionConfiguration.ephemeral
fixtureConfig.protocolClasses = [FixtureProtocol.self]
let fixtureService = LyricsService(session: URLSession(configuration: fixtureConfig))
let storeTrack = MusicTrack(title: "Example Song", artist: "Example Artist", album: "Studio", duration: 214, storeID: "123")
let localizedLookup = try await fixtureService.lookup(storeTrack)
check(localizedLookup.selected?.id == 99 && localizedLookup.selected?.language == .japanese,
    "A verified store ID must resolve localized Japanese metadata and select original timed lyrics")
let nameLookup = try await fixtureService.lookup(studio)
check(nameLookup.selected?.id == 99, "Missing store IDs must use a verified English catalog search before Japanese localization")
let nativeTrack = MusicTrack(title: "Library Song", artist: "Library Artist", album: "", duration: 100,
    libraryLyrics: "朝の風が吹いている\n今日も歩いていこう")
let nativeLookup = try await fixtureService.lookup(nativeTrack)
check(nativeLookup.fallback?.language == .japanese && nativeLookup.fallback?.isTimed == false,
    "Available library lyrics should remain usable without inventing a timeline when external lyrics are missing")
let englishCache = TranslationTarget.cacheKey(source: "en", target: "zh-Hans", text: englishText)
check(englishCache != TranslationTarget.cacheKey(source: "ja", target: "zh-Hans", text: englishText), "Source language must also partition translation caches")
print("Catalog localization and no-store-ID HTTP fixture tests passed.")
