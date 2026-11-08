import Foundation
import Network

/// State is confined to queue; no App Group entitlement is needed for personal signing.
final class CaptureLink {
    private let queue = DispatchQueue(label: "app.lyricbridge.capture-link")
    private var connection: NWConnection?
    private var ready = false
    private var stopped = false
    private var options = CaptureOptions()
    private var onStop: (() -> Void)?

    func start(onStop: @escaping () -> Void) {
        queue.async {
            self.stopped = false
            self.onStop = onStop
            self.connect()
        }
    }

    func snapshot() -> CaptureOptions? {
        queue.sync { ready ? options : nil }
    }

    func send(_ packet: RecognitionPacket) {
        queue.async {
            guard self.ready, let data = Wire.encode(packet) else { return }
            self.connection?.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.ready = false
            self.connection?.cancel()
            self.connection = nil
        }
    }

    private func connect() {
        guard !stopped else { return }
        let peer = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Wire.port)!, using: .tcp)
        connection = peer
        peer.stateUpdateHandler = { [weak self, weak peer] state in
            guard let self, let peer, self.connection === peer else { return }
            switch state {
            case .ready: self.receive(peer, buffered: Data())
            case .failed, .cancelled: self.reconnect(peer)
            default: break
            }
        }
        peer.start(queue: queue)
    }

    private func reconnect(_ peer: NWConnection) {
        guard connection === peer else { return }
        connection = nil
        ready = false
        peer.cancel()
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.connect() }
    }

    private func receive(_ peer: NWConnection, buffered: Data) {
        peer.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self, weak peer] data, _, complete, error in
            guard let self, let peer, self.connection === peer else { return }
            var buffer = buffered
            if let data { buffer.append(data) }
            guard buffer.count <= 8192 else { self.reconnect(peer); return }
            while let newline = buffer.firstIndex(of: 0x0A) {
                let message = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if let options = try? JSONDecoder().decode(CaptureOptions.self, from: message) {
                    self.options = options
                    self.ready = true
                    if options.stop { self.onStop?() }
                }
            }
            if complete || error != nil { self.reconnect(peer) }
            else { self.receive(peer, buffered: buffer) }
        }
    }
}
