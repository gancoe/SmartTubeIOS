import AVFoundation
import SmartTubeIOSCore
import Testing

@testable import SmartTubeIOS

@Suite("Native 4K HLS policy")
struct Native4KHLSPlaybackPolicyTests {
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
}
