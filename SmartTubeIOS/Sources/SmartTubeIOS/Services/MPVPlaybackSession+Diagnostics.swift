#if os(tvOS) && canImport(Libmpv)

import Foundation

extension MPVPlaybackSession {
    func monitorDiagnostics(videoID: String, reportID: String) async {
        guard let configuration = PlaybackDiagnosticsConfiguration(),
            let captureID = configuration.captureID,
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }

        let stateRoot =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? cache
        let captureSession = PlaybackDiagnosticsCaptureSession(
            captureID: captureID,
            stateURL: stateRoot.appendingPathComponent("PlaybackDiagnostics/capture-state.json"),
            defaults: .standard)
        let reporter = PlaybackDiagnosticsReporter(
            configuration: configuration,
            storeURL: cache.appendingPathComponent("MPVDiagnostics/pending.json"))

        while !Task.isCancelled {
            captureSession.refresh()
            guard captureSession.isCapturing else { break }
            let snapshot = MPVPlaybackDiagnosticSnapshot(
                reportID: reportID,
                videoID: videoID,
                currentTime: currentTime,
                rate: rate,
                bufferSeconds: bufferSeconds,
                isPlaying: isPlaying,
                isBuffering: isBuffering,
                isReady: isReady,
                isSeeking: isSeeking,
                hasEnded: hasEnded,
                videoWidth: videoWidth,
                videoHeight: videoHeight,
                downloadMbps: downloadMbps,
                droppedFrames: diagnosticsDroppedFrames,
                stalls: diagnosticsStalls,
                errorEventCount: diagnosticsErrorEventCount,
                errorCode: diagnosticsErrorCode,
                errorTimestamp: diagnosticsErrorTimestamp,
                captureID: captureID,
                captureState: captureSession.state.rawValue)
            await reporter.enqueue([snapshot.deliveryEvent()])
            await reporter.flush()
            if isStopped { break }
            do {
                try await Task.sleep(for: PlaybackDiagnosticsSampler.interval)
            } catch {
                return
            }
        }
    }
}

#endif
