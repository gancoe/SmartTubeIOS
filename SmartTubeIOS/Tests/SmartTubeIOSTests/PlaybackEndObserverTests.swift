import AVFoundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Native playback end observer")
@MainActor
struct PlaybackEndObserverTests {
    @Test("Stopping immediately after an item swap ignores its queued end event")
    func stoppingBeforeObserverRebindIgnoresEnd() async {
        let player = EndObserverTestPlayer()
        let viewModel = endObserverViewModel(player: player)
        viewModel.settings.autoplayEnabled = true
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        viewModel.relatedVideos = [Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")]
        let item = EndObserverTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        viewModel.stop()
        await drainEndObserverTasks()
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: item)
        await drainEndObserverTasks()
        #expect(viewModel.currentVideo?.id == "current")
        finishEndObserverTest(viewModel)
    }

    @Test("the current item end notification advances to a recommendation")
    func currentItemEndAdvances() async {
        let player = EndObserverTestPlayer()
        let viewModel = endObserverViewModel(player: player)
        viewModel.settings.autoplayEnabled = true
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]
        let item = EndObserverTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainEndObserverTasks()

        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: item)

        #expect(await eventuallyEndObserver { viewModel.currentVideo?.id == recommendation.id })
        finishEndObserverTest(viewModel)
    }

    @Test("an old item end notification is ignored after the player swaps items")
    func staleItemEndIsIgnored() async {
        let player = EndObserverTestPlayer()
        let viewModel = endObserverViewModel(player: player)
        viewModel.settings.autoplayEnabled = true
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]
        let oldItem = EndObserverTestItem(url: URL(fileURLWithPath: "/dev/null"))
        let currentItem = EndObserverTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: oldItem)
        await drainEndObserverTasks()
        player.replaceCurrentItem(with: currentItem)
        await drainEndObserverTasks()

        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: oldItem)
        await drainEndObserverTasks()

        #expect(viewModel.currentVideo?.id == "current")
        #expect(!viewModel.videoEnded)
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: currentItem)
        #expect(await eventuallyEndObserver { viewModel.currentVideo?.id == recommendation.id })
        finishEndObserverTest(viewModel)
    }

    @Test("autoplay disabled marks the video ended without loading a recommendation")
    func autoplayDisabledEndsVideo() async {
        let player = EndObserverTestPlayer()
        let viewModel = endObserverViewModel(player: player)
        viewModel.settings.autoplayEnabled = false
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]
        let item = EndObserverTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainEndObserverTasks()

        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: item)

        #expect(await eventuallyEndObserver { viewModel.videoEnded })
        #expect(viewModel.currentVideo?.id == "current")
        finishEndObserverTest(viewModel)
    }

    @Test("the end observer is rebound after a media-services player reset")
    func resetRebindsEndObserver() async {
        let player = EndObserverTestPlayer()
        let replacement = EndObserverTestPlayer()
        let viewModel = endObserverViewModel(player: player)
        viewModel.makeRecoveryPlayer = { replacement }
        viewModel.settings.autoplayEnabled = true
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]
        let item = EndObserverTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainEndObserverTasks()

        viewModel.error = NSError(
            domain: AVFoundationErrorDomain,
            code: PlaybackViewModel.mediaServicesResetCode
        )
        #expect(viewModel.prepareRetryAfterMediaReset())
        let replacementItem = EndObserverTestItem(url: URL(fileURLWithPath: "/dev/null"))
        replacement.replaceCurrentItem(with: replacementItem)
        await drainEndObserverTasks()

        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: replacementItem
        )

        #expect(await eventuallyEndObserver { viewModel.currentVideo?.id == recommendation.id })
        finishEndObserverTest(viewModel)
    }

    @Test("tvOS recommendation autoplay exposes a cancellable countdown")
    func recommendationCountdownCanBeCancelled() {
        let viewModel = endObserverViewModel(player: EndObserverTestPlayer())
        viewModel.autoplayCountdownEnabled = true
        viewModel.autoplayCountdownSleep = { _ in throw CancellationError() }
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]

        viewModel.handlePlaybackEnd()
        #expect(viewModel.pendingAutoplayVideo?.id == recommendation.id)
        #expect(viewModel.autoplayCountdown == PlaybackTuning.autoplayCountdownSeconds)
        viewModel.cancelAutoplay()

        #expect(viewModel.pendingAutoplayVideo == nil)
        #expect(viewModel.autoplayCountdown == nil)
        #expect(viewModel.videoEnded)
        finishEndObserverTest(viewModel)
    }

    @Test("play now clears the countdown and loads the pending recommendation")
    func playNowLoadsPendingRecommendation() {
        let viewModel = endObserverViewModel(player: EndObserverTestPlayer())
        viewModel.autoplayCountdownEnabled = true
        viewModel.autoplayCountdownSleep = { _ in throw CancellationError() }
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]

        viewModel.handlePlaybackEnd()
        viewModel.playAutoplayNow()

        #expect(viewModel.currentVideo?.id == recommendation.id)
        #expect(viewModel.pendingAutoplayVideo == nil)
        #expect(viewModel.autoplayCountdown == nil)
        finishEndObserverTest(viewModel)
    }

    @Test("a cancelled countdown cannot load its stale recommendation")
    func staleCountdownCompletionIsIgnored() async {
        let clock = ManualCountdownClock()
        let viewModel = endObserverViewModel(player: EndObserverTestPlayer())
        viewModel.autoplayCountdownEnabled = true
        viewModel.autoplayCountdownSleep = { duration in try await clock.sleep(duration) }
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]

        viewModel.handlePlaybackEnd()
        #expect(await eventuallyEndObserver { clock.waiterCount == 1 })
        viewModel.cancelAutoplay()
        clock.resumeNext()
        await drainEndObserverTasks()

        #expect(viewModel.currentVideo?.id == "current")
        #expect(viewModel.pendingAutoplayVideo == nil)
        #expect(viewModel.videoEnded)
        finishEndObserverTest(viewModel)
    }

    @Test("the full recommendation countdown expires and loads the pending video")
    func countdownExpiryLoadsRecommendation() async {
        let clock = ManualCountdownClock()
        let viewModel = endObserverViewModel(player: EndObserverTestPlayer())
        viewModel.autoplayCountdownEnabled = true
        viewModel.autoplayCountdownSleep = { duration in try await clock.sleep(duration) }
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]

        viewModel.handlePlaybackEnd()
        for expected in stride(from: PlaybackTuning.autoplayCountdownSeconds, through: 1, by: -1) {
            #expect(await eventuallyEndObserver { clock.waiterCount == 1 })
            #expect(viewModel.autoplayCountdown == expected)
            clock.resumeNext()
        }

        #expect(await eventuallyEndObserver { viewModel.currentVideo?.id == recommendation.id })
        viewModel.loadTask?.cancel()
        finishEndObserverTest(viewModel)
    }

    @Test("stopping during the countdown prevents a late recommendation load")
    func stopCancelsCountdown() async {
        let clock = ManualCountdownClock()
        let viewModel = endObserverViewModel(player: EndObserverTestPlayer())
        viewModel.autoplayCountdownEnabled = true
        viewModel.autoplayCountdownSleep = { duration in try await clock.sleep(duration) }
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]

        viewModel.handlePlaybackEnd()
        #expect(await eventuallyEndObserver { clock.waiterCount == 1 })
        viewModel.stop()
        clock.resumeNext()
        await drainEndObserverTasks()

        #expect(viewModel.currentVideo?.id == "current")
        #expect(viewModel.pendingAutoplayVideo == nil)
        #expect(viewModel.autoplayCountdown == nil)
    }

    @Test("suspending during the countdown prevents a late recommendation load")
    func suspendCancelsCountdown() async {
        let clock = ManualCountdownClock()
        let viewModel = endObserverViewModel(player: EndObserverTestPlayer())
        viewModel.autoplayCountdownEnabled = true
        viewModel.autoplayCountdownSleep = { duration in try await clock.sleep(duration) }
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]

        viewModel.handlePlaybackEnd()
        #expect(await eventuallyEndObserver { clock.waiterCount == 1 })
        viewModel.suspend()
        clock.resumeNext()
        await drainEndObserverTasks()

        #expect(viewModel.currentVideo?.id == "current")
        #expect(viewModel.pendingAutoplayVideo == nil)
        #expect(viewModel.autoplayCountdown == nil)
    }

    @Test("backgrounding during the countdown prevents a late recommendation load")
    func backgroundCancelsCountdown() async {
        let clock = ManualCountdownClock()
        let viewModel = endObserverViewModel(player: EndObserverTestPlayer())
        viewModel.autoplayCountdownEnabled = true
        viewModel.autoplayCountdownSleep = { duration in try await clock.sleep(duration) }
        viewModel.settings.backgroundPlaybackEnabled = false
        viewModel.isPlaying = true
        viewModel.currentVideo = Video(id: "current", title: "Current", channelTitle: "Test")
        let recommendation = Video(id: "recommendation", title: "Recommendation", channelTitle: "Test")
        viewModel.relatedVideos = [recommendation]

        viewModel.handlePlaybackEnd()
        #expect(await eventuallyEndObserver { clock.waiterCount == 1 })
        viewModel.handleBackground()
        clock.resumeNext()
        await drainEndObserverTasks()

        #expect(viewModel.currentVideo?.id == "current")
        #expect(viewModel.pendingAutoplayVideo == nil)
        #expect(viewModel.autoplayCountdown == nil)
        finishEndObserverTest(viewModel)
    }
}

@MainActor
private func endObserverViewModel(player: AVPlayer) -> PlaybackViewModel {
    let viewModel = PlaybackViewModel(player: player)
    viewModel.loadVideoOperation = { _ in }
    return viewModel
}

@MainActor
private func drainEndObserverTasks() async {
    for _ in 0..<100 { await Task.yield() }
}

@MainActor
private func eventuallyEndObserver(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<1000 {
        if predicate() { return true }
        await Task.yield()
    }
    return predicate()
}

@MainActor
private func finishEndObserverTest(_ viewModel: PlaybackViewModel) {
    viewModel.currentVideo = nil
    viewModel.stop()
}

@MainActor
private final class ManualCountdownClock {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var waiterCount: Int { waiters.count }

    func sleep(_: Duration) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    func resumeNext() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }
}

private final class EndObserverTestPlayer: AVPlayer {
    nonisolated(unsafe) private var item: AVPlayerItem?

    override var currentItem: AVPlayerItem? { item }

    override func replaceCurrentItem(with item: AVPlayerItem?) {
        willChangeValue(forKey: #keyPath(AVPlayer.currentItem))
        self.item = item
        didChangeValue(forKey: #keyPath(AVPlayer.currentItem))
    }

    override func seek(
        to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
        completionHandler: @escaping @Sendable (Bool) -> Void
    ) {}
}

private final class EndObserverTestItem: AVPlayerItem {}
