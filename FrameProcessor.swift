import Foundation
import CoreImage
import CoreGraphics
import Vision
import ImageIO
import CoreMedia

final class FrameProcessor {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastTime: TimeInterval = 0

    func reset() { lastTime = 0 }

    func recognize(_ sample: CMSampleBuffer, options: CaptureOptions,
                   orientation: CGImagePropertyOrientation = .up) -> RecognitionPacket? {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTime >= 0.32, let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        lastTime = now
        return autoreleasepool {
            let source = CIImage(cvPixelBuffer: buffer).oriented(forExifOrientation: Int32(orientation.rawValue))
            let scale = min(1, 1800 / max(source.extent.width, source.extent.height))
            let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let image = context.createCGImage(scaled, from: scaled.extent) else { return nil }
            let width = min(0.85, max(0.25, options.fraction))
            let x = options.side == "right" ? 1 - width : 0
            let top = min(0.7, max(0.05, options.top))
            let bottom = min(0.98, max(top + 0.1, options.bottom))
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.01
            request.regionOfInterest = CGRect(x: x + 0.008, y: 1 - bottom,
                width: width - 0.016, height: bottom - top)
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                guard let map = GrayMap(image: image) else { return nil }
                let fragments = (request.results ?? []).compactMap { observation -> OCRFragment? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    let light = map.measure(box)
                    return OCRFragment(text: candidate.string,
                        x: box.minX, y: box.minY, width: box.width, height: box.height,
                        brightness: light.bright, contrast: light.contrast,
                        confidence: Double(candidate.confidence))
                }
                let selection = SentenceSelector.select(fragments, mode: options.selectionMode, maxLines: options.maxLines)
                return RecognitionPacket(lines: selection.map { [$0.text] } ?? [], status: "capturing")
            } catch {
                return RecognitionPacket(lines: [], status: "capturing", error: "文字识别暂时失败：\(error.localizedDescription)")
            }
        }
    }

    private struct GrayMap {
        let width: Int
        let height: Int
        var pixels: [UInt8]

        init?(image: CGImage) {
            let w = image.width
            let h = image.height
            width = w
            height = h
            var data = [UInt8](repeating: 0, count: w * h)
            let ok = data.withUnsafeMutableBytes { bytes -> Bool in
                guard let ctx = CGContext(data: bytes.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
                return true
            }
            guard ok else { return nil }
            pixels = data
        }

        func measure(_ box: CGRect) -> (bright: Double, contrast: Double) {
            let x0 = max(0, Int(box.minX * Double(width)))
            let x1 = min(width, max(x0 + 1, Int(box.maxX * Double(width))))
            let y0 = max(0, Int((1 - box.maxY) * Double(height)))
            let y1 = min(height, max(y0 + 1, Int((1 - box.minY) * Double(height))))
            var histogram = [Int](repeating: 0, count: 256)
            var count = 0
            for y in stride(from: y0, to: y1, by: 2) {
                for x in stride(from: x0, to: x1, by: 2) {
                    histogram[Int(pixels[y * width + x])] += 1
                    count += 1
                }
            }
            guard count > 0 else { return (0, 0) }
            func percentile(_ fraction: Double) -> Double {
                let target = max(1, Int(Double(count) * fraction))
                var sum = 0
                for i in histogram.indices {
                    sum += histogram[i]
                    if sum >= target { return Double(i) }
                }
                return 255
            }
            let bright = percentile(0.90)
            return (bright, bright - percentile(0.50))
        }
    }
}
