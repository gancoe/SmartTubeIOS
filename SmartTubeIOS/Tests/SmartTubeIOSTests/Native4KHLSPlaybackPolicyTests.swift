import AVFoundation
import SmartTubeIOSCore
import Testing

@testable import SmartTubeIOS

private actor RampWaitGate {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Error>?

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func wait() async throws {
        started = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        try await withCheckedThrowingContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@Suite("Native 4K HLS policy")
struct Native4KHLSPlaybackPolicyTests {
    private func emptyItem() -> AVPlayerItem {
        AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
    }

    @Test("native 4K route admits VP9 SDR through 2160p")
    func admitsVP9SDR() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/Native4K/HLS", isHLS: true)
        #expect(policy.maximumHeight == 2160)
        #expect(!policy.requiresH264)
        #expect(policy.allowsFormat(height: 2160, mimeType: "video/webm; codecs=\"vp09.00.50.08\""))
        #expect(!policy.allowsFormat(height: 4320, mimeType: "video/webm; codecs=\"vp09.00.50.08\""))
    }

    @Test("native 4K route rejects AV1 and VP9 HDR profiles")
    func rejectsUnverifiedCodecs() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/Native4K/HLS", isHLS: true)
        #expect(!policy.allowsFormat(height: 2160, mimeType: "video/mp4; codecs=\"av01.0.12M.08\""))
        #expect(!policy.allowsFormat(height: 2160, mimeType: "video/webm; codecs=\"vp09.02.50.10\""))
    }

    @Test("fallback remains H264 through 1080p")
    func retainsFallback() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true)
        #expect(policy.maximumHeight == 1080)
        #expect(policy.requiresH264)
        #expect(policy.allowsFormat(height: 1080, mimeType: "video/mp4; codecs=\"avc1.640028\""))
        #expect(!policy.allowsFormat(height: 2160, mimeType: "video/mp4; codecs=\"avc1.640033\""))
    }

    @Test("YouTube bare VP9 metadata becomes selectable only at filtered HLS heights")
    func selectsOnlyManifestBackedFormats() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/Native4K/HLS", isHLS: true)
        let formats = [
            VideoFormat(label: "2160p", width: 3840, height: 2160, fps: 30, mimeType: "video/webm; codecs=\"vp9\""),
            VideoFormat(label: "1440p", width: 2560, height: 1440, fps: 30, mimeType: "video/webm; codecs=\"vp9\""),
            VideoFormat(
                label: "2160p", width: 3840, height: 2160, fps: 30, mimeType: "video/mp4; codecs=\"av01.0.12M.08\""),
        ]
        let selected = policy.formatsForHLS(formats, variantHeights: [2160])
        #expect(selected.count == 1)
        #expect(selected.first?.height == 2160)
        #expect(selected.first?.mimeType == "video/webm; codecs=\"vp9\"")
        #expect(selected.first?.url == nil)
    }

    @Test("4K and H264 fallback do not share filtered variant caches")
    func separatesCodecCaches() {
        let native = HLSPlaybackPolicy.resolve(label: "VisionOS/Native4K/HLS", isHLS: true)
        let fallback = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true)
        let legacy = HLSPlaybackPolicy.resolve(label: "WebSafari/HLS", isHLS: true)
        #expect(native.cacheKey(videoId: "video") != fallback.cacheKey(videoId: "video"))
        #expect(native.cacheKey(videoId: "video") != legacy.cacheKey(videoId: "video"))
        #expect(legacy.cacheKey(videoId: "video") == "video")
    }

    @Test("manager uncaps Native4K HLS while retaining H264 caps")
    @MainActor
    func managerPeakBitRatePolicy() {
        let manager = PlaybackQualityManager(player: AVPlayer())

        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        #expect(manager.allowsNativeVP9)
        #expect(manager.hlsPeakBitRate(for: 2160) == 0)

        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 1080, allowedVideoCodecs: ["avc1"])
        #expect(!manager.allowsNativeVP9)
        #expect(manager.hlsPeakBitRate(for: 1080) == 15_000_000)
        #expect(manager.hlsPeakBitRate(for: 2160) == 45_000_000)
    }

    @Test("reset clears Native4K eligibility and restores base HLS caps")
    @MainActor
    func resetRestoresBasePeakBitRatePolicy() {
        let manager = PlaybackQualityManager(player: AVPlayer())
        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        #expect(manager.hlsPeakBitRate(for: 2160) == 0)

        manager.reset()

        #expect(!manager.allowsNativeVP9)
        #expect(manager.hlsPeakBitRate(for: 1080) == 15_000_000)
        #expect(manager.hlsPeakBitRate(for: 2160) == 45_000_000)
    }

    @Test("native VP9 HLS ramps to the steady 100 second buffer")
    @MainActor
    func nativeHLSRampAppliesSteadyBuffer() async {
        let manager = PlaybackQualityManager(player: AVPlayer())
        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        let item = emptyItem()
        item.preferredForwardBufferDuration = 2

        let task = manager.rampHLSForwardBuffer(on: item, wait: {})
        await task.value

        #expect(item.preferredForwardBufferDuration == PlaybackTuning.nativeHLSForwardBufferSeconds)
    }

    @Test("H264 HLS ramps to the system default")
    @MainActor
    func h264HLSRampUsesSystemDefault() async {
        let manager = PlaybackQualityManager(player: AVPlayer())
        manager.configureHLSPlayback(userAgent: "test", maximumHeight: 1080, allowedVideoCodecs: ["avc1"])
        let item = emptyItem()
        item.preferredForwardBufferDuration = 2

        let task = manager.rampHLSForwardBuffer(on: item, wait: {})
        await task.value

        #expect(item.preferredForwardBufferDuration == 0)
    }

    @Test("an H264-capped native route ramps to the system default")
    @MainActor
    func h264CapDisablesNativeSteadyBuffer() async {
        let manager = PlaybackQualityManager(player: AVPlayer())
        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        manager.hasAppliedH264Cap = true
        let item = emptyItem()
        item.preferredForwardBufferDuration = 2

        let task = manager.rampHLSForwardBuffer(on: item, wait: {})
        await task.value

        #expect(item.preferredForwardBufferDuration == 0)
    }

    @Test("non-HLS streams ramp to the system default")
    @MainActor
    func nonHLSRampUsesSystemDefault() async {
        let manager = PlaybackQualityManager(player: AVPlayer())
        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        let item = emptyItem()
        item.preferredForwardBufferDuration = 2

        let task = manager.rampHLSForwardBuffer(on: item, isHLS: false, wait: {})
        await task.value

        #expect(item.preferredForwardBufferDuration == 0)
    }

    @Test("rearming a parked non-HLS item keeps the system default")
    @MainActor
    func nonHLSRearmUsesSystemDefault() async {
        let manager = PlaybackQualityManager(player: AVPlayer())
        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        let item = emptyItem()
        item.preferredForwardBufferDuration = 2

        let initialTask = manager.rampHLSForwardBuffer(on: item, isHLS: false, wait: {})
        await initialTask.value
        let rearmTask = manager.rearmHLSForwardBuffer(on: item, wait: {})
        await rearmTask.value

        #expect(item.preferredForwardBufferDuration == 0)
    }

    @Test("a throwing wait leaves the startup buffer unchanged")
    @MainActor
    func throwingWaitDoesNotApplyBuffer() async {
        let manager = PlaybackQualityManager(player: AVPlayer())
        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        let item = emptyItem()
        item.preferredForwardBufferDuration = 2

        let task = manager.rampHLSForwardBuffer(on: item, wait: { throw CancellationError() })
        await task.value

        #expect(item.preferredForwardBufferDuration == 2)
    }

    @Test("native target is captured before eligibility changes")
    @MainActor
    func nativeRampCapturesTargetBeforeEligibilityChange() async {
        let player = AVPlayer()
        let manager = PlaybackQualityManager(player: player)
        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        let oldItem = emptyItem()
        oldItem.preferredForwardBufferDuration = 2
        let newItem = emptyItem()
        newItem.preferredForwardBufferDuration = 2
        let gate = RampWaitGate()
        player.replaceCurrentItem(with: oldItem)

        let oldTask = manager.rampHLSForwardBuffer(on: oldItem, wait: { try await gate.wait() })
        await gate.waitUntilStarted()
        manager.configureHLSPlayback(userAgent: "test", maximumHeight: 1080, allowedVideoCodecs: ["avc1"])
        player.replaceCurrentItem(with: newItem)
        await gate.release()
        await oldTask.value
        let newTask = manager.rampHLSForwardBuffer(on: newItem, wait: {})
        await newTask.value

        #expect(oldItem.preferredForwardBufferDuration == PlaybackTuning.nativeHLSForwardBufferSeconds)
        #expect(newItem.preferredForwardBufferDuration == 0)
    }

    @Test("manager cancellation cannot apply a native ramp after replacement")
    @MainActor
    func cancellationDoesNotApplyToOldItem() async {
        let player = AVPlayer()
        let manager = PlaybackQualityManager(player: player)
        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        let oldItem = emptyItem()
        oldItem.preferredForwardBufferDuration = 2
        let newItem = emptyItem()
        newItem.preferredForwardBufferDuration = 2
        let gate = RampWaitGate()
        player.replaceCurrentItem(with: oldItem)

        let task = manager.rampHLSForwardBuffer(on: oldItem, wait: { try await gate.wait() })
        await gate.waitUntilStarted()
        player.replaceCurrentItem(with: newItem)
        manager.cancel()
        await gate.release()
        await task.value

        #expect(oldItem.preferredForwardBufferDuration == 2)
        #expect(newItem.preferredForwardBufferDuration == 2)
    }

    @Test("a newer ramp cancels the older item ramp")
    @MainActor
    func newerRampCancelsOlderRamp() async {
        let manager = PlaybackQualityManager(player: AVPlayer())
        manager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        let oldItem = emptyItem()
        oldItem.preferredForwardBufferDuration = 2
        let newItem = emptyItem()
        newItem.preferredForwardBufferDuration = 2
        let oldGate = RampWaitGate()
        let newGate = RampWaitGate()

        let oldTask = manager.rampHLSForwardBuffer(on: oldItem, wait: { try await oldGate.wait() })
        await oldGate.waitUntilStarted()
        let newTask = manager.rampHLSForwardBuffer(on: newItem, wait: { try await newGate.wait() })
        await newGate.waitUntilStarted()
        await oldGate.release()
        await oldTask.value
        #expect(oldItem.preferredForwardBufferDuration == 2)

        await newGate.release()
        await newTask.value
        #expect(newItem.preferredForwardBufferDuration == PlaybackTuning.nativeHLSForwardBufferSeconds)
    }

    @Test("stopping the view model cancels its native ramp")
    @MainActor
    func viewModelStopCancelsNativeRamp() async {
        let player = AVPlayer()
        let viewModel = PlaybackViewModel(player: player)
        viewModel.qualityManager.configureHLSPlayback(
            userAgent: "test", maximumHeight: 2160, allowedVideoCodecs: ["avc1", "vp09.00"])
        let item = emptyItem()
        item.preferredForwardBufferDuration = 2
        let gate = RampWaitGate()

        let task = viewModel.qualityManager.rampHLSForwardBuffer(on: item, wait: { try await gate.wait() })
        await gate.waitUntilStarted()
        viewModel.stop()
        await gate.release()
        await task.value

        #expect(item.preferredForwardBufferDuration == 2)
    }
}
