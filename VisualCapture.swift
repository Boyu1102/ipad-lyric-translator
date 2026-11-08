@preconcurrency import ScreenCaptureKit
import Foundation
import CoreMedia

@MainActor
final class VisualCapture: NSObject {
    var onPacket: ((RecognitionPacket) -> Void)?
    var onState: ((String, Bool) -> Void)?
    private let picker = SCContentSharingPicker.shared
    private var observer: VisualPickerObserver!
    private var stream: SCStream?
    private let worker = VisualFrameOutput()
    private var installedObserver = false
    private var epoch = UUID()
    private var awaitingPicker = false

    override init() {
        super.init()
        observer = VisualPickerObserver(owner: self)
        worker.onPacket = { [weak self] packet, epoch in
            Task { @MainActor in
                guard let self, self.epoch == epoch else { return }
                self.onPacket?(packet)
            }
        }
    }

    func configure(_ options: CaptureOptions) { worker.configure(options) }

    func start() {
        if stream != nil { onState?("正在读取当前歌词", true); return }
        guard !awaitingPicker else { return }
        awaitingPicker = true
        if !installedObserver { picker.add(observer); installedObserver = true }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        picker.defaultConfiguration = configuration
        picker.isActive = true
        onState?("请在系统提示中允许读取屏幕画面", false)
        picker.present()
    }

    func received(_ filter: SCContentFilter) async {
        awaitingPicker = false
        epoch = UUID()
        let thisEpoch = epoch
        let old = stream
        stream = nil
        try? await old?.stopCapture()
        guard thisEpoch == epoch else { return }
        let configuration = SCStreamConfiguration()
        // Audio is disabled at the capture source, rather than discarded after capture.
        configuration.capturesAudio = false
        // Do not attach microphone output or activate any AVAudioSession. FrameProcessor
        // throttles OCR itself; the macOS-only timing/queue properties aren't used on iPad.
        do {
            worker.begin(epoch: thisEpoch)
            let newStream = SCStream(filter: filter, configuration: configuration, delegate: observer)
            try newStream.addStreamOutput(worker, type: .screen, sampleHandlerQueue: worker.queue)
            stream = newStream
            try await newStream.startCapture()
            guard epoch == thisEpoch else { try? await newStream.stopCapture(); return }
            onState?("已开始，只读取画面", true)
        } catch {
            guard epoch == thisEpoch else { return }
            stream = nil
            onState?("无法开始读取画面：\(error.localizedDescription)", false)
        }
    }

    func pickerCancelled() {
        awaitingPicker = false
        if stream == nil { onState?("未开始：你取消了屏幕授权", false) }
    }
    func pickerFailed(_ error: Error) {
        awaitingPicker = false
        onState?("系统未能打开屏幕授权：\(error.localizedDescription)", false)
    }
    func unexpectedlyStopped(_ stoppedStream: SCStream, error: Error) {
        guard stream === stoppedStream else { return }
        stream = nil
        epoch = UUID()
        onState?("读取已停止：\(error.localizedDescription)", false)
    }
    func stop() async {
        epoch = UUID()
        awaitingPicker = false
        let old = stream
        stream = nil
        picker.isActive = false
        try? await old?.stopCapture()
        onState?("已停止", false)
    }
}

private final class VisualPickerObserver: NSObject, SCContentSharingPickerObserver, SCStreamDelegate, @unchecked Sendable {
    private weak var owner: VisualCapture?
    init(owner: VisualCapture) { self.owner = owner }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await owner?.received(filter) }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in owner?.pickerCancelled() }
    }
    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in owner?.pickerFailed(error) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in owner?.unexpectedlyStopped(stream, error: error) }
    }
}

private final class VisualFrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.lyricbridge.visual-ocr", qos: .userInitiated)
    var onPacket: ((RecognitionPacket, UUID) -> Void)?
    private let processor = FrameProcessor()
    private var options = CaptureOptions()
    private var epoch = UUID()
    func configure(_ options: CaptureOptions) {
        queue.async { self.options = options; self.processor.reset() }
    }
    func begin(epoch: UUID) {
        queue.async { self.epoch = epoch; self.processor.reset() }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, !options.stop else { return }
        if let packet = processor.recognize(sampleBuffer, options: options) { onPacket?(packet, epoch) }
    }
}
