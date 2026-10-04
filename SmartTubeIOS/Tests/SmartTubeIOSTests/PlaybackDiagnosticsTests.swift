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

    @Test("buffer viewing time accounts for accelerated playback without changing the player")
    func reportsBufferAtPlaybackSpeed() {
        let item = ControlledAVPlayerItem()
        item.currentTimeValue = CMTime(seconds: 10, preferredTimescale: 600)
        item.loadedTimeRangesValue = [
            NSValue(
                timeRange: CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    duration: CMTime(seconds: 60, preferredTimescale: 600)))
        ]
        let player = ControlledAVPlayer(item: item)
        player.rateValue = 1.5
        let viewModel = PlaybackViewModel(player: player)

        viewModel.updateStatsSnapshot()
        #expect(viewModel.statsSnapshot.bufferViewingSeconds == 40)
        #expect(player.rate == 1.5)

        player.rateValue = 2
        viewModel.updateStatsSnapshot()
        #expect(viewModel.statsSnapshot.bufferViewingSeconds == 30)
        #expect(player.rate == 2)

        player.rateValue = 0
        viewModel.updateStatsSnapshot()
        #expect(viewModel.statsSnapshot.bufferViewingSeconds == nil)
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

    @Test("delivery comments preserve known timeout details without exposing request credentials")
    func reportsSafeDeliveryComment() {
        #expect(PlaybackViewModel.errorLogCommentSummary(nil) == "—")
        #expect(
            PlaybackViewModel.errorLogCommentSummary("Media file not received in 15s")
                == "Media file not received in 15s")
        #expect(
            PlaybackViewModel.errorLogCommentSummary("Media file not received in 6.5s")
                == "Media file not received in 6.5s")
        #expect(
            PlaybackViewModel.errorLogCommentSummary("https://cdn.example/video?sig=secret")
                == "Details redacted")
        #expect(
            PlaybackViewModel.errorLogCommentSummary("Media file not received in 15s\nAuthorization: secret")
                == "Details redacted")
    }

    @Test("no-response timeout comments remain readable without allowing arbitrary error details")
    func reportsSafeNoResponseComment() {
        #expect(
            PlaybackViewModel.errorLogCommentSummary("No response for media file in 9.9767s")
                == "No response for media file in 9.9767s")
        #expect(
            PlaybackViewModel.errorLogCommentSummary("No response for media file in 10s")
                == "No response for media file in 10s")
        #expect(
            PlaybackViewModel.errorLogCommentSummary(
                "No response for media file in 10s https://cdn.example/?sig=secret")
                == "Details redacted")
        #expect(
            PlaybackViewModel.errorLogCommentSummary("No response for media file in 10s\nCookie: secret")
                == "Details redacted")
    }

    @Test("error URL summaries distinguish media hints from playlist and caption URLs without credentials")
    func reportsSafeErrorResource() {
        #expect(PlaybackViewModel.errorResourceSummary(nil) == "unknown")
        #expect(PlaybackViewModel.errorResourceSummary("invalid resource") == "unknown")
        #expect(
            PlaybackViewModel.errorResourceSummary("https://cdn.example/playlist/index.m3u8?sig=secret")
                == "playlist URL · HTTPS")
        #expect(
            PlaybackViewModel.errorResourceSummary("ytwebhls://cdn.example/index.m3u8?sig=secret")
                == "playlist URL · playlist proxy")
        #expect(
            PlaybackViewModel.errorResourceSummary(
                "https://cdn.example/mime/video%2Fwebm/itag/617/file/seg.ts?sig=secret")
                == "video URL (MIME hint) · HTTPS · itag=617")
        #expect(
            PlaybackViewModel.errorResourceSummary(
                "https://cdn.example/videoplayback?mime=audio%2Fmp4&itag=140&sig=secret")
                == "audio URL (MIME hint) · HTTPS · itag=140")
        #expect(
            PlaybackViewModel.errorResourceSummary("https://cdn.example/playlist/index.m3u8/file/seg.ts?sig=secret")
                == "media URL (track unknown) · HTTPS")
        #expect(
            PlaybackViewModel.errorResourceSummary("https://www.youtube.com/api/timedtext?sig=secret")
                == "captions URL · HTTPS")
        #expect(
            PlaybackViewModel.errorResourceSummary("https://cdn.example/?mime=secret&itag=secret&sig=secret")
                == "unknown URL · HTTPS")
    }

    @Test("remote events bind native values and sanitized errors without altering accelerated playback")
    func recordsStructuredNativeValues() {
        let now = Date(timeIntervalSince1970: 1_000)
        var snapshot = StatsForNerdsSnapshot.empty
        snapshot.videoId = "THbBVhNwTFo"
        snapshot.displayResolution = "256x144"
        snapshot.playerRate = 2
        snapshot.bufferAheadSeconds = 60
        snapshot.itemStatus = "ready"
        snapshot.playerTimeControlStatus = "playing"
        snapshot.streamType = "VisionOS/Native4K/HLS"
        snapshot.errorLog = "CoreMediaErrorDomain#-15628"
        snapshot.errorLogDate = now.addingTimeInterval(-11)
        snapshot.errorLogEventCount = 2
        snapshot.errorLogComment = "Details redacted"
        snapshot.errorLogResource = PlaybackViewModel.errorResourceSummary(
            "https://cdn.example/mime/video%2Fwebm/itag/617/file/seg.ts?sig=secret")
        snapshot.downloadedBytes = 1_000
        snapshot.accessLogEventCount = 3
        let event = PlaybackViewModel.deliveryEvent(
            snapshot, advertisedBitrate: 500_000, observedBitrate: 20_000_000, playbackPosition: 123, at: now)
        #expect(event.videoID == "THbBVhNwTFo")
        #expect(event.rate == 2)
        #expect(event.playbackPositionSeconds == 123)
        #expect(event.bufferMediaSeconds == 60)
        #expect(event.bufferViewingSeconds == 30)
        #expect(event.resolution == "256x144")
        #expect(event.errorCode == -15628)
        #expect(event.errorDomain == "CoreMediaErrorDomain")
        #expect(event.errorTimestamp == now.addingTimeInterval(-11))
        #expect(event.timestamp == now)
        #expect(event.errorResource == "video URL (MIME hint) · HTTPS · itag=617")
        #expect(event.advertisedBitrateBps == 500_000)
        #expect(event.observedBitrateBps == 20_000_000)
        #expect(event.downloadedBytes == 1_000)
        #expect(event.accessEventCount == 3)
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

    @Test("a retained error gets older while a subsequent event resets its age")
    func reportsErrorEventAge() {
        let firstEvent = Date(timeIntervalSince1970: 1_000)
        var snapshot = StatsForNerdsSnapshot.empty
        #expect(snapshot.errorLogAgeSeconds(at: firstEvent) == nil)

        snapshot.errorLogDate = firstEvent
        #expect(snapshot.errorLogAgeSeconds(at: firstEvent.addingTimeInterval(60)) == 60)
        #expect(snapshot.errorLogAgeSeconds(at: firstEvent.addingTimeInterval(120)) == 120)

        snapshot.errorLogDate = firstEvent.addingTimeInterval(118)
        #expect(snapshot.errorLogAgeSeconds(at: firstEvent.addingTimeInterval(120)) == 2)
        #expect(snapshot.errorLogAgeSeconds(at: firstEvent) == nil)
    }

    @Test("snapshot observes the installed bitrate limit without modifying playback policy")
    func reportsInstalledBitrateLimit() {
        let item = ControlledAVPlayerItem()
        item.preferredPeakBitRate = 45_000_000
        let viewModel = PlaybackViewModel(player: ControlledAVPlayer(item: item))

        viewModel.updateStatsSnapshot()

        #expect(viewModel.statsSnapshot.peakBitrateLimit == 45_000_000)
        #expect(item.preferredPeakBitRate == 45_000_000)
        #expect(viewModel.statsSnapshot.errorLogEventCount == 0)
        #expect(viewModel.statsSnapshot.errorLogDate == nil)
        #expect(viewModel.statsSnapshot.errorLogComment == "—")
        #expect(viewModel.statsSnapshot.advertisedBitrate == "—")
        #expect(viewModel.statsSnapshot.downloadedBytes == nil)
    }

    @Test("unavailable or invalid advertised bitrate stays unknown")
    func reportsUnknownAdvertisedBitrate() {
        #expect(PlaybackViewModel.deliveryBitrateLabel(nil) == "—")
        #expect(PlaybackViewModel.deliveryBitrateLabel(-1) == "—")
        #expect(PlaybackViewModel.deliveryBitrateLabel(0) == "—")
        #expect(PlaybackViewModel.deliveryBitrateLabel(.infinity) == "—")
        #expect(PlaybackViewModel.deliveryBitrateLabel(.nan) == "—")
        #expect(PlaybackViewModel.deliveryBitrateLabel(Double(Int.max)) == "—")
        #expect(PlaybackViewModel.deliveryBitrateLabel(4_000_000) == "4.0 Mbps")
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
