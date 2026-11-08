import SwiftUI
import Translation
import UniformTypeIdentifiers

@main
@MainActor
struct LyricBridgeApp: App {
    @StateObject private var model = LyricModel()
    var body: some Scene { WindowGroup { ContentView(model: model) } }
}

@MainActor
struct ContentView: View {
    @ObservedObject var model: LyricModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var searching = false
    @State private var title = ""
    @State private var artist = ""
    @State private var duration = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("不共享屏幕，直接跟随 Apple Music")
                        .font(.title2.weight(.semibold))
                    Text("Music 可以在后台播放；这里按播放时间显示当前整句，不必分屏。请先停止旧版的屏幕共享。")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button(model.connecting ? "正在连接…" : "连接 Apple Music", systemImage: "music.note") {
                            Task { await model.connect() }
                        }.buttonStyle(.borderedProminent).disabled(model.connecting)
                        if model.connected { Button("停止跟随") { model.stopFollowing() }.buttonStyle(.bordered) }
                    }
                    if let track = model.track {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(track.title).font(.title2.weight(.medium))
                            Text(track.artist).foregroundStyle(.secondary)
                            HStack {
                                Text(model.isPlaying ? "播放中" : "已暂停 / 等待播放")
                                if model.positionAvailable {
                                    Text("\(time(model.position)) / \(time(track.duration))").monospacedDigit()
                                }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .top) {
                        if model.fetching { ProgressView().controlSize(.small) }
                        Text(model.status).font(.callout).foregroundStyle(.secondary)
                    }
                    currentSentence
                    if !model.upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("接下来").font(.caption).foregroundStyle(.secondary)
                            ForEach(model.upcoming) { cue in
                                Text(cue.text).font(.title3).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let document = model.document, !document.cues.isEmpty, !model.automaticTimeline {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(document.isTimed ? "暂时读不到 Music 时间轴，可手动切句" : "本版本没有时间轴，可手动切句")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("上一句") { model.moveManually(-1) }
                                Button("下一句") { model.moveManually(1) }
                            }.buttonStyle(.bordered)
                        }
                    }
                    if !model.alternatives.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("选择歌曲版本").font(.headline)
                            ForEach(model.alternatives) { record in
                                Button { model.choose(record) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(record.trackName) · \(record.artistName)")
                                        Text("\(record.albumName) · \(time(record.duration)) · \(record.hasSyncedLyrics ? "同步歌词" : "普通歌词")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                    Divider()
                    Text(model.translationStatus).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("重试翻译") { model.retryTranslation() }
                        Button("重新找歌词") { model.refresh() }.disabled(model.track == nil || model.fetching)
                    }.font(.caption)
                    DisclosureGroup("歌词来源与同步") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(model.document?.source ?? "自动查找使用 LRCLIB 同步歌词服务")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("联网查找只发送歌名、歌手、专辑和时长，不发送屏幕或音乐音频。歌词覆盖及时间轴可能因版本而异。")
                                .font(.caption).foregroundStyle(.secondary)
                            if model.automaticTimeline {
                                HStack {
                                    Button("提前 0.5 秒") { model.offset += 0.5 }
                                    Text(String(format: "%+.1f 秒", model.offset)).monospacedDigit()
                                    Button("延后 0.5 秒") { model.offset -= 0.5 }
                                }.font(.caption).buttonStyle(.bordered)
                            }
                            HStack {
                                Button("手动找歌") {
                                    title = model.track?.title ?? ""
                                    artist = model.track?.artist ?? ""
                                    duration = model.track.map { String(Int($0.duration.rounded())) } ?? ""
                                    searching = true
                                }
                                Button("导入 LRC / TXT") { importing = true }
                            }.buttonStyle(.bordered)
                        }.padding(.top, 10)
                    }
                }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle("歌词译伴 · 不读屏版 0.3")
            .navigationBarTitleDisplayMode(.inline)
        }
        .translationTask(model.configuration) { session in await model.translate(using: session) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.resumed() } }
        .fileImporter(isPresented: $importing,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "lrc") ?? .data], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { model.importLyrics(from: url) }
            }
        .sheet(isPresented: $searching) {
            NavigationStack {
                Form {
                    TextField("歌名", text: $title)
                    TextField("歌手", text: $artist)
                    TextField("时长（秒，可留空）", text: $duration).keyboardType(.decimalPad)
                    Text("用于歌词版本匹配；只有读到 Music 播放进度时才能自动同步。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("查找歌词") {
                        model.searchManually(title: title, artist: artist, duration: Double(duration) ?? 0)
                        searching = false
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || artist.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .navigationTitle("手动找歌")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { searching = false } } }
            }.presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private var currentSentence: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.document?.instrumental == true {
                Text("纯音乐").font(.largeTitle)
            } else if let cue = model.currentCue, !cue.text.isEmpty {
                Text(cue.text).font(.system(size: 28, weight: .medium)).textSelection(.enabled)
                Text(model.currentTranslation ?? model.currentError ?? "正在翻译这整句…")
                    .font(.system(size: 25)).foregroundStyle(model.currentTranslation == nil ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
            } else {
                Text(model.document == nil ? "等待歌曲与歌词" : "前奏 / 间奏，等待下一句")
                    .font(.title2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
    }

    private func time(_ value: Double) -> String {
        let seconds = value.isFinite ? Int(min(864000, max(0, value))) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
