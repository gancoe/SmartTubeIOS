import AVFoundation
import CoreMedia
import Testing

@testable import SmartTubeIOS

@Suite("Playback diagnostics")
@MainActor
struct PlaybackDiagnosticsTests {

    @Test("snapshot reports actual waiting state, rate, item status, and buffer flags")
    func reportsActualPlayerState() {
        let item = ControlledAVPlayerItem()
        item.currentTimeValue = CMTime(seconds: 12, preferredTimescale: 600)
        item.statusValue = .readyToPlay
        item.loadedTimeRangesValue = [
            NSValue(
                timeRange: CMTimeRange(
                    start: CMTime(seconds: 8, preferredTimescale: 600),
                    duration: CMTime(seconds: 20, preferredTimescale: 600)))
        ]
        item.playbackBufferEmptyValue = false
        item.playbackLikelyToKeepUpValue = true

        let player = ControlledAVPlayer(item: item)
        player.timeControlStatusValue = .waitingToPlayAtSpecifiedRate
        player.rateValue = 1.25
        player.reasonForWaitingToPlayValue = .toMinimizeStalls

        let viewModel = PlaybackViewModel(player: player)
        viewModel.updateStatsSnapshot()

        #expect(viewModel.statsSnapshot.playerTimeControlStatus == "waiting")
        #expect(viewModel.statsSnapshot.playerRate == 1.25)
        #expect(viewModel.statsSnapshot.waitingReason == "toMinimizeStalls")
        #expect(viewModel.statsSnapshot.itemStatus == "ready")
        #expect(viewModel.statsSnapshot.bufferAheadSeconds == 16)
        #expect(viewModel.statsSnapshot.playbackBufferEmpty == false)
        #expect(viewModel.statsSnapshot.playbackLikelyToKeepUp == true)
    }

    @Test("buffer snapshot follows only the contiguous valid range from item time")
    func reportsContiguousBufferBoundaries() {
        let item = ControlledAVPlayerItem()
        item.currentTimeValue = CMTime(seconds: 10, preferredTimescale: 600)
        item.loadedTimeRangesValue = [
            NSValue(
                timeRange: CMTimeRange(
                    start: CMTime(seconds: 0, preferredTimescale: 600),
                    duration: CMTime(seconds: 5, preferredTimescale: 600))),
            NSValue(
                timeRange: CMTimeRange(
                    start: CMTime(seconds: 20, preferredTimescale: 600),
                    duration: CMTime(seconds: 5, preferredTimescale: 600))),
            NSValue(
                timeRange: CMTimeRange(
                    start: CMTime(seconds: 9, preferredTimescale: 600),
                    duration: CMTime(seconds: 4, preferredTimescale: 600))),
            NSValue(
                timeRange: CMTimeRange(
                    start: CMTime(seconds: 13, preferredTimescale: 600),
                    duration: CMTime(seconds: 3, preferredTimescale: 600))),
            NSValue(timeRange: CMTimeRange(start: .invalid, duration: .invalid)),
        ]

        let viewModel = PlaybackViewModel(player: ControlledAVPlayer(item: item))
        viewModel.updateStatsSnapshot()

        #expect(viewModel.statsSnapshot.bufferAheadSeconds == 6)
    }

    @Test("missing current item reports unknown diagnostics")
    func reportsMissingCurrentItem() {
        let viewModel = PlaybackViewModel(player: ControlledAVPlayer(item: nil))
        viewModel.updateStatsSnapshot()

        #expect(viewModel.statsSnapshot.playerTimeControlStatus == "unknown")
        #expect(viewModel.statsSnapshot.playerRate == nil)
        #expect(viewModel.statsSnapshot.itemStatus == "unknown")
        #expect(viewModel.statsSnapshot.bufferAheadSeconds == nil)
        #expect(viewModel.statsSnapshot.playbackBufferEmpty == nil)
        #expect(viewModel.statsSnapshot.playbackLikelyToKeepUp == nil)
    }

    @Test("error diagnostics retain only domain and code")
    func sanitizesErrorDiagnostics() {
        let item = ControlledAVPlayerItem()
        let privateToken = "secret-token"
        let privateURL = "https://cdn.example/video.m3u8?sig=\(privateToken)"
        item.errorValue = NSError(
            domain: "AVFoundationErrorDomain",
            code: -11800,
            userInfo: [
                NSLocalizedDescriptionKey: "failed \(privateToken)",
                NSURLErrorFailingURLStringErrorKey: privateURL,
            ])

        let player = ControlledAVPlayer(item: item)
        player.errorValue = NSError(
            domain: "AVPlayerDomain",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: privateURL])

        let viewModel = PlaybackViewModel(player: player)
        viewModel.updateStatsSnapshot()

        #expect(viewModel.statsSnapshot.itemError == "AVFoundationErrorDomain#-11800")
        #expect(viewModel.statsSnapshot.playerError == "AVPlayerDomain#-2")
        #expect(!viewModel.statsSnapshot.itemError.contains(privateToken))
        #expect(!viewModel.statsSnapshot.playerError.contains(privateToken))
        #expect(!viewModel.statsSnapshot.itemError.contains("https://"))
        #expect(!viewModel.statsSnapshot.playerError.contains("?"))
    }

    @Test("refresh reads current player and item state after playback stops")
    func refreshReadsFreshFailureState() {
        let item = ControlledAVPlayerItem()
        item.statusValue = .readyToPlay
        item.currentTimeValue = CMTime(seconds: 20, preferredTimescale: 600)
        item.loadedTimeRangesValue = [
            NSValue(
                timeRange: CMTimeRange(
                    start: CMTime(seconds: 20, preferredTimescale: 600),
                    duration: CMTime(seconds: 10, preferredTimescale: 600)))
        ]
        let player = ControlledAVPlayer(item: item)
        player.timeControlStatusValue = .waitingToPlayAtSpecifiedRate
        player.rateValue = 1

        let viewModel = PlaybackViewModel(player: player)
        viewModel.updateStatsSnapshot()
        #expect(viewModel.statsSnapshot.itemStatus == "ready")
        #expect(viewModel.statsSnapshot.bufferAheadSeconds == 10)

        item.statusValue = .failed
        item.errorValue = NSError(domain: "AVFoundationErrorDomain", code: -11819)
        item.loadedTimeRangesValue = [
            NSValue(
                timeRange: CMTimeRange(
                    start: CMTime(seconds: 40, preferredTimescale: 600),
                    duration: CMTime(seconds: 5, preferredTimescale: 600)))
        ]
        item.playbackBufferEmptyValue = true
        item.playbackLikelyToKeepUpValue = false
        player.timeControlStatusValue = .paused
        player.rateValue = 0

        viewModel.updateStatsSnapshot()

        #expect(viewModel.statsSnapshot.playerTimeControlStatus == "paused")
        #expect(viewModel.statsSnapshot.playerRate == 0)
        #expect(viewModel.statsSnapshot.itemStatus == "failed")
        #expect(viewModel.statsSnapshot.bufferAheadSeconds == 0)
        #expect(viewModel.statsSnapshot.playbackBufferEmpty == true)
        #expect(viewModel.statsSnapshot.playbackLikelyToKeepUp == false)
        #expect(viewModel.statsSnapshot.itemError == "AVFoundationErrorDomain#-11819")
    }
}

@MainActor
private final class ControlledAVPlayer: AVPlayer {
    let controlledItem: ControlledAVPlayerItem?
    nonisolated(unsafe) var timeControlStatusValue: AVPlayer.TimeControlStatus = .paused
    nonisolated(unsafe) var rateValue: Float = 0
    nonisolated(unsafe) var reasonForWaitingToPlayValue: AVPlayer.WaitingReason?
    nonisolated(unsafe) var errorValue: Error?

    init(item: ControlledAVPlayerItem?) {
        controlledItem = item
        super.init()
    }

    override var currentItem: AVPlayerItem? { controlledItem }
    override var timeControlStatus: AVPlayer.TimeControlStatus { timeControlStatusValue }
    override var rate: Float {
        get { rateValue }
        set { rateValue = newValue }
    }
    override var reasonForWaitingToPlay: AVPlayer.WaitingReason? { reasonForWaitingToPlayValue }
    override var error: Error? { errorValue }
}

@MainActor
private final class ControlledAVPlayerItem: AVPlayerItem {
    nonisolated(unsafe) var currentTimeValue = CMTime.invalid
    nonisolated(unsafe) var statusValue: AVPlayerItem.Status = .unknown
    nonisolated(unsafe) var loadedTimeRangesValue: [NSValue] = []
    nonisolated(unsafe) var playbackBufferEmptyValue = false
    nonisolated(unsafe) var playbackLikelyToKeepUpValue = false
    nonisolated(unsafe) var errorValue: Error?

    init() {
        super.init(
            asset: AVURLAsset(url: URL(fileURLWithPath: "/dev/null")),
            automaticallyLoadedAssetKeys: nil)
    }

    override func currentTime() -> CMTime { currentTimeValue }
    override var status: AVPlayerItem.Status { statusValue }
    override var loadedTimeRanges: [NSValue] { loadedTimeRangesValue }
    override var isPlaybackBufferEmpty: Bool { playbackBufferEmptyValue }
    override var isPlaybackLikelyToKeepUp: Bool { playbackLikelyToKeepUpValue }
    override var error: Error? { errorValue }
}
