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
                VStack(alignment: .leading, spacing: 24) {
                    connectionControls
                    trackDetails
                    HStack(spacing: 16) {
                        Text("译文").font(.subheadline).foregroundStyle(.secondary)
                        Picker("译文语言", selection: $model.target) {
                            ForEach(TranslationTarget.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).frame(maxWidth: 260)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        if model.fetching { ProgressView().controlSize(.small) }
                        Text(model.status).font(.caption).foregroundStyle(.secondary)
                    }
                    currentSentence
                    upcomingSentences
                    manualControls
                    candidates
                    Divider()
                    Text(model.translationStatus).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("歌词与设置") { settings.padding(.top, 14) }
                }
                .padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle("歌词译伴")
            .navigationBarTitleDisplayMode(.inline)
        }
        .translationTask(model.configuration) { session in await model.translate(using: session) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.resumed() } }
        .fileImporter(isPresented: $importing,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "lrc") ?? .data], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { model.importLyrics(from: url) }
            }
        .sheet(isPresented: $searching) { searchSheet }
    }

    private var connectionControls: some View {
        HStack {
            if model.connected {
                Label("已连接 Apple Music", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("停止跟随") { model.stopFollowing() }.font(.subheadline)
            } else {
                Button(model.connecting ? "正在连接…" : "连接 Apple Music", systemImage: "music.note") {
                    Task { await model.connect() }
                }.buttonStyle(.borderedProminent).disabled(model.connecting)
            }
        }
    }

    @ViewBuilder private var trackDetails: some View {
        if let track = model.track {
            VStack(alignment: .leading, spacing: 8) {
                Text(track.title).font(.title2.weight(.semibold))
                Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: model.isPlaying ? "waveform" : "pause.fill")
                    Text(model.isPlaying ? "播放中" : "已暂停")
                    if model.positionAvailable {
                        Text("\(time(model.position)) / \(time(track.duration))").monospacedDigit()
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var currentSentence: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.document?.instrumental == true {
                Text("纯音乐").font(.title2)
            } else if let cue = model.currentCue, !cue.text.isEmpty {
                Text(cue.text).font(.system(size: 25, weight: .medium)).textSelection(.enabled)
                if model.sourceLanguage.rawValue != model.target.rawValue {
                    Divider().opacity(0.5)
                    Text(model.currentTranslation ?? model.currentError ?? "正在翻译这整句…")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(model.currentTranslation == nil ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                }
            } else {
                Text(model.document == nil ? "等待歌词" : "前奏 / 间奏")
                    .font(.title2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
        .animation(.easeInOut(duration: 0.15), value: model.currentIndex)
    }

    @ViewBuilder private var upcomingSentences: some View {
        if !model.upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("接下来").font(.caption)
                ForEach(model.upcoming) { Text($0.text).font(.body) }
            }.foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    @ViewBuilder private var manualControls: some View {
        if let document = model.document, !document.cues.isEmpty, !model.automaticTimeline {
            VStack(alignment: .leading, spacing: 10) {
                Text(document.isTimed ? "暂时读不到播放时间，可手动切句" : "这个版本没有时间轴，可手动切句")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("上一句", systemImage: "chevron.left") { model.moveManually(-1) }
                    Button("下一句", systemImage: "chevron.right") { model.moveManually(1) }
                }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private var candidates: some View {
        if !model.alternatives.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("选择歌词版本").font(.headline)
                ForEach(model.alternatives) { record in
                    Button { model.choose(record) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(record.trackName) · \(record.artistName)")
                            Text("\(record.albumName) · \(time(record.duration)) · \(record.hasSyncedLyrics ? "同步" : "无时间轴") · \(record.language.label)")
                                .font(.caption).foregroundStyle(.secondary)
                            if record.language == .romanized || record.language == .unknown {
                                Text("缺少可靠原词，建议换版本或导入歌词").font(.caption).foregroundStyle(.orange)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.bordered)
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button("重试翻译") { model.retryTranslation() }
                Button("重新找歌词") { model.refresh() }
            }.font(.subheadline)
            Picker("原文语言", selection: $model.sourceOverride) {
                Text("自动识别").tag("auto")
                Text("日语").tag("ja")
                Text("英语").tag("en")
            }.pickerStyle(.menu)
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
            Text(model.document?.source ?? "自动查找同步歌词，优先日文原词")
                .font(.caption).foregroundStyle(.secondary)
            Text("Apple Music 显示的歌词不一定对其他 App 开放。找不到时，可导入自己的歌词；TXT 可手动切句，LRC 可同步播放。")
                .font(.caption).foregroundStyle(.secondary)
            Text("不读屏、不录音。联网匹配只发送当前歌名、歌手、专辑、时长及歌曲编号。翻译由设备完成。")
                .font(.caption2).foregroundStyle(.secondary)
            Text("版本 0.4.0").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var searchSheet: some View {
        NavigationStack {
            Form {
                TextField("歌名", text: $title)
                TextField("歌手", text: $artist)
                TextField("时长（秒，可留空）", text: $duration).keyboardType(.decimalPad)
                Text("支持英文、日文歌名；时长用于区分不同歌曲版本。")
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

    private func time(_ value: Double) -> String {
        let seconds = value.isFinite ? Int(min(864000, max(0, value))) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
