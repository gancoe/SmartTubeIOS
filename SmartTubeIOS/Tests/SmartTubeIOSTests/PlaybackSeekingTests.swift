import AVFoundation
import CoreMedia
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Native AVPlayer seeking")
@MainActor
struct PlaybackSeekingTests {

    @Test("rapid relative seeks accumulate from the latest requested position")
    func rapidRelativeSeeksAccumulate() async {
        let player = ControlledAVPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentTime = 100
        viewModel.duration = 200

        viewModel.seekRelative(seconds: 10)
        viewModel.seekRelative(seconds: 10)

        #expect(player.requestedTimes == [110, 120])

        player.completeSeek(at: 1, finished: true)
        #expect(await waitUntil { viewModel.currentTime == 120 })
        #expect(viewModel.currentTime == 120)
    }

    @Test("a cancelled stale seek completion cannot overwrite the latest position")
    func staleCompletionDoesNotOverwriteLatestPosition() async {
        let player = ControlledAVPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentTime = 50

        viewModel.seek(to: 80)
        viewModel.seek(to: 120)

        player.completeSeek(at: 1, finished: true)
        #expect(await waitUntil { viewModel.currentTime == 120 })
        let completedBeforeStaleCallback = player.completionCallCount
        player.completeSeek(at: 0, finished: false)
        #expect(await waitUntil { player.completionCallCount == completedBeforeStaleCallback + 1 })
        for _ in 0..<20 { await Task.yield() }

        #expect(viewModel.currentTime == 120)
    }

    @Test("an unsuccessful latest seek leaves the current position unchanged")
    func unsuccessfulLatestSeekLeavesPositionUnchanged() async {
        let player = ControlledAVPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentTime = 50

        viewModel.seek(to: 80)
        player.completeSeek(at: 0, finished: false)
        #expect(await waitUntil { player.completionCallCount == 1 })
        for _ in 0..<20 { await Task.yield() }

        #expect(viewModel.currentTime == 50)
    }

    @Test("loading another video clears a pending relative seek target")
    func loadingAnotherVideoClearsPendingSeekTarget() {
        let player = ControlledAVPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentTime = 100
        viewModel.duration = 200

        viewModel.seekRelative(seconds: 10)
        viewModel.load(video: Video(id: "next-video", title: "Next Video", channelTitle: "Channel"))
        viewModel.seekRelative(seconds: 10)
        viewModel.stop()

        #expect(player.requestedTimes == [110, 10])
    }

    @Test("stopping playback clears a pending relative seek target")
    func stoppingClearsPendingSeekTarget() {
        let player = ControlledAVPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentTime = 100
        viewModel.duration = 200

        viewModel.seekRelative(seconds: 10)
        viewModel.stop()
        viewModel.seekRelative(seconds: 10)

        #expect(player.requestedTimes == [110, 110])
    }

    @Test("relative seeks clamp to a known duration and preserve play state")
    func knownDurationClampsAndPlayStateIsPreserved() {
        let player = ControlledAVPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentTime = 95
        viewModel.duration = 100
        viewModel.isPlaying = true

        viewModel.seekRelative(seconds: 20)

        #expect(player.requestedTimes == [100])
        #expect(viewModel.isPlaying)
    }

    @Test("relative seeks allow an upper target while duration is unknown")
    func unknownDurationAllowsUpperTarget() {
        let player = ControlledAVPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.currentTime = 100
        viewModel.duration = 0
        viewModel.isPlaying = false

        viewModel.seekRelative(seconds: 30)

        #expect(player.requestedTimes == [130])
        #expect(viewModel.isPlaying == false)
    }
}

@MainActor
private func waitUntil(
    _ predicate: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<20 {
        if predicate() { return true }
        await Task.yield()
    }
    return predicate()
}

private final class ControlledAVPlayer: AVPlayer {
    nonisolated(unsafe) private(set) var requestedTimes: [TimeInterval] = []
    nonisolated(unsafe) private var completions: [(@Sendable (Bool) -> Void)?] = []
    nonisolated(unsafe) private(set) var completionCallCount = 0

    override func seek(
        to time: CMTime,
        toleranceBefore: CMTime,
        toleranceAfter: CMTime,
        completionHandler: @escaping @Sendable (Bool) -> Void
    ) {
        requestedTimes.append(time.seconds)
        completions.append(completionHandler)
    }

    func completeSeek(at index: Int, finished: Bool) {
        completionCallCount += 1
        completions[index]?(finished)
        completions[index] = nil
    }
}
