import AVFoundation
import Foundation

extension PlaybackViewModel {
    func monitorPlaybackDiagnostics() async {
        guard let configuration = PlaybackDiagnosticsConfiguration(),
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        if playbackDiagnosticsReporter == nil {
            playbackDiagnosticsReporter = PlaybackDiagnosticsReporter(
                configuration: configuration,
                storeURL: cache.appendingPathComponent("PlaybackDiagnostics/pending.json"))
        }
        guard let reporter = playbackDiagnosticsReporter else { return }
        while !Task.isCancelled {
            if let item = player.currentItem {
                updateStatsSnapshot()
                let snapshot = statsSnapshot
                let nativeErrors = item.errorLog()?.events ?? []
                let now = Date()
                let state = [
                    snapshot.videoId, snapshot.displayResolution, snapshot.streamType,
                    snapshot.itemStatus, snapshot.playerTimeControlStatus, snapshot.waitingReason,
                    snapshot.itemError, snapshot.playerError, "\(snapshot.playerRate ?? 0)",
                ].joined(separator: "|")
                let decision = playbackDiagnosticsSampler.sample(
                    itemID: ObjectIdentifier(item), errorCount: nativeErrors.count, state: state, at: now)
                let access = item.accessLog()?.events.last
                let advertisedBitrate = access?.indicatedBitrate
                var events: [PlaybackDeliveryEvent] = []
                if decision.emitSnapshot {
                    events.append(
                        Self.deliveryEvent(
                            snapshot, advertisedBitrate: advertisedBitrate, observedBitrate: access?.observedBitrate,
                            playbackPosition: item.currentTime().seconds, at: now))
                }
                for index in decision.errorIndices {
                    let nativeError = nativeErrors[index]
                    var errorSnapshot = snapshot
                    errorSnapshot.errorLog = Self.errorLogSummary(nativeError)
                    errorSnapshot.errorLogDate = nativeError.date
                    errorSnapshot.errorLogEventCount = index + 1
                    errorSnapshot.errorLogComment = Self.errorLogCommentSummary(nativeError.errorComment)
                    errorSnapshot.errorLogResource = Self.errorResourceSummary(nativeError.uri)
                    events.append(
                        Self.deliveryEvent(
                            errorSnapshot, advertisedBitrate: advertisedBitrate,
                            observedBitrate: access?.observedBitrate, playbackPosition: item.currentTime().seconds,
                            at: now))
                }
                await reporter.enqueue(events)
            }
            await reporter.flush()
            do {
                try await Task.sleep(for: PlaybackDiagnosticsSampler.interval)
            } catch { return }
        }
    }

    static func deliveryEvent(
        _ snapshot: StatsForNerdsSnapshot, advertisedBitrate: Double?, observedBitrate: Double?,
        playbackPosition: Double? = nil, at now: Date
    ) -> PlaybackDeliveryEvent {
        func safeText(_ value: String, pattern: String, fallback: String = "unknown") -> String {
            value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
                ? value : fallback
        }
        func finiteNonnegative(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }
        let errorParts = snapshot.errorLog.split(separator: "#", maxSplits: 1).map(String.init)
        let domain =
            errorParts.count == 2
            ? safeText(errorParts[0], pattern: #"^[A-Za-z0-9_.-]{1,80}$"#, fallback: "") : ""
        let code = domain.isEmpty ? nil : Int(errorParts[1])
        let rate = snapshot.playerRate.map(Double.init).flatMap { value -> Double? in
            value.isFinite && (0...4).contains(value) ? value : nil
        }
        let resolution = snapshot.displayResolution.replacingOccurrences(of: "×", with: "x")
        return PlaybackDeliveryEvent(
            timestamp: now,
            reportID: safeText(snapshot.reportID, pattern: #"^[A-Za-z0-9_-]{1,64}$"#),
            videoID: safeText(snapshot.videoId, pattern: #"^[A-Za-z0-9_-]{1,64}$"#),
            resolution: safeText(resolution, pattern: #"^[0-9]+x[0-9]+$"#),
            rate: rate,
            bufferMediaSeconds: finiteNonnegative(snapshot.bufferAheadSeconds),
            bufferViewingSeconds: finiteNonnegative(snapshot.bufferViewingSeconds),
            itemStatus: snapshot.itemStatus,
            playbackStatus: snapshot.playerTimeControlStatus,
            waitingReason: snapshot.waitingReason,
            streamRoute: safeText(snapshot.streamType, pattern: #"^[A-Za-z0-9/._ -]{1,100}$"#),
            advertisedBitrateBps: finiteNonnegative(advertisedBitrate).flatMap { $0 > 0 ? $0 : nil },
            observedBitrateBps: finiteNonnegative(observedBitrate).flatMap { $0 > 0 ? $0 : nil },
            downloadedBytes: snapshot.downloadedBytes,
            droppedFrames: max(0, snapshot.droppedFrames),
            stalls: max(0, snapshot.stalls),
            peakBitrateBps: finiteNonnegative(snapshot.peakBitrateLimit),
            accessEventCount: max(0, snapshot.accessLogEventCount),
            errorEventCount: max(0, snapshot.errorLogEventCount),
            errorDomain: code == nil ? nil : domain,
            errorCode: code,
            errorTimestamp: snapshot.errorLogDate,
            errorComment: snapshot.errorLogComment == "—" ? "—" : Self.errorLogCommentSummary(snapshot.errorLogComment),
            errorResource: snapshot.errorLogResource,
            playbackPositionSeconds: finiteNonnegative(playbackPosition))
    }
}
