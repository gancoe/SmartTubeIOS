import AVFoundation
import SmartTubeIOSCore
import Testing

@testable import SmartTubeIOS

@Suite("Native 4K recovery")
@MainActor
struct Native4KRecoveryTests {
    @Test("the recovered H264 item still reports playback end")
    func recoveredItemRetainsEndObserver() async {
        let player = NativeRecoveryTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.settings.historyState = .disabled
        viewModel.settings.autoplayEnabled = false
        viewModel.currentVideo = Video(id: "native-end", title: "Test", channelTitle: "Test")
        viewModel.isLoading = false
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        let recovered = NativeRecoveryTestItem(url: URL(fileURLWithPath: "/dev/null"))
        viewModel.nativeVP9RecoveryOperation = { [weak viewModel] _, _ in
            viewModel?.qualityManager.configureHLSPlayback(
                userAgent: "test", maximumHeight: 1080, allowedVideoCodecs: ["avc1"])
            player.replaceCurrentItem(with: recovered)
            recovered.transition(to: .readyToPlay)
            viewModel?.isLoading = false
        }
        let failed = NativeRecoveryTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: failed)
        await drainNativeRecoveryTasks()
        failed.transition(to: .readyToPlay)
        await drainNativeRecoveryTasks()
        failed.transition(to: .failed, error: nativeDecodeError)
        await eventuallyNativeRecovery { player.currentItem === recovered }
        #expect(player.currentItem === recovered)
        await drainNativeRecoveryTasks()

        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: recovered)
        await eventuallyNativeRecovery { viewModel.videoEnded }
        #expect(viewModel.videoEnded)
        finishNativeRecovery(viewModel)
    }

    @Test("rapid native VP9 stall rejection preserves the pending position")
    func stallRejectionPreservesPosition() {
        let viewModel = PlaybackViewModel(player: NativeRecoveryTestPlayer())
        viewModel.currentTime = 64
        viewModel.pendingSeekTarget = 71
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"]
        )

        viewModel.rejectNativeVP9AfterStall()

        #expect(viewModel.nativeVP9Rejected)
        #expect(viewModel.savedPositionToRestore == 71)
        #expect(viewModel.pendingSeekTarget == nil)
    }

    @Test("non-native stall rejection leaves the recovery gate unchanged")
    func nonNativeStallDoesNotReject() {
        let viewModel = PlaybackViewModel(player: NativeRecoveryTestPlayer())
        viewModel.currentTime = 64
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 1080, allowedVideoCodecs: ["avc1"]
        )

        viewModel.rejectNativeVP9AfterStall()

        #expect(!viewModel.nativeVP9Rejected)
        #expect(viewModel.savedPositionToRestore == nil)
    }

    @Test("a late native VP9 failure autorecovers once and preserves the pending position")
    func lateFailureRecoversOnce() async {
        let player = NativeRecoveryTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        let video = Video(id: "native-recovery", title: "Test", channelTitle: "Test")
        viewModel.currentVideo = video
        viewModel.currentTime = 123
        viewModel.pendingSeekTarget = 145
        viewModel.isLoading = false
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"]
        )
        var recoveryCount = 0
        viewModel.nativeVP9RecoveryOperation = { recoveredVideo, _ in
            #expect(recoveredVideo.id == video.id)
            recoveryCount += 1
        }

        let item = NativeRecoveryTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainNativeRecoveryTasks()
        item.transition(to: .readyToPlay)
        await drainNativeRecoveryTasks()
        item.transition(to: .failed, error: nativeDecodeError)
        await eventuallyNativeRecovery { recoveryCount == 1 }

        #expect(recoveryCount == 1)
        #expect(viewModel.nativeVP9Rejected)
        #expect(viewModel.savedPositionToRestore == 145)
        #expect(viewModel.pendingSeekTarget == nil)
        finishNativeRecovery(viewModel)
    }

    @Test("a native-ready media-services reset rebuilds and autorecovers")
    func nativeResetRebuildsAndRecovers() async {
        let player = NativeRecoveryTestPlayer()
        let replacement = NativeRecoveryTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        let video = Video(id: "native-reset", title: "Test", channelTitle: "Test")
        viewModel.makeRecoveryPlayer = { replacement }
        viewModel.currentVideo = video
        viewModel.currentTime = 88
        viewModel.isLoading = false
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"]
        )
        var recoveryCount = 0
        viewModel.nativeVP9RecoveryOperation = { recoveredVideo, _ in
            #expect(recoveredVideo.id == video.id)
            #expect(viewModel.player === replacement)
            recoveryCount += 1
        }

        let item = NativeRecoveryTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainNativeRecoveryTasks()
        item.transition(to: .readyToPlay)
        await drainNativeRecoveryTasks()
        item.transition(to: .failed, error: nativeResetError)
        await eventuallyNativeRecovery { recoveryCount == 1 }

        #expect(recoveryCount == 1)
        #expect(viewModel.nativeVP9Rejected)
        #expect(viewModel.savedPositionToRestore == 88)
        #expect(player.currentItem == nil)
        finishNativeRecovery(viewModel)
    }

    @Test("a native VP9 failure before readiness stays with the initial fallback")
    func preReadyFailureDoesNotAutorecover() async {
        let player = NativeRecoveryTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentVideo = Video(id: "native-pre-ready", title: "Test", channelTitle: "Test")
        viewModel.isLoading = true
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"]
        )
        var recoveryCount = 0
        viewModel.nativeVP9RecoveryOperation = { _, _ in recoveryCount += 1 }

        let item = NativeRecoveryTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainNativeRecoveryTasks()
        item.transition(to: .failed, error: nativeDecodeError)
        await drainNativeRecoveryTasks()

        #expect(recoveryCount == 0)
        #expect(!viewModel.nativeVP9Rejected)
        finishNativeRecovery(viewModel)
    }

    @Test("a stale old item cannot trigger native VP9 recovery")
    func staleItemDoesNotRecover() async {
        let player = NativeRecoveryTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentVideo = Video(id: "native-stale", title: "Test", channelTitle: "Test")
        viewModel.isLoading = false
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"]
        )
        var recoveryCount = 0
        viewModel.nativeVP9RecoveryOperation = { _, _ in recoveryCount += 1 }

        let oldItem = NativeRecoveryTestItem(url: URL(fileURLWithPath: "/dev/null"))
        let newItem = NativeRecoveryTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: oldItem)
        await drainNativeRecoveryTasks()
        oldItem.transition(to: .readyToPlay)
        await drainNativeRecoveryTasks()
        player.replaceCurrentItem(with: newItem)
        await drainNativeRecoveryTasks()
        oldItem.transition(to: .failed, error: nativeDecodeError)
        await drainNativeRecoveryTasks()

        #expect(recoveryCount == 0)
        #expect(!viewModel.nativeVP9Rejected)
        finishNativeRecovery(viewModel)
    }

    @Test("stop suppresses a queued native VP9 recovery callback")
    func stopSuppressesQueuedRecovery() async {
        let player = NativeRecoveryTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentVideo = Video(id: "native-stop", title: "Test", channelTitle: "Test")
        viewModel.isLoading = false
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"]
        )
        var recoveryCount = 0
        viewModel.nativeVP9RecoveryOperation = { _, _ in recoveryCount += 1 }

        let item = NativeRecoveryTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainNativeRecoveryTasks()
        item.transition(to: .readyToPlay)
        await drainNativeRecoveryTasks()
        item.transition(to: .failed, error: nativeDecodeError)
        viewModel.stop()
        await drainNativeRecoveryTasks()

        #expect(recoveryCount == 0)
        #expect(!viewModel.nativeVP9Rejected)
        finishNativeRecovery(viewModel)
    }

    @Test("switching videos cancels a queued native VP9 recovery")
    func newVideoCancelsQueuedRecovery() async {
        let player = NativeRecoveryTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        let oldVideo = Video(id: "native-old", title: "Old", channelTitle: "Test")
        let newVideo = Video(id: "native-new", title: "New", channelTitle: "Test")
        viewModel.currentVideo = oldVideo
        viewModel.isLoading = false
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"]
        )
        var recoveryCount = 0
        viewModel.nativeVP9RecoveryOperation = { _, _ in recoveryCount += 1 }
        viewModel.loadVideoOperation = { _ in }

        let item = NativeRecoveryTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainNativeRecoveryTasks()
        item.transition(to: .readyToPlay)
        await drainNativeRecoveryTasks()
        item.transition(to: .failed, error: nativeDecodeError)
        viewModel.load(video: newVideo)
        await drainNativeRecoveryTasks()

        #expect(recoveryCount == 0)
        #expect(viewModel.currentVideo?.id == newVideo.id)
        finishNativeRecovery(viewModel)
    }
}

private let nativeDecodeError = NSError(domain: AVFoundationErrorDomain, code: -11828)
private let nativeResetError = NSError(domain: AVFoundationErrorDomain, code: -11819)

@MainActor
private func finishNativeRecovery(_ viewModel: PlaybackViewModel) {
    viewModel.currentVideo = nil
    viewModel.stop()
}

@MainActor
private func drainNativeRecoveryTasks() async {
    for _ in 0..<100 { await Task.yield() }
}

@MainActor
private func eventuallyNativeRecovery(_ predicate: () -> Bool) async {
    for _ in 0..<1_000 {
        if predicate() { return }
        await Task.yield()
    }
}

private final class NativeRecoveryTestPlayer: AVPlayer {
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

private final class NativeRecoveryTestItem: AVPlayerItem {
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
