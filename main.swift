import Foundation

func fragment(_ text: String, _ x: Double, _ y: Double, light: Double = 245) -> OCRFragment {
    OCRFragment(text: text, x: x, y: y, width: 0.15, height: 0.04,
        brightness: light, contrast: light > 200 ? 95 : 15, confidence: 0.9)
}

let split = [fragment("これは", 0.5, 0.6), fragment("一つの", 0.67, 0.6), fragment("文です", 0.84, 0.6),
    fragment("前の歌詞", 0.5, 0.72, light: 145), fragment("次の歌詞", 0.5, 0.48, light: 150)]
assert(SentenceSelector.select(split, mode: "highlight", maxLines: 3)?.text == "これは一つの文です")
assert(SentenceSelector.select([fragment("暗い歌詞", 0.5, 0.6, light: 150)], mode: "highlight", maxLines: 3) == nil)
let wrapped = [fragment("これは長い", 0.5, 0.6), fragment("一つの文です", 0.5, 0.53)]
assert(SentenceSelector.select(wrapped, mode: "highlight", maxLines: 3)?.text == "これは長い一つの文です")
assert(SentenceSelector.select(wrapped, mode: "highlight", maxLines: 1)?.visualLines == 1)
assert(SentenceSelector.select(split, mode: "topThree", maxLines: 3)?.visualLines == 3)
assert(SentenceSelector.join(["hello", "world"]) == "hello world")
assert(SentenceSelector.join(["これは", "日本語です"]) == "これは日本語です")
var stabilizer = SentenceStabilizer()
assert(stabilizer.observe("これ", at: 0) == nil)
assert(stabilizer.observe("これは文です", at: 0.3) == nil)
assert(stabilizer.observe("これは文です", at: 0.7) == nil)
assert(stabilizer.observe("これは文です", at: 1.2) == "これは文です")
assert(stabilizer.observe("これは文です", at: 1.6) == nil)
stabilizer.reset()
assert(stabilizer.observe("これは文です", at: 2) == nil)
print("Sentence grouping, highlight rejection, wrapping, three-line limit and stabilization passed.")
