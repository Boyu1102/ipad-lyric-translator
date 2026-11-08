import Foundation

struct OCRFragment {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var brightness: Double
    var contrast: Double
    var confidence: Double
    var midY: Double { y + height / 2 }
}

struct SentenceSelection {
    var text: String
    var visualLines: Int
}

enum SentenceSelector {
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .filter { !$0.isWhitespace }
    }

    static func join(_ parts: [String]) -> String {
        var result = ""
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let last = result.unicodeScalars.last, let first = trimmed.unicodeScalars.first,
               isLatin(last.value), isLatin(first.value) { result += " " }
            result += trimmed
        }
        return result
    }

    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value) ||
            (0x3400...0x9FFF).contains($0.value) ||
            (0xFF66...0xFF9F).contains($0.value)
        }
    }

    private static func isLatin(_ value: UInt32) -> Bool {
        (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value)
    }

    private struct Line {
        var fragments: [OCRFragment]
        var center: Double {
            fragments.map(\.midY).reduce(0, +) / Double(fragments.count)
        }
        var height: Double { fragments.map(\.height).max() ?? 0 }
        var brightness: Double { fragments.map(\.brightness).max() ?? 0 }
        var contrast: Double { fragments.map(\.contrast).max() ?? 0 }
        var text: String {
            let sorted = fragments.sorted { $0.x < $1.x }
            var nonoverlapping: [OCRFragment] = []
            for fragment in sorted {
                if let last = nonoverlapping.last {
                    let overlap = max(0, min(last.x + last.width, fragment.x + fragment.width) - max(last.x, fragment.x))
                    if overlap > min(last.width, fragment.width) * 0.65 {
                        if fragment.confidence > last.confidence { nonoverlapping[nonoverlapping.count - 1] = fragment }
                        continue
                    }
                }
                nonoverlapping.append(fragment)
            }
            return SentenceSelector.join(nonoverlapping.map(\.text))
        }
    }

    static func select(_ fragments: [OCRFragment], mode: String, maxLines: Int) -> SentenceSelection? {
        let usable = fragments.filter { $0.confidence >= 0.35 && $0.height >= 0.009 && !$0.text.isEmpty }
            .sorted { $0.midY > $1.midY }
        var lines: [Line] = []
        for fragment in usable {
            if let index = lines.indices.min(by: {
                abs(lines[$0].center - fragment.midY) < abs(lines[$1].center - fragment.midY)
            }), abs(lines[index].center - fragment.midY) <= max(lines[index].height, fragment.height) * 0.45 {
                lines[index].fragments.append(fragment)
            } else {
                lines.append(Line(fragments: [fragment]))
            }
        }
        lines = lines.filter { containsJapanese($0.text) && normalize($0.text).count >= 2 }
            .sorted { $0.center > $1.center }
        guard !lines.isEmpty else { return nil }
        let limit = min(3, max(1, maxLines))
        let chosen: [Line]
        if mode == "topThree" {
            chosen = Array(lines.prefix(limit))
        } else {
            guard let strongest = lines.max(by: { $0.brightness < $1.brightness }),
                  strongest.brightness >= 200, strongest.contrast >= 18 else { return nil }
            let threshold = max(200, strongest.brightness - 24)
            // Only the bright line and nearby bright wrapped lines qualify. Dim context never
            // gets translated merely because it remains visible above or below the singer.
            let nearby = lines.filter {
                $0.brightness >= threshold && $0.contrast >= 18 &&
                abs($0.center - strongest.center) <= max(strongest.height, $0.height) * 3.4
            }
            chosen = Array(nearby.sorted {
                abs($0.center - strongest.center) < abs($1.center - strongest.center)
            }.prefix(limit)).sorted { $0.center > $1.center }
        }
        let text = join(chosen.map(\.text))
        guard !text.isEmpty else { return nil }
        return SentenceSelection(text: text, visualLines: chosen.count)
    }
}

/// Stabilize a whole selected sentence, never emit individual OCR fragments.
struct SentenceStabilizer {
    private var pending = ""
    private var pendingText = ""
    private var firstSeen: TimeInterval = 0
    private var lastSeen: TimeInterval = 0
    private var samples = 0
    private var lastEmitted = ""

    mutating func reset() { self = SentenceStabilizer() }

    mutating func observe(_ text: String, at time: TimeInterval) -> String? {
        let key = SentenceSelector.normalize(text)
        if key.isEmpty {
            if time - lastSeen > 0.8 { pending = ""; samples = 0 }
            return nil
        }
        if key != pending {
            pending = key
            pendingText = text
            firstSeen = time
            samples = 1
        } else {
            samples += 1
            if text.count >= pendingText.count { pendingText = text }
        }
        lastSeen = time
        guard samples >= 3, time - firstSeen >= 0.8, key != lastEmitted else { return nil }
        lastEmitted = key
        return pendingText
    }
}
