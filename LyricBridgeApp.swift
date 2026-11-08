import SwiftUI
import ReplayKit
import Translation
import UIKit

@main
@MainActor
struct LyricBridgeApp: App {
    @StateObject private var model = LyricModel()
    var body: some Scene {
        WindowGroup { ContentView(model: model) }
    }
}

struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
        picker.showsMicrophoneButton = false
        // Read the embedded extension's actual ID because personal signing can rename it.
        if let plugins = Bundle.main.builtInPlugInsURL,
           let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil),
           let extensionURL = urls.first(where: { $0.pathExtension == "appex" }) {
            picker.preferredExtension = Bundle(url: extensionURL)?.bundleIdentifier
        }
        return picker
    }
    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {}
}

@MainActor
struct ContentView: View {
    @ObservedObject var model: LyricModel
    @State private var autoScroll = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("音乐放左边，译文放右边")
                        .font(.headline)
                    Text("请保持两个 App 并排显示。识别区域应只覆盖音乐歌词。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(model.translationReady ? "重试翻译" : "启用翻译") {
                            model.retryTranslation()
                        }.buttonStyle(.bordered)
                        Spacer()
                        Button("准备识别") { model.armCapture() }
                        BroadcastButton().frame(width: 48, height: 48)
                        Button("停止") { model.stopCapture() }.tint(.red)
                    }
                    Text("先点“准备识别”，再点圆形录屏按钮，在系统弹窗中开始直播。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: model.isReceiving ? "circle.fill" : "circle")
                            .foregroundStyle(model.isReceiving ? Color.green : Color.gray)
                        Text(model.status)
                    }.font(.caption)
                    Text(model.translationStatus).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("调整识别区域") {
                        Picker("音乐位置", selection: $model.side) {
                            Text("左侧").tag("left")
                            Text("右侧").tag("right")
                        }.pickerStyle(.segmented)
                        HStack {
                            Text("占全屏宽度")
                            Slider(value: $model.fraction, in: 0.3...0.85, step: 0.01)
                            Text("\(Int(model.fraction * 100))%")
                                .monospacedDigit().frame(width: 40)
                        }.font(.caption)
                        Text("例如音乐占屏幕左半边，选择左侧和 50%。请勿把本 App 包进识别区域。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding()
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if model.rows.isEmpty {
                                Text("识别到的日语歌词和中文译文会显示在这里。")
                                    .foregroundStyle(.secondary).padding(.vertical, 32)
                            }
                            ForEach(model.rows) { row in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(row.original).font(.title3).foregroundStyle(.secondary)
                                    if let translated = row.translated {
                                        Text(translated).font(.title3.weight(.medium))
                                    } else {
                                        Text(row.error ?? "等待翻译…")
                                            .font(.body).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled).id(row.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding()
                    }
                    .onChange(of: model.rows.count) { _, _ in
                        if autoScroll { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    }
                }
                Divider()
                HStack {
                    Toggle("自动滚动", isOn: $autoScroll).fixedSize()
                    Spacer()
                    Button("换歌 / 清空") { model.clear() }
                }.font(.caption).padding()
            }
            .navigationTitle("歌词译伴 · 测试版")
            .navigationBarTitleDisplayMode(.inline)
            .translationTask(model.configuration) { session in
                await model.translate(using: session)
            }
        }
    }
}
