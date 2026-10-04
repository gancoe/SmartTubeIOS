import AVFoundation
import SmartTubeIOSCore
import os

private let playerLog = CrashlyticsLogger(category: "Player")
private let deliveryLog = Logger(subsystem: appSubsystem, category: "PlaybackDeliveryDiagnostics")

// MARK: - Stats for Nerds

extension PlaybackViewModel {

    static let statsForNerdsRefreshInterval: Duration = .seconds(1)

    public func toggleStatsForNerds() {
        statsForNerdsVisible.toggle()
        if statsForNerdsVisible { updateStatsSnapshot() }
    }

    func updateStatsSnapshot() {
        guard let item = player.currentItem else {
            statsSnapshot = .empty
            return
        }
        let accessLog = item.accessLog()
        let logEvent = accessLog?.events.last
        let videoId = playerInfo?.video.id ?? currentVideo?.id ?? ""

        // Resolution — always derived from AVPlayer's presentationSize (the actual decoded
        // video dimensions). This is the ground truth: if a quality switch is in flight the
        // old resolution is shown until the new composition becomes readyToPlay, which is
        // honest. Showing selectedFormat metadata here caused stats to report 256×144 while
        // the player was actually decoding 640×360 (the VP9 WebM quality-switch failure).
        let presentationSize = item.presentationSize
        let res: String
        if presentationSize.width > 0 && presentationSize.height > 0 {
            res = "\(Int(presentationSize.width))×\(Int(presentationSize.height))"
        } else {
            res = "—"
        }

        let fps = selectedFormat?.fps ?? 0

        // Codec: retain the stream metadata label. It does not identify the format actually
        // decoded by AVPlayer.
        let codec: String
        if let fmt = selectedFormat {
            codec = Self.extractCodec(from: fmt.mimeType)
        } else if playerInfo?.hlsURL != nil {
            codec = "HLS"
        } else if playerInfo?.dashURL != nil {
            codec = "DASH"
        } else if let fmt = playerInfo?.formats.first {
            codec = Self.extractCodec(from: fmt.mimeType)
        } else {
            codec = "—"
        }

        let nominalBitrate: String
        if let br = selectedFormat?.bitrate, br > 0 {
            nominalBitrate = Self.formatBitrate(br)
        } else if playerInfo?.hlsURL != nil || playerInfo?.dashURL != nil {
            nominalBitrate = "Adaptive"
        } else if let br = playerInfo?.formats.first?.bitrate, br > 0 {
            nominalBitrate = Self.formatBitrate(br)
        } else {
            nominalBitrate = "—"
        }

        let observedBitrate: String
        if let br = logEvent?.observedBitrate, br > 0 {
            observedBitrate = Self.formatBitrate(Int(br))
        } else {
            observedBitrate = "—"
        }

        let droppedFrames = logEvent.map { $0.numberOfDroppedVideoFrames } ?? 0
        let stalls = logEvent.map { $0.numberOfStalls } ?? 0

        let resSource = "presentationSize"
        // Only forward to Crashlytics breadcrumbs when something meaningful changed.
        // Silent 0.5 s ticks otherwise saturate the 64 KB breadcrumb buffer and push
        // critical events (load, quality switch, errors) out of the window.
        let prevSnap = statsSnapshot
        let codecChanged = codec != prevSnap.codec && prevSnap.codec != "—"
        let resChanged = res != prevSnap.displayResolution && prevSnap.displayResolution != "—"
        let isFirstSnap = prevSnap.videoId != videoId
        if isFirstSnap || codecChanged || resChanged {
            playerLog.notice(
                "[stats] snapshot — res=\(res) codec=\(codec) source=\(resSource)\(codecChanged ? " ⚠️codec-changed" : "")\(resChanged ? " ⚠️res-changed" : "")"
            )
        } else {
            playerLog.debug("[stats] snapshot — res=\(res) codec=\(codec) source=\(resSource)")
        }

        let snapshot = StatsForNerdsSnapshot(
            videoId: videoId,
            displayResolution: res,
            fps: fps,
            codec: codec,
            nominalBitrate: nominalBitrate,
            observedBitrate: observedBitrate,
            droppedFrames: droppedFrames,
            stalls: stalls,
            pendingQualityLabel: qualityManager.pendingQualityLabel,
            reportID: CrashlyticsLogger.sessionReportID,
            timeToPlayMs: timeToPlayMs,
            timeToHighQualityMs: timeToHighQualityMs,
            cacheStatus: cacheStatusSummary,
            streamURL: lastAttemptedStreamURL.map {
                let host = $0.host ?? ""
                let components = $0.pathComponents.filter { $0 != "/" }.prefix(3)
                let path = components.isEmpty ? "" : "/" + components.joined(separator: "/")
                return host + path
            } ?? "—",
            streamType: lastSuccessfulStreamType
        )
        statsSnapshot = playbackDiagnostics(snapshot: snapshot, item: item, accessLog: accessLog)
    }

    private func recordDeliveryChange(_ snapshot: StatsForNerdsSnapshot, previous: StatsForNerdsSnapshot) {
        let errorChanged =
            snapshot.errorLogEventCount != previous.errorLogEventCount
            || snapshot.errorLogDate != previous.errorLogDate || snapshot.errorLog != previous.errorLog
        let playbackChanged =
            snapshot.playerTimeControlStatus != previous.playerTimeControlStatus
            || snapshot.playerRate != previous.playerRate || snapshot.streamType != previous.streamType
        if snapshot.videoId != previous.videoId || snapshot.displayResolution != previous.displayResolution
            || errorChanged || playbackChanged
        {
            let errorDate = snapshot.errorLogDate?.formatted(.iso8601) ?? "—"
            let viewingBuffer = snapshot.bufferViewingSeconds.map { String(format: "%.1f", $0) } ?? "—"
            let details = [
                "report=\(snapshot.reportID)", "res=\(snapshot.displayResolution)", "rate=\(snapshot.playerRate ?? 0)",
                "viewingBuffer=\(viewingBuffer)s", "route=\(snapshot.streamType)",
                "advertised=\(snapshot.advertisedBitrate)", "errors=\(snapshot.errorLogEventCount)",
                "lastError=\(snapshot.errorLog)", "errorDate=\(errorDate)",
                "comment=\(snapshot.errorLogComment)", "resource=\(snapshot.errorLogResource)",
            ].joined(separator: " ")
            deliveryLog.notice("[hls-delivery] \(details, privacy: .public)")
        }
    }

    private func playbackDiagnostics(
        snapshot: StatsForNerdsSnapshot, item: AVPlayerItem, accessLog: AVPlayerItemAccessLog?
    ) -> StatsForNerdsSnapshot {
        var snapshot = snapshot
        let accessEvent = accessLog?.events.last
        snapshot.advertisedBitrate = Self.deliveryBitrateLabel(accessEvent?.indicatedBitrate)
        snapshot.accessLogEventCount = accessLog?.events.count ?? 0
        if let bytes = accessEvent?.numberOfBytesTransferred, bytes >= 0 {
            snapshot.downloadedBytes = bytes
        }
        snapshot.playerTimeControlStatus = Self.timeControlStatusLabel(player.timeControlStatus)
        snapshot.playerRate = player.rate
        snapshot.waitingReason = Self.waitingReasonLabel(player.reasonForWaitingToPlay)
        snapshot.itemStatus = Self.itemStatusLabel(item.status)
        snapshot.bufferAheadSeconds = Self.contiguousBufferAheadSeconds(for: item)
        snapshot.playbackBufferEmpty = item.isPlaybackBufferEmpty
        snapshot.playbackLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
        snapshot.itemError = Self.errorSummary(item.error)
        snapshot.playerError = Self.errorSummary(player.error)
        let errorLog = item.errorLog()
        let errorEvent = errorLog?.events.last
        snapshot.errorLog = Self.errorLogSummary(errorEvent)
        snapshot.errorLogDate = errorEvent?.date
        snapshot.errorLogEventCount = errorLog?.events.count ?? 0
        snapshot.errorLogComment = Self.errorLogCommentSummary(errorEvent?.errorComment)
        snapshot.errorLogResource = Self.errorResourceSummary(errorEvent?.uri)
        snapshot.peakBitrateLimit = item.preferredPeakBitRate
        recordDeliveryChange(snapshot, previous: statsSnapshot)
        return snapshot
    }

    static func timeControlStatusLabel(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .playing: return "playing"
        case .waitingToPlayAtSpecifiedRate: return "waiting"
        case .paused: return "paused"
        default: return "unknown"
        }
    }

    static func waitingReasonLabel(_ reason: AVPlayer.WaitingReason?) -> String {
        guard let reason else { return "—" }
        switch reason {
        case .toMinimizeStalls: return "toMinimizeStalls"
        case .evaluatingBufferingRate: return "evaluatingBufferingRate"
        case .noItemToPlay: return "noItemToPlay"
        default: return "unknown"
        }
    }

    static func itemStatusLabel(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown: return "unknown"
        case .readyToPlay: return "ready"
        case .failed: return "failed"
        @unknown default: return "unknown"
        }
    }

    static func errorSummary(_ error: Error?) -> String {
        guard let error else { return "—" }
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }

    static func errorLogSummary(_ event: AVPlayerItemErrorLogEvent?) -> String {
        guard let event else { return "—" }
        return "\(event.errorDomain)#\(event.errorStatusCode)"
    }

    static func errorLogCommentSummary(_ comment: String?) -> String {
        guard let comment, !comment.isEmpty else { return "—" }
        if let range = comment.range(
            of: #"(?<![A-Za-z0-9])HTTP[ \t]+[1-5][0-9]{2}(?![0-9])"#, options: .regularExpression)
        {
            return "HTTP \(comment[range].suffix(3))"
        }
        let pattern = #"^(Media (file|playlist) not received|No response for media file) in [0-9]+(\.[0-9]+)?s$"#
        guard comment.range(of: pattern, options: .regularExpression) == comment.startIndex..<comment.endIndex else {
            return "Details redacted"
        }
        return comment
    }

    static func deliveryBitrateLabel(_ bitrate: Double?) -> String {
        guard let bitrate, bitrate.isFinite, bitrate > 0, bitrate < Double(Int.max) else { return "—" }
        return formatBitrate(Int(bitrate))
    }

    static func errorResourceSummary(_ uri: String?) -> String {
        guard let uri, let components = URLComponents(string: uri),
            let url = components.url, let scheme = components.scheme,
            components.host?.isEmpty == false
        else { return "unknown" }
        let transport: String
        switch scheme.lowercased() {
        case "https": transport = "HTTPS"
        case "http": transport = "HTTP"
        case "ytwebhls": transport = "playlist proxy"
        default: return "unknown"
        }
        let pathFields = components.percentEncodedPath.split(separator: "/").map {
            String($0).removingPercentEncoding ?? String($0)
        }
        func values(for name: String) -> [String] {
            let queryValues = (components.queryItems ?? []).filter { $0.name == name }.compactMap(\.value)
            let pathValues = pathFields.indices.dropLast().compactMap { index in
                pathFields[index] == name ? pathFields[index + 1] : nil
            }
            return queryValues + pathValues
        }
        let mimeValues = Set(values(for: "mime"))
        let mime = mimeValues.count == 1 ? mimeValues.first : nil
        let category: String
        if url.pathExtension.lowercased() == "m3u8" {
            category = "playlist URL"
        } else if url.pathExtension.lowercased() == "vtt" || components.path == "/api/timedtext" {
            category = "captions URL"
        } else if let mime, ["audio/mp4", "audio/webm", "audio/aac", "audio/mpeg"].contains(mime) {
            category = "audio URL (MIME hint)"
        } else if let mime, ["video/mp4", "video/webm"].contains(mime) {
            category = "video URL (MIME hint)"
        } else if ["ts", "m4s", "mp4", "webm", "aac"].contains(url.pathExtension.lowercased()) {
            category = "media URL (track unknown)"
        } else {
            category = "unknown URL"
        }
        let itagValues = Set(values(for: "itag"))
        if itagValues.count == 1, let value = itagValues.first, let itag = Int(value), itag > 0 {
            return "\(category) · \(transport) · itag=\(itag)"
        }
        return "\(category) · \(transport)"
    }

    static func contiguousBufferAheadSeconds(for item: AVPlayerItem) -> Double? {
        let currentTime = CMTimeGetSeconds(item.currentTime())
        guard currentTime.isFinite, currentTime >= 0 else { return nil }

        let ranges = item.loadedTimeRanges.compactMap { value -> (start: Double, end: Double)? in
            let range = value.timeRangeValue
            let start = CMTimeGetSeconds(range.start)
            let duration = CMTimeGetSeconds(range.duration)
            guard start.isFinite, duration.isFinite, start >= 0, duration > 0 else { return nil }
            let end = start + duration
            guard end.isFinite, end > start else { return nil }
            return (start, end)
        }
        .sorted { $0.start < $1.start }

        var end = currentTime
        for range in ranges {
            guard range.end > end else { continue }
            guard range.start <= end else { break }
            end = range.end
        }
        return end > currentTime ? end - currentTime : 0
    }

    static func extractCodec(from mimeType: String) -> String {
        if mimeType.contains("mpegURL") || mimeType.contains("m3u8") { return "HLS" }
        if let range = mimeType.range(of: #"codecs="([^"]+)""#, options: .regularExpression) {
            let matched = String(mimeType[range])
            if let valueRange = matched.range(of: #"(?<==)[^"]+"#, options: .regularExpression) {
                let codecs = String(matched[valueRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let first =
                    codecs.components(separatedBy: ",").first?
                    .trimmingCharacters(in: .whitespaces) ?? codecs
                return first.components(separatedBy: ".").first ?? first
            }
        }
        if mimeType.contains("mp4") { return "mp4" }
        if mimeType.contains("webm") { return "webm" }
        return mimeType.isEmpty ? "—" : mimeType
    }

    static func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 { return String(format: "%.1f Mbps", Double(bps) / 1_000_000) }
        if bps >= 1_000 { return String(format: "%.0f kbps", Double(bps) / 1_000) }
        return "\(bps) bps"
    }
}

// MARK: - StatsForNerdsSnapshot

/// Snapshot of playback diagnostics for the "Stats for Nerds" overlay.
public struct StatsForNerdsSnapshot: Sendable {
    public var videoId: String
    public var displayResolution: String
    public var fps: Int
    public var codec: String
    public var nominalBitrate: String
    public var observedBitrate: String
    public var droppedFrames: Int
    public var stalls: Int
    /// Quality label most recently selected by the user — persists after CDN failures
    /// so Stats for Nerds can show user intent vs actual delivery.
    public var pendingQualityLabel: String
    /// Session report ID — matches the `report_id` custom key stamped on Crashlytics
    /// reports. Quote this when sending a diagnostic report so the developer can
    /// locate the exact session in Firebase.
    public var reportID: String
    /// Elapsed ms from `load()` to the first `readyToPlay` (low-quality fast-start frame). 0 = not yet measured.
    public var timeToPlayMs: Int
    /// Elapsed ms from `load()` to the quality-ramp task firing (~readyToPlay + 800 ms). 0 = not yet measured.
    public var timeToHighQualityMs: Int
    /// Cache hit/miss summary at load time (e.g. "pi:HIT wkHLS:MISS").
    public var cacheStatus: String
    /// Host + path of the stream URL handed to AVPlayer (no query string). Empty when not yet loaded.
    public var streamURL: String
    /// Which loading path produced the current stream (e.g. "primaryHLS", "webView/HLS").
    public var streamType: String
    public var playerTimeControlStatus: String = "unknown"
    public var playerRate: Float?
    public var waitingReason: String = "—"
    public var itemStatus: String = "unknown"
    public var bufferAheadSeconds: Double?
    public var playbackBufferEmpty: Bool?
    public var playbackLikelyToKeepUp: Bool?
    public var itemError: String = "—"
    public var playerError: String = "—"
    public var errorLog: String = "—"
    public var errorLogDate: Date?
    public var errorLogEventCount: Int = 0
    public var errorLogComment: String = "—"
    public var errorLogResource: String = "unknown"
    public var advertisedBitrate: String = "—"
    public var accessLogEventCount: Int = 0
    public var downloadedBytes: Int64?
    public var peakBitrateLimit: Double?

    public func errorLogAgeSeconds(at now: Date = Date()) -> TimeInterval? {
        guard let errorLogDate else { return nil }
        let age = now.timeIntervalSince(errorLogDate)
        return age.isFinite && age >= 0 ? age : nil
    }

    public var bufferViewingSeconds: Double? {
        guard let seconds = bufferAheadSeconds, seconds.isFinite, seconds >= 0,
            let rate = playerRate, rate.isFinite, rate > 0
        else { return nil }
        return seconds / Double(rate)
    }

    public static let empty = StatsForNerdsSnapshot(
        videoId: "",
        displayResolution: "",
        fps: 0,
        codec: "",
        nominalBitrate: "",
        observedBitrate: "",
        droppedFrames: 0,
        stalls: 0,
        pendingQualityLabel: "",
        reportID: CrashlyticsLogger.sessionReportID,
        timeToPlayMs: 0,
        timeToHighQualityMs: 0,
        cacheStatus: "",
        streamURL: "",
        streamType: "",
        playerTimeControlStatus: "unknown",
        playerRate: nil,
        waitingReason: "—",
        itemStatus: "unknown",
        bufferAheadSeconds: nil,
        playbackBufferEmpty: nil,
        playbackLikelyToKeepUp: nil,
        itemError: "—",
        playerError: "—",
        errorLog: "—"
    )
}
