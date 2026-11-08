import Foundation

enum Wire {
    static let port: UInt16 = 54137
    static let maximumPacket = 65_536

    static func encode<T: Encodable>(_ value: T) -> Data? {
        guard var data = try? JSONEncoder().encode(value) else { return nil }
        data.append(0x0A)
        return data
    }
}

struct CaptureOptions: Codable {
    var side: String = "left"
    var fraction: Double = 0.62
    var stop: Bool = false
}

struct RecognitionPacket: Codable {
    var lines: [String]
    var status: String
    var error: String?
}
