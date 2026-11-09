import Foundation
import MediaPlayer

struct MusicSnapshot {
    let track: MusicTrack?
    let position: Double?
    let isPlaying: Bool
}

@MainActor
final class MusicMonitor {
    var onSnapshot: ((MusicSnapshot) -> Void)?
    private var player: MPMusicPlayerController?
    private var loop: Task<Void, Never>?
    private var lastPosition: Double?
    private var lastTrackKey: String?
    private var progressedAt = Date()
    private var generatingNotifications = false
    private var libraryLyricsKey: String?
    private var libraryLyrics: String?

    func start() async -> Bool {
        var authorization = MPMediaLibrary.authorizationStatus()
        if authorization == .notDetermined {
            authorization = await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard authorization == .authorized else { return false }
        if player == nil { player = MPMusicPlayerController.systemMusicPlayer }
        if !generatingNotifications {
            player?.beginGeneratingPlaybackNotifications()
            generatingNotifications = true
        }
        loop?.cancel()
        sample()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.sample()
            }
        }
        return true
    }

    func stop() {
        loop?.cancel()
        loop = nil
        if generatingNotifications {
            player?.endGeneratingPlaybackNotifications()
            generatingNotifications = false
        }
        // Stop observing only. Never stop, pause, seek, replace the queue, or change Music's volume.
    }

    func refresh() { sample() }

    private func sample() {
        guard let player else { return }
        let track: MusicTrack?
        if let item = player.nowPlayingItem, let title = item.title, !title.isEmpty {
            var current = MusicTrack(title: title, artist: item.artist ?? "", album: item.albumTitle ?? "",
                duration: item.playbackDuration.isFinite ? max(0, item.playbackDuration) : 0,
                storeID: item.value(forProperty: MPMediaItemPropertyPlaybackStoreID) as? String ?? "")
            if libraryLyricsKey != current.key {
                libraryLyricsKey = current.key
                libraryLyrics = item.lyrics
            }
            current.libraryLyrics = libraryLyrics
            track = current
        } else { track = nil }
        let time = player.currentPlaybackTime
        let playing = player.playbackState == .playing
        let validTime = time.isFinite && time >= 0
        if track?.key != lastTrackKey || !playing || (validTime && abs(time - (lastPosition ?? -1)) > 0.01) {
            progressedAt = Date()
        }
        lastPosition = validTime ? time : nil
        lastTrackKey = track?.key
        let stale = playing && Date().timeIntervalSince(progressedAt) > 6
        onSnapshot?(MusicSnapshot(track: track, position: validTime && !stale ? time : nil, isPlaying: playing))
    }
}
