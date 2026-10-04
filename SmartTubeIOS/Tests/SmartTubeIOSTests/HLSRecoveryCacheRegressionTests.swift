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

    @Test("invalidation preserves adjacent video and policy entries")
    func invalidationPreservesAdjacentVideoEntries() throws {
        var cache = HLSManifestCache()
        let videoID = "expired-video"
        let adjacentVideoID = "expired-video-other"
        let adjacentPolicyKey = HLSPlaybackPolicy.resolve(label: "VisionOS/Native4K/HLS", isHLS: true)
            .cacheKey(videoId: adjacentVideoID)
        let retained = try #require(URL(string: "https://example.invalid/retained.m3u8"))
        cache.store([720: retained], for: adjacentVideoID)
        cache.store([2160: retained], for: adjacentPolicyKey)

        cache.invalidate(for: videoID)

        #expect(cache.variants(for: adjacentVideoID) == [720: retained])
        #expect(cache.variants(for: adjacentPolicyKey) == [2160: retained])
    }

    @Test("repeated missing-video invalidation preserves unrelated entries")
    func invalidationIsIdempotentForMissingVideo() throws {
        var cache = HLSManifestCache()
        let retained = try #require(URL(string: "https://example.invalid/retained.m3u8"))
        cache.store([720: retained], for: "other-video")
        cache.invalidate(for: "missing-video")
        cache.invalidate(for: "missing-video")
        #expect(cache.variants(for: "missing-video") == nil)
        #expect(cache.variants(for: "other-video") == [720: retained])
    }
}
