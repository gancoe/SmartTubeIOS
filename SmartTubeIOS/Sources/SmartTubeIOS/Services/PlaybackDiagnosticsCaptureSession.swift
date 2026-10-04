import Foundation

@MainActor
final class PlaybackDiagnosticsCaptureSession {
    enum State: String, Codable {
        case active
        case recovery
        case ended
    }

    private static let maximumDuration: TimeInterval = 30 * 60
    private static let recoveryDuration: TimeInterval = 60

    let captureID: UUID
    private let stateURL: URL
    private(set) var startedAt: Date
    private(set) var endsAt: Date
    private(set) var state: State

    init(captureID: UUID, stateURL: URL, now: Date = Date()) {
        self.captureID = captureID
        self.stateURL = stateURL
        startedAt = now
        endsAt = now
        state = .ended
        if let values = Self.read(from: stateURL) {
            if let stored = values[captureID.uuidString.lowercased()] {
                guard stored.start <= now, stored.end >= stored.start,
                    stored.end.timeIntervalSince(stored.start) <= Self.maximumDuration
                else { return }
                startedAt = stored.start
                endsAt = stored.end
                state = stored.state
            } else {
                endsAt = now.addingTimeInterval(Self.maximumDuration)
                state = .active
                if !persist() {
                    endsAt = now
                    state = .ended
                }
            }
        }
        refresh(at: now)
    }

    var isCapturing: Bool { state != .ended }

    func refresh(at now: Date = Date()) {
        guard state != .ended else { return }
        if now >= endsAt {
            state = .ended
            _ = persist()
        }
    }

    func note(errorCode: Int?, at now: Date = Date()) {
        guard state == .active, now >= startedAt,
            errorCode == -16_830 || errorCode == -12_889
        else { return }
        endsAt = min(endsAt, now.addingTimeInterval(Self.recoveryDuration))
        state = .recovery
        if !persist() { state = .ended }
    }

    private struct Stored: Codable {
        let start: Date
        let end: Date
        let state: State

        enum CodingKeys: String, CodingKey { case start, end, state }
        init(start: Date, end: Date, state: State) {
            self.start = start
            self.end = end
            self.state = state
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            start = try container.decode(Date.self, forKey: .start)
            end = try container.decode(Date.self, forKey: .end)
            state = State(rawValue: try container.decode(String.self, forKey: .state)) ?? .ended
        }
    }

    private static func read(from url: URL) -> [String: Stored]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url),
            let result = try? JSONDecoder().decode([String: Stored].self, from: data)
        else { return nil }
        return result
    }

    @discardableResult
    private func persist() -> Bool {
        guard var values = Self.read(from: stateURL) else { return false }
        values[captureID.uuidString.lowercased()] = Stored(start: startedAt, end: endsAt, state: state)
        guard let data = try? JSONEncoder().encode(values) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: stateURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
