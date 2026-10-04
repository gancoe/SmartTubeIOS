import AVFoundation
import SmartTubeIOSCore
import Testing

@testable import SmartTubeIOS

@Suite("Playback recovery transitions")
@MainActor
struct PlaybackRecoveryTransitionTests {
    @Test("a native-ready item keeps its recovery classification after a quality preference change")
    func nativeReadyItemKeepsNativeClassificationAfterPreferenceChange() async {
        let player = RecoveryTransitionTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.settings.historyState = .disabled
        viewModel.currentVideo = Video(id: "native-to-h264", title: "Test", channelTitle: "Test")
        viewModel.isLoading = false
        defer { finishRecoveryTransition(viewModel) }
        var recoveryCount = 0
        viewModel.nativeVP9RecoveryOperation = { _, _ in recoveryCount += 1 }
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])

        let item = RecoveryTransitionTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainRecoveryTransitionTasks()
        item.transition(to: .readyToPlay)
        await drainRecoveryTransitionTasks()

        viewModel.settings.preferredQuality = .q1080
        item.transition(to: .failed, error: nativeDecodeError)
        #expect(await eventuallyRecoveryTransition { recoveryCount == 1 })

        #expect(recoveryCount == 1)
        #expect(viewModel.nativeVP9Rejected)
    }

    @Test("an H264 item stays non-native after a quality preference change")
    func h264ItemStaysNonNativeAfterPreferenceChange() async {
        let player = RecoveryTransitionTestPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.settings.historyState = .disabled
        viewModel.currentVideo = Video(id: "h264-to-native", title: "Test", channelTitle: "Test")
        viewModel.isLoading = false
        defer { finishRecoveryTransition(viewModel) }
        var recoveryCount = 0
        viewModel.nativeVP9RecoveryOperation = { _, _ in recoveryCount += 1 }
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 1080, allowedVideoCodecs: ["avc1"])

        let item = RecoveryTransitionTestItem(url: URL(fileURLWithPath: "/dev/null"))
        player.replaceCurrentItem(with: item)
        await drainRecoveryTransitionTasks()
        item.transition(to: .readyToPlay)
        await drainRecoveryTransitionTasks()

        viewModel.settings.preferredQuality = .q2160
        item.transition(to: .failed, error: mediaServicesResetError)
        #expect(await eventuallyRecoveryTransition { viewModel.error != nil })

        #expect(recoveryCount == 0)
        #expect(!viewModel.nativeVP9Rejected)
        #expect((viewModel.error as NSError?)?.code == -11819)
    }

    @Test("a recovered item reopens from injected parked identity and reports a later failure")
    func recoveredItemReopensFromInjectedParkedIdentity() async {
        let fixture = await recoveredFixture()
        defer { finishRecoveryTransition(fixture.viewModel) }
        parkForRecoveryReopen(fixture.viewModel, video: fixture.video)

        fixture.viewModel.load(video: fixture.video)
        await drainRecoveryTransitionTasks()
        #expect(fixture.viewModel.player === fixture.player)
        #expect(fixture.viewModel.player.currentItem === fixture.recoveredItem)
        #expect(fixture.recoveryCount() == 1)
        fixture.recoveredItem.transition(to: .failed, error: mediaServicesResetError)

        #expect(await eventuallyRecoveryTransition { fixture.viewModel.error != nil })
        #expect(!fixture.viewModel.isPlaying)
        #expect(fixture.recoveryCount() == 1)
    }
}

@MainActor
private final class RecoveryTransitionFixture {
    let player: RecoveryTransitionTestPlayer
    let viewModel: PlaybackViewModel
    let video: Video
    let recoveredItem: RecoveryTransitionTestItem
    let recoveryCount: () -> Int

    init(
        player: RecoveryTransitionTestPlayer,
        viewModel: PlaybackViewModel,
        video: Video,
        recoveredItem: RecoveryTransitionTestItem,
        recoveryCount: @escaping () -> Int
    ) {
        self.player = player
        self.viewModel = viewModel
        self.video = video
        self.recoveredItem = recoveredItem
        self.recoveryCount = recoveryCount
    }
}

@MainActor
private func recoveredFixture() async -> RecoveryTransitionFixture {
    let player = RecoveryTransitionTestPlayer()
    let viewModel = PlaybackViewModel(player: player)
    viewModel.settings.historyState = .disabled
    viewModel.settings.autoplayEnabled = false
    let video = Video(id: "recovered-parked", title: "Test", channelTitle: "Test")
    viewModel.currentVideo = video
    viewModel.isLoading = false
    viewModel.qualityManager.configureHLSPlayback(
        userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
    let recoveredItem = RecoveryTransitionTestItem(url: URL(fileURLWithPath: "/dev/null"))
    var recoveryCount = 0
    viewModel.nativeVP9RecoveryOperation = { [weak viewModel] _, _ in
        recoveryCount += 1
        viewModel?.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 1080, allowedVideoCodecs: ["avc1"])
        player.replaceCurrentItem(with: recoveredItem)
        recoveredItem.transition(to: .readyToPlay)
        viewModel?.isLoading = false
    }

    let failedItem = RecoveryTransitionTestItem(url: URL(fileURLWithPath: "/dev/null"))
    player.replaceCurrentItem(with: failedItem)
    await drainRecoveryTransitionTasks()
    failedItem.transition(to: .readyToPlay)
    await drainRecoveryTransitionTasks()
    failedItem.transition(to: .failed, error: nativeDecodeError)
    #expect(await eventuallyRecoveryTransition { player.currentItem === recoveredItem })
    await drainRecoveryTransitionTasks()

    return RecoveryTransitionFixture(
        player: player, viewModel: viewModel, video: video, recoveredItem: recoveredItem,
        recoveryCount: { recoveryCount })
}

private let nativeDecodeError = NSError(domain: AVFoundationErrorDomain, code: -11828)
private let mediaServicesResetError = NSError(domain: AVFoundationErrorDomain, code: -11819)

@MainActor
private func finishRecoveryTransition(_ viewModel: PlaybackViewModel) {
    viewModel.currentVideo = nil
    viewModel.stop()
}

@MainActor
private func parkForRecoveryReopen(_ viewModel: PlaybackViewModel, video: Video) {
    viewModel.currentVideo = nil
    viewModel.stop()
    viewModel.currentVideo = video
    viewModel.parkedVideoId = video.id
}

@MainActor
private func drainRecoveryTransitionTasks() async {
    for _ in 0..<100 { await Task.yield() }
}

@MainActor
private func eventuallyRecoveryTransition(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<1_000 {
        if predicate() { return true }
        await Task.yield()
    }
    return predicate()
}

private final class RecoveryTransitionTestPlayer: AVPlayer {
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

private final class RecoveryTransitionTestItem: AVPlayerItem {
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
