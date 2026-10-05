import Foundation

struct MPVPlaybackDiagnosticSnapshot: Sendable, Equatable {
    let timestamp: Date
    let reportID: String
    let videoID: String
    let currentTime: Double?
    let rate: Double?
    let bufferSeconds: Double?
    let isPlaying: Bool
    let isBuffering: Bool
    let isReady: Bool
    let isSeeking: Bool
    let hasEnded: Bool
    let videoWidth: Int?
    let videoHeight: Int?
    let downloadMbps: Double?
    let droppedFrames: Int
    let stalls: Int
    let errorEventCount: Int
    let errorCode: Int?
    let errorTimestamp: Date?
    let captureID: UUID?
    let captureState: String?

    init(
        timestamp: Date = Date(),
        reportID: String,
        videoID: String,
        currentTime: Double? = nil,
        rate: Double? = nil,
        bufferSeconds: Double? = nil,
        isPlaying: Bool = false,
        isBuffering: Bool = false,
        isReady: Bool = false,
        isSeeking: Bool = false,
        hasEnded: Bool = false,
        videoWidth: Int? = nil,
        videoHeight: Int? = nil,
        downloadMbps: Double? = nil,
        droppedFrames: Int = 0,
        stalls: Int = 0,
        errorEventCount: Int = 0,
        errorCode: Int? = nil,
        errorTimestamp: Date? = nil,
        captureID: UUID? = nil,
        captureState: String? = nil
    ) {
        self.timestamp = timestamp
        self.reportID = reportID
        self.videoID = videoID
        self.currentTime = currentTime
        self.rate = rate
        self.bufferSeconds = bufferSeconds
        self.isPlaying = isPlaying
        self.isBuffering = isBuffering
        self.isReady = isReady
        self.isSeeking = isSeeking
        self.hasEnded = hasEnded
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.downloadMbps = downloadMbps
        self.droppedFrames = droppedFrames
        self.stalls = stalls
        self.errorEventCount = errorEventCount
        self.errorCode = errorCode
        self.errorTimestamp = errorTimestamp
        self.captureID = captureID
        self.captureState = captureState
    }

    func deliveryEvent() -> PlaybackDeliveryEvent {
        MPVPlaybackDiagnosticMapper.deliveryEvent(from: self)
    }
}

enum MPVPlaybackDiagnosticMapper {
    static func deliveryEvent(from snapshot: MPVPlaybackDiagnosticSnapshot) -> PlaybackDeliveryEvent {
        let validReportID = safeIdentifier(snapshot.reportID)
        let validVideoID = safeIdentifier(snapshot.videoID)
        let resolution: String
        if let width = snapshot.videoWidth, let height = snapshot.videoHeight,
            (1...20_000).contains(width), (1...20_000).contains(height)
        {
            resolution = "\(width)x\(height)"
        } else {
            resolution = "unknown"
        }
        let rate = finite(snapshot.rate, minimum: 0, maximum: 4)
        let buffer = finite(snapshot.bufferSeconds, minimum: 0)
        let viewingBuffer = buffer.flatMap { value in
            guard let rate, rate > 0 else { return value }
            return value / rate
        }
        let observedBitrate = finite(snapshot.downloadMbps, minimum: 0).flatMap { value in
            let bitrate = value * 1_000_000
            return bitrate.isFinite && bitrate > 0 ? bitrate : nil
        }
        let itemStatus = snapshot.isReady ? "ready" : snapshot.errorEventCount > 0 ? "failed" : "unknown"
        let playbackStatus: String
        if snapshot.isBuffering || snapshot.isSeeking {
            playbackStatus = "waiting"
        } else if snapshot.isPlaying && !snapshot.hasEnded {
            playbackStatus = "playing"
        } else {
            playbackStatus = "paused"
        }
        let errorCode = snapshot.errorCode.flatMap { Int32(exactly: $0).map(Int.init) }
        return PlaybackDeliveryEvent(
            timestamp: snapshot.timestamp,
            reportID: validReportID,
            videoID: validVideoID,
            resolution: resolution,
            rate: rate,
            bufferMediaSeconds: buffer,
            bufferViewingSeconds: viewingBuffer,
            itemStatus: itemStatus,
            playbackStatus: playbackStatus,
            waitingReason: snapshot.isBuffering || snapshot.isSeeking ? "unknown" : "—",
            streamRoute: "MPV/FFmpeg/HLS",
            observedBitrateBps: observedBitrate,
            droppedFrames: max(0, snapshot.droppedFrames),
            stalls: max(0, snapshot.stalls),
            errorEventCount: max(0, snapshot.errorEventCount),
            errorDomain: errorCode == nil ? nil : "MPV",
            errorCode: errorCode,
            errorTimestamp: snapshot.errorEventCount > 0 ? snapshot.errorTimestamp : nil,
            errorComment: errorCode == nil ? "—" : "Details redacted",
            errorResource: "unknown",
            playbackPositionSeconds: finite(snapshot.currentTime, minimum: 0),
            captureID: snapshot.captureID,
            captureState: snapshot.captureState)
    }

    private static func safeIdentifier(_ value: String) -> String {
        let pattern = #"^[A-Za-z0-9_-]{1,64}$"#
        return value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
            ? value : "unknown"
    }

    private static func finite(_ value: Double?, minimum: Double, maximum: Double? = nil) -> Double? {
        guard let value, value.isFinite, value >= minimum,
            maximum.map({ value <= $0 }) ?? true
        else { return nil }
        return value
    }
}
