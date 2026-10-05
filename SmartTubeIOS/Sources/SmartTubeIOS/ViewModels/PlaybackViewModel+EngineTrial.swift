import AVFoundation
import SmartTubeIOSCore

extension PlaybackViewModel {
    var availableEngineTrialSource: PlaybackEngineTrialSource? {
        guard let source = playbackEngineTrialSource,
            let asset = player.currentItem?.asset as? AVURLAsset,
            source.matches(activeURL: asset.url.realURL ?? asset.url), !isLoading
        else { return nil }
        return source
    }

    func suspendForEngineTrial() {
        suspend()
        qualityManager.cancelHLSForwardBufferRamp()
        suspendPlaybackDiagnostics()
        cancelPlaybackDiagnosticsNativeMetrics()
        nativeVP9RecoveryTask?.cancel()
        nativeVP9RecoveryTask = nil
        phase2Task?.cancel()
        phase2Task = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        itemObserverTask?.cancel()
        itemObserverTask = nil
        stallObserverTask?.cancel()
        stallObserverTask = nil
        durationObserverTask?.cancel()
        durationObserverTask = nil
        player.replaceCurrentItem(with: nil)
        parkedVideoId = nil
    }

    func reloadAfterEngineTrial(video: Video, position: Double, rate: Double) {
        settings.playbackSpeed = rate
        load(video: video)
        savedPositionToRestore = max(0, position)
    }
}
