import AVFoundation
import SmartTubeIOSCore

#if canImport(UIKit)
import UIKit
#endif

extension PlaybackViewModel {
    #if canImport(UIKit)
    nonisolated static let mediaServicesResetCode = AVError.Code.mediaServicesWereReset.rawValue
    #else
    nonisolated static let mediaServicesResetCode = -11819
    #endif

    nonisolated static func isMediaServicesReset(_ error: Error?) -> Bool {
        #if os(iOS)
        return false
        #else
        guard let error = error as NSError? else { return false }
        return error.domain == AVFoundationErrorDomain && error.code == mediaServicesResetCode
        #endif
    }

    func setupFailureObserver() {
        guard failurePlayerObserver == nil else { return }
        let observationID = failureObservationID
        let observer = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] source, _ in
            let item = source.currentItem
            Task { @MainActor [weak self, weak source] in
                guard let self, let source, self.player === source,
                    self.failureObservationID == observationID,
                    self.player.currentItem === item
                else { return }
                self.observeItemFailure(item, observationID: observationID)
            }
        }
        failurePlayerObserver = observer
    }

    func isCurrentPlayback(_ source: AVPlayer?) -> Bool {
        player === source && player.currentItem?.status != .failed
    }

    func cancelFailureObserver() {
        failureObservationID &+= 1
        failurePlayerObserver?.invalidate()
        failurePlayerObserver = nil
        failureItemObserver?.invalidate()
        failureItemObserver = nil
    }

    private func observeItemFailure(_ item: AVPlayerItem?, observationID: UInt) {
        failureItemObserver?.invalidate()
        failureItemObserver = nil
        guard let item else { return }
        let videoID = currentVideo?.id
        failureItemObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed, Self.isMediaServicesReset(item.error) else { return }
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.failureObservationID == observationID,
                    self.player.currentItem === item, self.currentVideo?.id == videoID
                else { return }
                self.handleMediaServicesReset()
            }
        }
    }

    private func handleMediaServicesReset() {
        isPlaying = false
        player.pause()
        cancelPlaybackWorkAfterFailure()
        isLoading = false
        isQualityChangePending = false
        error = NSError(
            domain: AVFoundationErrorDomain, code: Self.mediaServicesResetCode,
            userInfo: [NSLocalizedDescriptionKey: "Playback stopped. Press Play or Try Again to resume."])
        showControls()
        updateStatsSnapshot()
    }

    private func cancelPlaybackWorkAfterFailure() {
        loadTask?.cancel()
        loadTask = nil
        exhaustiveRetryTask?.cancel()
        exhaustiveRetryTask = nil
        phase2Task?.cancel()
        phase2Task = nil
        itemObserverTask?.cancel()
        itemObserverTask = nil
        endObserverTask?.cancel()
        endObserverTask = nil
        stallObserverTask?.cancel()
        stallObserverTask = nil
        durationObserverTask?.cancel()
        durationObserverTask = nil
        qualityManager.cancel()
    }

    @discardableResult
    func prepareRetryAfterMediaReset() -> Bool {
        guard
            Self.isMediaServicesReset(error) || Self.isMediaServicesReset(player.currentItem?.error)
                || Self.isMediaServicesReset(player.error)
        else { return false }
        let position = pendingSeekTarget ?? currentTime
        savedPositionToRestore = position.isFinite ? max(0, position) : 0
        invalidatePendingSeek()
        cancelPlaybackWorkAfterFailure()
        rebuildPlayerAfterMediaReset()
        return true
    }

    private func rebuildPlayerAfterMediaReset() {
        cancelFailureObserver()
        rateObserver?.invalidate()
        rateObserver = nil
        airPlayObserver?.invalidate()
        airPlayObserver = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        isPlaying = false
        player.pause()
        let oldPlayer = player
        oldPlayer.replaceCurrentItem(with: nil)
        player = makeRecoveryPlayer()
        player.allowsExternalPlayback = oldPlayer.allowsExternalPlayback
        player.volume = oldPlayer.volume
        player.isMuted = oldPlayer.isMuted
        qualityManager.player = player
        audioManager.reset()
        audioManager.player = player
        sponsorBlockManager.player = player
        parkedVideoId = nil
        isQualityChangePending = false
        isSwappingItem = false
        setupTimeObserver()
        setupRateObserver()
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        setupAirPlayObserver()
        #endif
    }
}
