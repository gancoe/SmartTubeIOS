import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("Playback diagnostics reporter")
struct PlaybackDiagnosticsReporterTests {
    @Test("events encode the bounded diagnostic schema and omit nil fields")
    func encodesSchemaWithoutCredentials() async throws {
        let transport = RecordingTransport(statuses: [.success(204)])
        let storeURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let reporter = PlaybackDiagnosticsReporter(
            configuration: try #require(configuration()),
            storeURL: storeURL,
            transport: transport)

        let event = PlaybackDeliveryEvent(
            eventID: "event-1",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            reportID: "report-1",
            videoID: "video-1",
            resolution: "1920×1080",
            rate: 1.25,
            itemStatus: "ready",
            playbackStatus: "playing",
            waitingReason: "—",
            streamRoute: "primaryHLS",
            accessEventCount: 2,
            errorEventCount: 0,
            errorComment: "Media file not received in 6.5s",
            errorResource: "playlist URL · HTTPS",
            playbackPositionSeconds: 123.5
        )
        await reporter.enqueue([event])
        await reporter.flush()

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(
            request.value(forHTTPHeaderField: "Authorization")
                == "Bearer \(String(repeating: "t", count: 32))")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let expectedKeys: Set<String> = [
            "schema_version", "event_id", "timestamp", "report_id", "video_id", "resolution",
            "playback_position_seconds", "rate",
            "item_status", "playback_status", "waiting_reason", "stream_route", "dropped_frames", "stalls",
            "access_event_count", "error_event_count", "error_comment", "error_resource",
        ]
        #expect(Set(json.keys) == expectedKeys)
        #expect(json["event_id"] as? String == "event-1")
        #expect(json["timestamp"] as? String == "2023-11-14T22:13:20Z")
        let encodedBody = try #require(String(data: body, encoding: .utf8))
        #expect(!encodedBody.contains("Bearer"))
    }

    @Test("failed delivery retains events and retries the same oldest IDs")
    func retainsAndRetriesAfterFailure() async throws {
        let transport = RecordingTransport(statuses: [.failure, .success(202), .success(204)])
        let storeURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let reporter = PlaybackDiagnosticsReporter(
            configuration: try #require(configuration()),
            storeURL: storeURL,
            transport: transport)
        await reporter.enqueue([event(id: "first"), event(id: "second")])

        await reporter.flush()
        #expect(await reporter.pendingCount == 2)
        #expect(await transport.requests.count == 1)

        await reporter.flush()
        #expect(await reporter.pendingCount == 0)
        #expect(await transport.requests.count == 3)
        let requests = await transport.requests
        let sentIDs = try requests.map(eventID(from:))
        #expect(sentIDs == ["first", "first", "second"])
    }

    @Test("acknowledged events are removed from a reloaded local queue")
    func persistsAndReloadsQueue() async throws {
        let storeURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let configuration = try #require(configuration())
        let first = PlaybackDiagnosticsReporter(
            configuration: configuration,
            storeURL: storeURL,
            transport: RecordingTransport(statuses: [.success(200)]))
        await first.enqueue([event(id: "persisted")])
        let attributes = try #require(try? FileManager.default.attributesOfItem(atPath: storeURL.path))
        #expect(attributes[.size] != nil)
        let storedData = try #require(try? Data(contentsOf: storeURL))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([PlaybackDeliveryEvent].self, from: storedData)
            #expect(decoded.map(\.eventID) == ["persisted"])
            #expect(decoded.count == 1)
        } catch {
            Issue.record("decode failed: \(error)")
        }

        let transport = RecordingTransport(statuses: [.success(201)])
        let reloaded = PlaybackDiagnosticsReporter(
            configuration: configuration,
            storeURL: storeURL,
            transport: transport)
        #expect(await reloaded.pendingCount == 1)
        await reloaded.flush()
        #expect(await reloaded.pendingCount == 0)
        let acknowledgedData = try #require(try? Data(contentsOf: storeURL))
        #expect((try? decoder.decode([PlaybackDeliveryEvent].self, from: acknowledgedData))?.isEmpty == true)

        let afterAck = PlaybackDiagnosticsReporter(
            configuration: configuration,
            storeURL: storeURL,
            transport: RecordingTransport(statuses: []))
        #expect(await afterAck.pendingCount == 0)
    }

    @Test("enqueue drops the oldest events at the configured queue bound")
    func boundsQueue() async throws {
        let storeURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let transport = RecordingTransport(statuses: [.success(204), .success(204), .success(204)])
        let reporter = PlaybackDiagnosticsReporter(
            configuration: try #require(configuration()),
            storeURL: storeURL,
            limits: PlaybackDiagnosticsLimits(maxPendingEvents: 3, maxStoreBytes: 1_048_576),
            transport: transport)
        await reporter.enqueue((1...5).map { event(id: "event-\($0)") })
        #expect(await reporter.pendingCount == 3)
        await reporter.flush()
        let requests = await transport.requests
        let sentIDs = try requests.map(eventID(from:))
        #expect(sentIDs == ["event-3", "event-4", "event-5"])
    }

    @Test("configuration rejects unsafe HTTP endpoints and malformed tokens")
    func validatesConfiguration() {
        let token = String(repeating: "t", count: 32)
        #expect(
            PlaybackDiagnosticsConfiguration(
                endpoint: URL(string: "http://8.8.8.8/v1/events")!, token: token) == nil)
        #expect(
            PlaybackDiagnosticsConfiguration(
                endpoint: URL(string: "http://127.0.0.1/v1/events?x=1")!, token: token) == nil)
        #expect(
            PlaybackDiagnosticsConfiguration(
                endpoint: URL(string: "http://127.0.0.1/events")!, token: token) == nil)
        #expect(
            PlaybackDiagnosticsConfiguration(
                endpoint: URL(string: "http://127.0.0.1/v1/events")!, token: "short") == nil)
        #expect(
            PlaybackDiagnosticsConfiguration(
                endpoint: URL(string: "http://127.0.0.1/v1/events")!,
                token: "\(String(repeating: "t", count: 16)) \(String(repeating: "t", count: 16))") == nil)
        #expect(
            PlaybackDiagnosticsConfiguration(
                endpoint: URL(string: "http://10.1.2.3/v1/events")!, token: token) != nil)
        #expect(
            PlaybackDiagnosticsConfiguration(
                endpoint: URL(string: "http://collector.local/v1/events")!, token: token) != nil)
        #expect(
            PlaybackDiagnosticsConfiguration(
                endpoint: URL(string: "https://collector.example/v1/events")!, token: token) != nil)
    }

    private func configuration() -> PlaybackDiagnosticsConfiguration? {
        PlaybackDiagnosticsConfiguration(
            endpoint: URL(string: "http://127.0.0.1/v1/events")!,
            token: String(repeating: "t", count: 32))
    }

    private func event(id: String) -> PlaybackDeliveryEvent {
        PlaybackDeliveryEvent(eventID: id, reportID: "report", videoID: "video", resolution: "720p")
    }

    private func eventID(from request: URLRequest) throws -> String {
        guard let body = request.httpBody,
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
            let eventID = json["event_id"] as? String
        else { throw TestError.invalidRequest }
        return eventID
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("smarttube-playback-diagnostics-\(UUID().uuidString).json")
    }

    private enum TestError: Error {
        case invalidRequest
    }
}

private actor RecordingTransport: PlaybackDiagnosticsTransport {
    enum Result: Sendable {
        case success(Int)
        case failure
    }

    private var statuses: [Result]
    private(set) var requests: [URLRequest] = []

    init(statuses: [Result]) {
        self.statuses = statuses
    }

    func send(_ request: URLRequest) throws -> PlaybackDiagnosticsTransportResponse {
        requests.append(request)
        guard !statuses.isEmpty else { return PlaybackDiagnosticsTransportResponse(statusCode: 204) }
        switch statuses.removeFirst() {
        case .success(let status):
            return PlaybackDiagnosticsTransportResponse(statusCode: status)
        case .failure:
            throw RecordingError.unavailable
        }
    }

    enum RecordingError: Error {
        case unavailable
    }
}
