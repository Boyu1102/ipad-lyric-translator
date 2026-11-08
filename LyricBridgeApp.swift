import SwiftUI
import Translation

@main
@MainActor
struct LyricBridgeApp: App {
    @StateObject private var model = LyricModel()
    var body: some Scene {
        WindowGroup { ContentView(model: model) }
    }
}

@MainActor
struct ContentView: View {
    @ObservedObject var model: LyricModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var autoScroll = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button("开始翻译", systemImage: "play.fill") { model.start() }
                            .buttonStyle(.borderedProminent)
                        Button("停止") { model.stop() }.buttonStyle(.bordered)
                        Spacer()
                        Button("重新连接") { model.retryTranslation() }.font(.caption)
                    }
                    Text("开始后按系统提示允许读取画面；不需要到控制中心另开共享。")
                        .font(.caption).foregroundStyle(.secondary)
                    Label(model.status, systemImage: model.isReceiving ? "circle.fill" : "circle")
                        .font(.caption).foregroundStyle(model.isReceiving ? Color.green : Color.secondary)
                    Text(model.translationStatus).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("歌词位置与识别方式") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("音乐位置", selection: $model.side) {
                                Text("音乐在左").tag("left")
                                Text("音乐在右").tag("right")
                            }.pickerStyle(.segmented)
                            HStack {
                                Text("音乐窗口宽度")
                                Slider(value: $model.fraction, in: 0.25...0.85, step: 0.01)
                                Text("\(Int(model.fraction * 100))%")
                                    .monospacedDigit().frame(width: 40)
                            }.font(.caption)
                            Picker("识别方式", selection: $model.selectionMode) {
                                Text("只取高亮歌词").tag("highlight")
                                Text("取歌词区域前3行").tag("topThree")
                            }.pickerStyle(.segmented)
                            Picker("最多视觉行数", selection: $model.maxLines) {
                                Text("1 行").tag(1)
                                Text("2 行").tag(2)
                                Text("3 行").tag(3)
                            }.pickerStyle(.segmented)
                            Text("同一行的碎片会先拼接，连续换行最多合并3行；整句稳定后才翻译。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 6)
                    }
                }.padding()
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if model.rows.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("等待完整歌词").font(.title2.weight(.medium))
                                    Text("默认只翻译当前高亮的歌词，暗色上下文不加入列表。请保持音乐和译文窗口并排可见。")
                                        .foregroundStyle(.secondary)
                                }.padding(.vertical, 30)
                            }
                            ForEach(model.rows) { row in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(row.original).font(.title3).foregroundStyle(.secondary)
                                    Text(row.translated ?? row.error ?? "正在翻译整句…")
                                        .font(.title2.weight(.medium))
                                        .foregroundStyle(row.translated == nil ? Color.secondary : Color.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled).id(row.id)
                                Divider()
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding()
                    }
                    .onChange(of: model.rows.count) { _, _ in
                        if autoScroll { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    }
                    .onChange(of: model.rows.last?.translated) { _, _ in
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
            .navigationTitle("歌词译伴 · 整句版 0.2")
            .navigationBarTitleDisplayMode(.inline)
        }
        .translationTask(model.configuration) { session in await model.translate(using: session) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && model.isReceiving { model.ensureTranslation() }
        }
    }
}
