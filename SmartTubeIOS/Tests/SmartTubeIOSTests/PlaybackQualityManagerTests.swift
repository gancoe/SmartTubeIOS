import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private final class CapturingPlayer: PlayerItemSwappable {
    private var storedRate: Float = 0
    private(set) var replacementItems: [AVPlayerItem] = []
    private(set) var replacementCallCount = 0
    private let replacementEvents: AsyncStream<Void>
    private let replacementContinuation: AsyncStream<Void>.Continuation
    let avPlayer: AVPlayer?

    var rate: Float {
        get { avPlayer?.rate ?? storedRate }
        set {
            storedRate = newValue
            avPlayer?.rate = newValue
        }
    }

    init(avPlayer: AVPlayer? = nil) {
        (replacementEvents, replacementContinuation) = AsyncStream.makeStream(
            of: Void.self, bufferingPolicy: .bufferingNewest(1)
        )
        self.avPlayer = avPlayer
        avPlayer?.isMuted = true
    }

    func replaceCurrentItem(with item: AVPlayerItem?) {
        replacementCallCount += 1
        if let item {
            replacementItems.append(item)
        }
        replacementContinuation.yield(())
        avPlayer?.replaceCurrentItem(with: item)
    }

    @MainActor
    func waitForReplacement() async {
        if !replacementItems.isEmpty { return }
        var iterator = replacementEvents.makeAsyncIterator()
        _ = await iterator.next()
    }
}

@MainActor
private final class QualityTestDelegate: QualityContext, QualityEventHandler {
    var playerInfo: PlayerInfo?
    var settings = AppSettings()
    var currentVideo: Video?
    var currentTime: TimeInterval = 0
    var toastMessage: String?
    var isSwappingItem = false
    var isQualityChangePending = false
    private let terminalEvents: AsyncStream<Void>
    private let terminalContinuation: AsyncStream<Void>.Continuation
    private(set) var readyItem: AVPlayerItem?
    private(set) var readySeekTo: TimeInterval?
    private(set) var didFail = false

    init(playerInfo: PlayerInfo) {
        (terminalEvents, terminalContinuation) = AsyncStream.makeStream(
            of: Void.self, bufferingPolicy: .bufferingNewest(1)
        )
        self.playerInfo = playerInfo
    }

    func qualityItemDidBecomeReady(_ item: AVPlayerItem, seekTo: TimeInterval) {
        readyItem = item
        readySeekTo = seekTo
        terminalContinuation.yield(())
    }

    func qualityItemDidFail(
        error: Error?, quality: AppSettings.VideoQuality, hasAppliedH264Cap: Bool
    ) {
        didFail = true
        terminalContinuation.yield(())
    }

    func qualitySelectDASHFormat(videoURL: URL, audioURL: URL, seekTo: TimeInterval) {}

    func waitForTerminalEvent() async {
        if readyItem != nil || didFail { return }
        var iterator = terminalEvents.makeAsyncIterator()
        _ = await iterator.next()
    }
}

@Suite("Playback quality manager regressions", .timeLimit(.minutes(1)))
struct PlaybackQualityManagerTests {

    private func makePlayerInfo(hlsURL: URL) -> PlayerInfo {
        PlayerInfo(
            video: Video(id: "quality-test", title: "Quality test", channelTitle: "Test"),
            formats: [],
            hlsURL: hlsURL,
            dashURL: nil,
            captionTracks: [],
            trackingURLs: nil,
            endCards: []
        )
    }

    @MainActor
    private func makeManager(
        hlsURL: URL, player: CapturingPlayer = CapturingPlayer()
    ) -> (PlaybackQualityManager, QualityTestDelegate) {
        let manager = PlaybackQualityManager(player: player)
        let delegate = QualityTestDelegate(playerInfo: makePlayerInfo(hlsURL: hlsURL))
        manager.delegate = delegate
        return (manager, delegate)
    }

    private func capturedItem(
        _ player: CapturingPlayer, sourceLocation: SourceLocation = #_sourceLocation
    ) -> AVPlayerItem? {
        guard player.replacementCallCount == 1, player.replacementItems.count == 1 else {
            Issue.record(
                "Expected one replacement call with an item, got \(player.replacementCallCount) calls and \(player.replacementItems.count) items",
                sourceLocation: sourceLocation
            )
            return nil
        }
        return player.replacementItems[0]
    }

    @Test("HLS quality reload captures the master item with the requested cap and switch buffer")
    @MainActor
    func hlsReloadUsesRequestedCapAndPlaylistURL() async {
        let hlsURL = URL(string: "https://manifest.example.test/master.m3u8")!
        let player = CapturingPlayer()
        let (manager, delegate) = makeManager(hlsURL: hlsURL, player: player)
        defer {
            manager.cancel()
            withExtendedLifetime(delegate) {}
        }

        await manager.reloadHLSItem(seekTo: 12, quality: .q720)

        guard let item = capturedItem(player) else { return }
        let asset = item.asset as? AVURLAsset
        #expect(asset?.url == hlsURL)
        #expect(item.preferredMaximumResolution == CGSize(width: 2880, height: 720))
        #expect(item.preferredPeakBitRate == 8_000_000)
        #expect(item.preferredForwardBufferDuration == 2)
    }

    @Test("HLS quality reload applies the lower native source cap")
    @MainActor
    func hlsReloadCombinesRequestedAndNativeCaps() async {
        let hlsURL = URL(string: "https://manifest.example.test/master.m3u8")!
        let player = CapturingPlayer()
        let (manager, delegate) = makeManager(hlsURL: hlsURL, player: player)
        manager.configureHLSPlayback(
            userAgent: "quality-test", maximumHeight: 480, allowedVideoCodecs: ["avc1"]
        )
        defer {
            manager.cancel()
            withExtendedLifetime(delegate) {}
        }

        await manager.reloadHLSItem(seekTo: 0, quality: .q1080)

        guard let item = capturedItem(player) else { return }
        let asset = item.asset as? AVURLAsset
        #expect(asset?.url.scheme == "ytwebhls")
        #expect(asset?.url.realURL == hlsURL)
        #expect(item.preferredMaximumResolution == CGSize(width: 1920, height: 480))
        #expect(item.preferredPeakBitRate == 4_000_000)
    }

    @Test("Auto HLS reload removes quality constraints while preserving the master item")
    @MainActor
    func hlsReloadAutoLeavesABRUnconstrained() async {
        let hlsURL = URL(string: "https://manifest.example.test/master.m3u8")!
        let player = CapturingPlayer()
        let (manager, delegate) = makeManager(hlsURL: hlsURL, player: player)
        defer {
            manager.cancel()
            withExtendedLifetime(delegate) {}
        }

        await manager.reloadHLSItem(seekTo: 0, quality: .auto)

        guard let item = capturedItem(player) else { return }
        #expect((item.asset as? AVURLAsset)?.url == hlsURL)
        #expect(item.preferredMaximumResolution == .zero)
        #expect(item.preferredPeakBitRate == 0)
    }

    @Test("Auto HLS reload retains the native source cap")
    @MainActor
    func hlsReloadAutoRetainsNativeCap() async {
        let hlsURL = URL(string: "https://manifest.example.test/master.m3u8")!
        let player = CapturingPlayer()
        let (manager, delegate) = makeManager(hlsURL: hlsURL, player: player)
        manager.configureHLSPlayback(
            userAgent: "quality-test", maximumHeight: 480, allowedVideoCodecs: ["avc1"]
        )
        defer {
            manager.cancel()
            withExtendedLifetime(delegate) {}
        }

        await manager.reloadHLSItem(seekTo: 0, quality: .auto)

        guard let item = capturedItem(player) else { return }
        let asset = item.asset as? AVURLAsset
        #expect(asset?.url.scheme == "ytwebhls")
        #expect(asset?.url.realURL == hlsURL)
        #expect(item.preferredMaximumResolution == CGSize(width: 1920, height: 480))
        #expect(item.preferredPeakBitRate == 4_000_000)
    }

    @Test("Selecting a format runs the manager's HLS replacement path")
    @MainActor
    func selectFormatUsesHLSReloadPath() async {
        let hlsURL = URL(string: "https://manifest.example.test/master.m3u8")!
        let player = CapturingPlayer()
        let (manager, delegate) = makeManager(hlsURL: hlsURL, player: player)
        delegate.currentTime = 9
        defer { manager.cancel() }

        manager.selectFormat(
            VideoFormat(
                label: "720p", width: 1280, height: 720, fps: 30,
                mimeType: "video/mp4; codecs=\"avc1.64001f\""
            )
        )
        await player.waitForReplacement()

        guard let item = capturedItem(player) else { return }
        #expect(manager.selectedFormat?.height == 720)
        #expect((item.asset as? AVURLAsset)?.url == hlsURL)
        #expect(item.preferredMaximumResolution == CGSize(width: 2880, height: 720))
        #expect(delegate.isQualityChangePending)
    }

    @Test("H264 capped reload captures the 1080p item cap")
    @MainActor
    func h264CappedReloadUses1080pCap() async {
        let hlsURL = URL(string: "https://manifest.example.test/master.m3u8")!
        let player = CapturingPlayer()
        let (manager, delegate) = makeManager(hlsURL: hlsURL, player: player)
        defer {
            manager.cancel()
            withExtendedLifetime(delegate) {}
        }

        await manager.reloadHLSItemH264Capped(seekTo: 4)

        guard let item = capturedItem(player) else { return }
        #expect((item.asset as? AVURLAsset)?.url == hlsURL)
        #expect(item.preferredMaximumResolution == CGSize(width: 1920, height: 1080))
        #expect(item.preferredPeakBitRate == 15_000_000)
    }

    @Test("HLS reload restores playback rate after a real local item becomes ready")
    @MainActor
    func hlsReloadSetsRateAfterReady() async throws {
        let url = try makeSilentWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let avPlayer = AVPlayer()
        let player = CapturingPlayer(avPlayer: avPlayer)
        let (manager, delegate) = makeManager(hlsURL: url, player: player)
        delegate.settings.playbackSpeed = 1.5
        defer {
            manager.cancel()
            avPlayer.replaceCurrentItem(with: nil)
        }

        await manager.reloadHLSItem(seekTo: 23, quality: .auto)
        #expect(player.rate == 0)
        avPlayer.play()
        await delegate.waitForTerminalEvent()

        #expect(delegate.didFail == false)
        #expect(delegate.readyItem != nil)
        #expect(delegate.readyItem === player.replacementItems.first)
        #expect(delegate.readySeekTo == 23)
        #expect(player.rate == 1.5)
    }

    private func makeSilentWAV() throws -> URL {
        let sampleRate: UInt32 = 8_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let frameCount: UInt32 = sampleRate
        let dataSize = frameCount * UInt32(channels) * UInt32(bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian, Array.init))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        data.append(contentsOf: Array("data".utf8))
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
        data.append(contentsOf: repeatElement(0, count: Int(dataSize)))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("smarttube-quality-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }
}
