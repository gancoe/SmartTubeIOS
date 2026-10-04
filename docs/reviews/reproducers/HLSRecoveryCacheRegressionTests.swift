import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("HLS recovery cache invalidation reproducer")
struct HLSRecoveryCacheRegressionTests {
    @Test("403 recovery invalidates every source policy for the affected video")
    func recoveryInvalidatesPolicyEntries() throws {
        var cache = HLSManifestCache()
        let videoID = "expired-video"
        let nativeKey = HLSPlaybackPolicy.resolve(label: "VisionOS/Native4K/HLS", isHLS: true)
            .cacheKey(videoId: videoID)
        let h264Key = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true)
            .cacheKey(videoId: videoID)
        let stale = try #require(URL(string: "https://example.invalid/expired.m3u8"))
        let unrelated = try #require(URL(string: "https://example.invalid/other.m3u8"))
        cache.store([720: stale], for: videoID)
        cache.store([2160: stale], for: nativeKey)
        cache.store([1080: stale], for: h264Key)
        cache.store([720: unrelated], for: "other-video")

        cache.invalidate(for: videoID)

        #expect(cache.variants(for: videoID) == nil)
        #expect(cache.variants(for: nativeKey) == nil)
        #expect(cache.variants(for: h264Key) == nil)
        #expect(cache.variants(for: "other-video") == [720: unrelated])
    }
}
