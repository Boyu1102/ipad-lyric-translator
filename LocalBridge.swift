import Foundation
import Network

/// Only accepts connections on this device's IPv4 loopback interface.
/// Screen pixels never leave the capture extension; only OCR strings travel here.
final class LocalBridge {
    private let queue = DispatchQueue(label: "app.lyricbridge.loopback")
    private var listener: NWListener?
    private var peers: [UUID: NWConnection] = [:]
    private var options = CaptureOptions()
    var onPacket: ((RecognitionPacket) -> Void)?
    var onError: ((String) -> Void)?

    func start() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(
                    host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Wire.port)!)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    if case .failed(let error) = state {
                        self?.onError?("识别连接未能建立：\(error.localizedDescription)")
                        self?.listener?.cancel()
                        self?.listener = nil
                    }
                }
                listener.newConnectionHandler = { [weak self] peer in
                    self?.accept(peer)
                }
                listener.start(queue: self.queue)
            } catch {
                self.onError?("识别连接未能建立：\(error.localizedDescription)")
            }
        }
    }

    func configure(_ options: CaptureOptions) {
        queue.async { [weak self] in
            guard let self else { return }
            self.options = options
            for peer in self.peers.values { self.sendOptions(to: peer) }
        }
    }

    private func sendOptions(to peer: NWConnection) {
        guard let data = Wire.encode(options) else { return }
        peer.send(content: data, completion: .contentProcessed { _ in })
    }

    private func accept(_ peer: NWConnection) {
        // A small upper bound prevents a stray local client from accumulating connections.
        guard peers.count < 4 else { peer.cancel(); return }
        let id = UUID()
        peers[id] = peer
        peer.stateUpdateHandler = { [weak self, weak peer] state in
            guard let self, let peer else { return }
            switch state {
            case .ready:
                self.sendOptions(to: peer)
                self.receive(peer, id: id, buffered: Data())
            case .failed, .cancelled:
                self.peers.removeValue(forKey: id)
            default: break
            }
        }
        peer.start(queue: queue)
    }

    private func receive(_ peer: NWConnection, id: UUID, buffered: Data) {
        peer.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            [weak self, weak peer] data, _, complete, error in
            guard let self, let peer else { return }
            var buffer = buffered
            if let data { buffer.append(data) }
            guard buffer.count <= Wire.maximumPacket else { peer.cancel(); return }
            while let newline = buffer.firstIndex(of: 0x0A) {
                let message = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if let packet = try? JSONDecoder().decode(RecognitionPacket.self, from: message) {
                    self.onPacket?(packet)
                }
            }
            if complete || error != nil {
                peer.cancel()
                self.peers.removeValue(forKey: id)
            } else {
                self.receive(peer, id: id, buffered: buffer)
            }
        }
    }
}
