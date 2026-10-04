import Foundation
import SmartTubeIOSCore
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let playbackDiagnosticsLog = Logger(
    subsystem: appSubsystem,
    category: "PlaybackDiagnosticsReporter"
)

public struct PlaybackDiagnosticsConfiguration: Codable, Equatable, Sendable {
    public let endpoint: URL
    public let token: String

    public init?(endpoint: URL, token: String) {
        guard Self.isValidEndpoint(endpoint), Self.isValidToken(token) else { return nil }
        self.endpoint = endpoint
        self.token = token
    }

    public init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "PlaybackDiagnostics", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(FileConfiguration.self, from: data)
        else { return nil }
        self.init(endpointString: file.endpoint, token: file.token)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let endpoint = try container.decode(String.self, forKey: .endpoint)
        let token = try container.decode(String.self, forKey: .token)
        guard let configuration = Self(endpointString: endpoint, token: token) else {
            throw ConfigurationError.invalid
        }
        self = configuration
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpoint.absoluteString, forKey: .endpoint)
        try container.encode(token, forKey: .token)
    }

    private init?(endpointString: String, token: String) {
        guard let endpoint = URL(string: endpointString) else { return nil }
        self.init(endpoint: endpoint, token: token)
    }

    private static func isValidToken(_ token: String) -> Bool {
        token.count >= 32 && !token.contains(where: \.isWhitespace)
    }

    private static func isValidEndpoint(_ endpoint: URL) -> Bool {
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            let host = components.host?.lowercased(), !host.isEmpty,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            components.path == "/v1/events"
        else { return false }

        guard scheme == "http" || scheme == "https" else { return false }
        guard scheme == "https" else {
            return host.hasSuffix(".local") || Self.isPrivateIPv4(host)
        }
        return true
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
            octets.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else { return false }
        let values = octets.compactMap { Int($0) }
        guard values.count == 4, values.allSatisfy({ (0...255).contains($0) }) else { return false }

        switch values[0] {
        case 10, 127:
            return true
        case 172:
            return (16...31).contains(values[1])
        case 192:
            return values[1] == 168
        default:
            return false
        }
    }

    private struct FileConfiguration: Decodable {
        let endpoint: String
        let token: String
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case token
    }

    private enum ConfigurationError: Error {
        case invalid
    }
}

public struct PlaybackDiagnosticsLimits: Sendable, Equatable {
    public let maxPendingEvents: Int
    public let maxStoreBytes: Int

    public init(maxPendingEvents: Int = 1_000, maxStoreBytes: Int = 1_048_576) {
        self.maxPendingEvents = max(0, maxPendingEvents)
        self.maxStoreBytes = max(0, maxStoreBytes)
    }
}

public struct PlaybackDeliveryEvent: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let eventID: String
    public let timestamp: Date
    public let reportID: String
    public let videoID: String
    public let resolution: String
    public let playbackPositionSeconds: Double?
    public let rate: Double?
    public let bufferMediaSeconds: Double?
    public let bufferViewingSeconds: Double?
    public let itemStatus: String
    public let playbackStatus: String
    public let waitingReason: String
    public let streamRoute: String
    public let advertisedBitrateBps: Double?
    public let observedBitrateBps: Double?
    public let peakBitrateBps: Double?
    public let downloadedBytes: Int64?
    public let droppedFrames: Int
    public let stalls: Int
    public let accessEventCount: Int
    public let errorEventCount: Int
    public let errorDomain: String?
    public let errorCode: Int?
    public let errorTimestamp: Date?
    public let errorComment: String
    public let errorResource: String

    public init(
        schemaVersion: Int = 1,
        eventID: String = UUID().uuidString,
        timestamp: Date = Date(),
        reportID: String = "",
        videoID: String = "",
        resolution: String = "",
        rate: Double? = nil,
        bufferMediaSeconds: Double? = nil,
        bufferViewingSeconds: Double? = nil,
        itemStatus: String = "",
        playbackStatus: String = "",
        waitingReason: String = "",
        streamRoute: String = "",
        advertisedBitrateBps: Double? = nil,
        observedBitrateBps: Double? = nil,
        downloadedBytes: Int64? = nil,
        droppedFrames: Int = 0,
        stalls: Int = 0,
        peakBitrateBps: Double? = nil,
        accessEventCount: Int = 0,
        errorEventCount: Int = 0,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        errorTimestamp: Date? = nil,
        errorComment: String = "",
        errorResource: String = "",
        playbackPositionSeconds: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.timestamp = timestamp
        self.reportID = reportID
        self.videoID = videoID
        self.resolution = resolution
        self.playbackPositionSeconds = playbackPositionSeconds
        self.rate = rate
        self.bufferMediaSeconds = bufferMediaSeconds
        self.bufferViewingSeconds = bufferViewingSeconds
        self.itemStatus = itemStatus
        self.playbackStatus = playbackStatus
        self.waitingReason = waitingReason
        self.streamRoute = streamRoute
        self.advertisedBitrateBps = advertisedBitrateBps
        self.observedBitrateBps = observedBitrateBps
        self.peakBitrateBps = peakBitrateBps
        self.downloadedBytes = downloadedBytes
        self.droppedFrames = droppedFrames
        self.stalls = stalls
        self.accessEventCount = accessEventCount
        self.errorEventCount = errorEventCount
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.errorTimestamp = errorTimestamp
        self.errorComment = errorComment
        self.errorResource = errorResource
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventID = "event_id"
        case timestamp
        case reportID = "report_id"
        case videoID = "video_id"
        case resolution
        case playbackPositionSeconds = "playback_position_seconds"
        case rate
        case bufferMediaSeconds = "buffer_media_seconds"
        case bufferViewingSeconds = "buffer_viewing_seconds"
        case itemStatus = "item_status"
        case playbackStatus = "playback_status"
        case waitingReason = "waiting_reason"
        case streamRoute = "stream_route"
        case advertisedBitrateBps = "advertised_bitrate_bps"
        case observedBitrateBps = "observed_bitrate_bps"
        case peakBitrateBps = "peak_bitrate_bps"
        case downloadedBytes = "downloaded_bytes"
        case droppedFrames = "dropped_frames"
        case stalls
        case accessEventCount = "access_event_count"
        case errorEventCount = "error_event_count"
        case errorDomain = "error_domain"
        case errorCode = "error_code"
        case errorTimestamp = "error_timestamp"
        case errorComment = "error_comment"
        case errorResource = "error_resource"
    }

}

public struct PlaybackDiagnosticsTransportResponse: Sendable, Equatable {
    public let statusCode: Int

    public init(statusCode: Int) {
        self.statusCode = statusCode
    }
}

public protocol PlaybackDiagnosticsTransport: Sendable {
    func send(_ request: URLRequest) async throws -> PlaybackDiagnosticsTransportResponse
}

public struct PlaybackDiagnosticsURLSessionTransport: PlaybackDiagnosticsTransport, @unchecked Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> PlaybackDiagnosticsTransportResponse {
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TransportError.invalidResponse
        }
        return PlaybackDiagnosticsTransportResponse(statusCode: response.statusCode)
    }

    private enum TransportError: Error {
        case invalidResponse
    }
}

public actor PlaybackDiagnosticsReporter {
    public let configuration: PlaybackDiagnosticsConfiguration
    public let limits: PlaybackDiagnosticsLimits

    private let storeURL: URL
    private let transport: any PlaybackDiagnosticsTransport
    private var pending: [PlaybackDeliveryEvent]
    private let encoder: JSONEncoder
    private var isFlushing = false

    public var pendingCount: Int { pending.count }

    public init(
        configuration: PlaybackDiagnosticsConfiguration,
        storeURL: URL,
        limits: PlaybackDiagnosticsLimits = PlaybackDiagnosticsLimits(),
        transport: any PlaybackDiagnosticsTransport = PlaybackDiagnosticsURLSessionTransport()
    ) {
        self.configuration = configuration
        self.limits = limits
        self.storeURL = storeURL
        self.transport = transport
        self.encoder = Self.makeEncoder()
        self.pending = Self.loadPending(from: storeURL, limits: limits)
    }

    public func enqueue(_ events: [PlaybackDeliveryEvent]) {
        guard !events.isEmpty, limits.maxPendingEvents > 0, limits.maxStoreBytes > 0 else { return }

        var identifiers = Set(pending.map(\.eventID))
        for event in events where !identifiers.contains(event.eventID) {
            pending.append(event)
            identifiers.insert(event.eventID)
        }
        trimPending()
        persist()
    }

    public func flush() async {
        guard !isFlushing, !pending.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        for _ in 0..<5 {
            guard let event = pending.first else { return }
            let request: URLRequest
            do {
                request = try makeRequest(for: event)
            } catch {
                playbackDiagnosticsLog.error("queue request preparation failed")
                return
            }

            do {
                let response = try await transport.send(request)
                guard [200, 201, 202, 204].contains(response.statusCode) else {
                    playbackDiagnosticsLog.error("queue delivery stopped at HTTP status")
                    return
                }
                guard let index = pending.firstIndex(where: { $0.eventID == event.eventID }) else {
                    continue
                }
                pending.remove(at: index)
                persist()
            } catch {
                playbackDiagnosticsLog.error("queue delivery failed")
                return
            }
        }
    }

    private func makeRequest(for event: PlaybackDeliveryEvent) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(event)
        return request
    }

    private func trimPending() {
        while pending.count > limits.maxPendingEvents {
            pending.removeFirst()
        }
        while !pending.isEmpty {
            guard let data = try? encoder.encode(pending) else {
                pending.removeFirst()
                continue
            }
            if data.count <= limits.maxStoreBytes { return }
            pending.removeFirst()
        }
    }

    private func persist() {
        trimPending()
        guard let data = try? encoder.encode(pending) else {
            playbackDiagnosticsLog.error("queue encoding failed")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            playbackDiagnosticsLog.error("queue persistence failed")
        }
    }

    private static func loadPending(from url: URL, limits: PlaybackDiagnosticsLimits) -> [PlaybackDeliveryEvent] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let fileSize = attributes[.size] as? NSNumber,
            fileSize.intValue >= 0, fileSize.intValue <= limits.maxStoreBytes,
            let data = try? Data(contentsOf: url),
            let events = try? Self.makeDecoder().decode([PlaybackDeliveryEvent].self, from: data)
        else { return [] }

        var seen = Set<String>()
        var unique = events.filter { seen.insert($0.eventID).inserted }
        while unique.count > limits.maxPendingEvents { unique.removeFirst() }
        while !unique.isEmpty {
            guard let encoded = try? Self.makeEncoder().encode(unique), encoded.count > limits.maxStoreBytes
            else { break }
            unique.removeFirst()
        }
        return unique
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
