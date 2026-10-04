import AVFoundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Native playback item failure")
@MainActor
struct PlaybackItemFailureTests {
    @Test("a media-services reset after readiness exposes retry without leaving the video")
    func postReadyResetExposesRetry() async {
        let player = FailureTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentVideo = Video(id: "failure-test", title: "Test", channelTitle: "Test")
        viewModel.currentTime = 123
        viewModel.isPlaying = true
        let item = FailureTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainTasks()
        item.transition(to: .readyToPlay)
        await drainTasks()
        item.transition(to: .failed, error: resetError)

        #expect(await eventually { viewModel.error != nil })
        #expect((viewModel.error as NSError?)?.code == -11819)
        #expect(!viewModel.isPlaying)
        #expect(viewModel.currentTime == 123)
        finish(viewModel)
    }

    @Test("Play rebuilds the reset player, rebinds managers and preserves the requested position")
    func playRebuildsAndPreservesPosition() async {
        let player = FailureTestPlayer()
        let replacement = FailureTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.makeRecoveryPlayer = { replacement }
        viewModel.currentVideo = Video(id: "failure-test", title: "Test", channelTitle: "Test")
        viewModel.currentTime = 123
        let item = FailureTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainTasks()
        item.transition(to: .readyToPlay)
        await drainTasks()
        item.transition(to: .failed, error: resetError)
        #expect(await eventually { viewModel.error != nil })
        viewModel.seekRelative(seconds: 10)

        viewModel.togglePlayPause()

        #expect(viewModel.player === replacement)
        #expect(player.currentItem == nil)
        #expect(viewModel.audioManager.player === replacement)
        #expect(viewModel.qualityManager.player === replacement)
        #expect(viewModel.sponsorBlockManager.player === replacement)
        #expect(viewModel.savedPositionToRestore == 133)
        #expect(viewModel.pendingSeekTarget == nil)
        #expect(viewModel.isLoading)
        finish(viewModel)
    }

    @Test("a replaced item cannot expose its failure on the new item")
    func replacedItemCannotFailNewItem() async {
        let player = FailureTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentVideo = Video(id: "failure-test", title: "Test", channelTitle: "Test")
        let oldItem = FailureTestItem(url: URL(fileURLWithPath: "/dev/null"))
        let newItem = FailureTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: oldItem)
        await drainTasks()
        player.replaceCurrentItem(with: newItem)
        oldItem.transition(to: .failed, error: resetError)
        await drainTasks()

        #expect(viewModel.error == nil)
        #expect(viewModel.player.currentItem === newItem)
        finish(viewModel)
    }

    @Test("stop cancels an already queued failure callback")
    func stopCancelsQueuedFailure() async {
        let player = FailureTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        let item = FailureTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainTasks()

        item.transition(to: .failed, error: resetError)
        viewModel.stop()
        await drainTasks()

        #expect(viewModel.error == nil)
        #expect(viewModel.exhaustiveRetryTask == nil)
        #expect(!viewModel.isPlaying)
    }

    @Test("an old video failure cannot interrupt a different video")
    func oldVideoCannotInterruptNewVideo() async {
        let player = FailureTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentVideo = Video(id: "old-video", title: "Old", channelTitle: "Test")
        let item = FailureTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainTasks()

        item.transition(to: .failed, error: resetError)
        viewModel.currentVideo = Video(id: "new-video", title: "New", channelTitle: "Test")
        await drainTasks()

        #expect(viewModel.error == nil)
        finish(viewModel)
    }

    @Test("the reset code from another error domain does not rebuild the player")
    func unrelatedErrorDomainDoesNotRebuild() {
        let player = FailureTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentVideo = Video(id: "failure-test", title: "Test", channelTitle: "Test")
        viewModel.error = NSError(domain: NSURLErrorDomain, code: -11819)
        viewModel.retryLoad()

        #expect(viewModel.player === player)
        #expect(viewModel.savedPositionToRestore == nil)
        finish(viewModel)
    }

    @Test("reopening a parked ready item restores failure observation")
    func parkedItemReopenRestoresObservation() async {
        let player = FailureTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        let video = Video(id: "failure-test", title: "Test", channelTitle: "Test")
        let item = FailureTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        item.transition(to: .readyToPlay)
        viewModel.stop()
        viewModel.parkedVideoId = video.id

        viewModel.load(video: video)
        await drainTasks()
        item.transition(to: .failed, error: resetError)

        #expect(await eventually { viewModel.error != nil })
        #expect(!viewModel.isPlaying)
        finish(viewModel)
    }
}

private let resetError = NSError(domain: AVFoundationErrorDomain, code: -11819)

@MainActor
private func finish(_ viewModel: PlaybackViewModel) {
    viewModel.currentVideo = nil
    viewModel.stop()
}

@MainActor
private func drainTasks() async {
    for _ in 0..<100 { await Task.yield() }
}

@MainActor
private func eventually(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<1000 {
        if predicate() { return true }
        await Task.yield()
    }
    return predicate()
}

private final class FailureTestPlayer: AVPlayer {
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

private final class FailureTestItem: AVPlayerItem {
    nonisolated(unsafe) private var controlledStatus: AVPlayerItem.Status = .unknown
    nonisolated(unsafe) private var controlledError: Error?

    override var status: AVPlayerItem.Status { controlledStatus }
    override var error: Error? { controlledError }

    func transition(to status: AVPlayerItem.Status, error: Error? = nil) {
        willChangeValue(forKey: #keyPath(AVPlayerItem.status))
        controlledError = error
        controlledStatus = status
        didChangeValue(forKey: #keyPath(AVPlayerItem.status))
    }
}
