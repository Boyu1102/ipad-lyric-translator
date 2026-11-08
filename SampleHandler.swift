import ReplayKit
import Vision
import ImageIO

final class SampleHandler: RPBroadcastSampleHandler {
    private let link = CaptureLink()
    private var lastTime: TimeInterval = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        lastTime = 0
        link.start { [weak self] in
            self?.finishBroadcastWithError(NSError(
                domain: "LyricBridge", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "已停止歌词识别"]))
        }
    }

    override func broadcastFinished() {
        link.send(RecognitionPacket(lines: [], status: "stopped"))
        link.stop()
    }

    override func broadcastPaused() {
        link.send(RecognitionPacket(lines: [], status: "paused"))
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Intentionally ignore application audio and microphone buffers.
        guard sampleBufferType == .video,
              let options = link.snapshot(), !options.stop else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTime >= 0.8 else { return }
        lastTime = now
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let rawOrientation = CMGetAttachment(
                sampleBuffer, key: RPVideoSampleOrientationKey as CFString,
                attachmentModeOut: nil) as? NSNumber
            let orientation = rawOrientation.flatMap {
                CGImagePropertyOrientation(rawValue: $0.uint32Value)
            } ?? .up
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.012
            let width = min(0.85, max(0.3, options.fraction))
            request.regionOfInterest = CGRect(
                x: options.side == "right" ? 1 - width : 0,
                y: 0.06, width: width, height: 0.88)
            do {
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation).perform([request])
                let observations = (request.results ?? []).sorted {
                    if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.018 {
                        return $0.boundingBox.midY > $1.boundingBox.midY
                    }
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                let lines = observations.compactMap { observation -> String? in
                    guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.35 else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.count >= 2, Self.containsJapaneseScript(text) else { return nil }
                    return text
                }
                link.send(RecognitionPacket(lines: Array(lines.prefix(24)), status: "capturing"))
            } catch {
                link.send(RecognitionPacket(lines: [], status: "capturing", error: "文字识别失败：\(error.localizedDescription)"))
            }
        }
    }

    private static func containsJapaneseScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value) ||
            (0x3400...0x9FFF).contains(scalar.value) ||
            (0xFF66...0xFF9F).contains(scalar.value)
        }
    }
}
