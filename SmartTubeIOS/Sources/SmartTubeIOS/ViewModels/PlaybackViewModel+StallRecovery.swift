import AVFoundation
import SmartTubeIOSCore
import os

private let playerLog = CrashlyticsLogger(category: "Player")

extension PlaybackViewModel {
    func scheduleStallSeekRecovery(count: Int, source: AVPlayer?) {
        let stalledItem = player.currentItem
        Task { @MainActor [weak self, weak source, weak stalledItem] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.isCurrentPlayback(source),
                let stalledItem, self.player.currentItem === stalledItem, stalledItem.status != .failed,
                !self.isPlaying, self.player.rate == 0,
                !self.isQualityChangePending, !self.isSwappingItem
            else { return }
            let seekT = self.currentTime
            playerLog.notice(
                "[rateObserver] recovery#\(count): seeking to \(seekT)s to flush pipeline")
            self.player.seek(
                to: CMTime(seconds: seekT, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
            ) { [weak self, weak source, weak stalledItem] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentPlayback(source),
                        let stalledItem, self.player.currentItem === stalledItem,
                        stalledItem.status != .failed,
                        !self.isPlaying, self.player.rate == 0
                    else { return }
                    self.player.rate = Float(self.settings.playbackSpeed)
                    self.isPlaying = true
                    playerLog.notice(
                        "[rateObserver] recovery#\(count): rate restored, isPlaying=true")
                }
            }
        }
    }
}
