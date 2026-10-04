import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@MainActor
@Suite("VisionOS native stream source")
struct VisionOSNativeStreamSourceTests {
    @Test(
        "only an explicit 2160p preference opts into the native VP9 experiment",
        arguments: AppSettings.VideoQuality.allCases)
    func qualityOptIn(quality: AppSettings.VideoQuality) {
        #expect(
            VisionOSNativeStreamSource.allowsNativeVP9Attempt(
                requestedQuality: quality, hardwareSupported: true, supplementalRequested: true, rejected: false
            ) == (quality == .q2160))
    }

    @Test("2160p cannot override missing decoder support or session rejection")
    func optInStillRequiresDecoder() {
        #expect(
            !VisionOSNativeStreamSource.allowsNativeVP9Attempt(
                requestedQuality: .q2160, hardwareSupported: false, supplementalRequested: true, rejected: false
            ))
        #expect(
            !VisionOSNativeStreamSource.allowsNativeVP9Attempt(
                requestedQuality: .q2160, hardwareSupported: true, supplementalRequested: false, rejected: false
            ))
        #expect(
            !VisionOSNativeStreamSource.allowsNativeVP9Attempt(
                requestedQuality: .q2160, hardwareSupported: true, supplementalRequested: true, rejected: true
            ))
    }

    private enum TestError: Error {
        case fetchFailed
    }

    @MainActor
    private final class Fake {
        var fetchResult: Result<PlayerInfo, Error>
        var hlsResult = false
        var fallbackResult = false
        var trace: [String] = []
        var hlsInfo: PlayerInfo?
        var fallbackInfo: PlayerInfo?
        var onHLS: (@MainActor () -> Void)?

        init(info: PlayerInfo) {
            fetchResult = .success(info)
        }

        func fetch() throws -> PlayerInfo {
            trace.append("fetch")
            return try fetchResult.get()
        }

        func attemptHLS(_ info: PlayerInfo, label: String) -> Bool {
            trace.append("hls:\(label)")
            hlsInfo = info
            onHLS?()
            return hlsResult
        }

        func attemptFallback(_ info: PlayerInfo, label: String) -> Bool {
            trace.append("fallback:\(label)")
            fallbackInfo = info
            return fallbackResult
        }
    }

    @Test("native VP9 HLS success skips the existing fallback")
    func nativeHLSuccessSkipsFallback() async throws {
        let info = makeInfo(hlsURL: URL(string: "https://example.com/native.m3u8"))
        let fake = Fake(info: info)
        fake.hlsResult = true

        let result = try await source(fake: fake, supportsNativeVP9: true).resolve()

        #expect(result)
        #expect(fake.trace == ["fetch", "hls:VisionOS/Native4K/HLS"])
        #expect(fake.hlsInfo?.video.id == info.video.id)
    }

    @Test("failed native HLS falls back with the fetched PlayerInfo")
    func failedNativeHLSUsesFallback() async throws {
        let info = makeInfo(hlsURL: URL(string: "https://example.com/native.m3u8"))
        let fake = Fake(info: info)
        fake.fallbackResult = true

        let result = try await source(fake: fake, supportsNativeVP9: true).resolve()

        #expect(result)
        #expect(
            fake.trace == [
                "fetch", "hls:VisionOS/Native4K/HLS", "fallback:VisionOS",
            ])
        #expect(fake.hlsInfo?.video.id == fake.fallbackInfo?.video.id)
        #expect(fake.hlsInfo?.hlsURL == fake.fallbackInfo?.hlsURL)
    }

    @Test("unsupported native VP9 capability uses only the existing fallback")
    func unsupportedNativeVP9UsesFallbackOnly() async throws {
        let info = makeInfo(hlsURL: URL(string: "https://example.com/native.m3u8"))
        let fake = Fake(info: info)
        fake.fallbackResult = true

        let result = try await source(fake: fake, supportsNativeVP9: false).resolve()

        #expect(result)
        #expect(fake.trace == ["fetch", "fallback:VisionOS"])
    }

    @Test("missing HLS skips the native 4K attempt")
    func missingHLSUsesFallbackOnly() async throws {
        let info = makeInfo(hlsURL: nil)
        let fake = Fake(info: info)
        fake.fallbackResult = true

        let result = try await source(fake: fake, supportsNativeVP9: true).resolve()

        #expect(result)
        #expect(fake.trace == ["fetch", "fallback:VisionOS"])
    }

    @Test("fetch errors propagate without attempting either stream")
    func fetchErrorStopsResolution() async {
        let info = makeInfo(hlsURL: URL(string: "https://example.com/native.m3u8"))
        let fake = Fake(info: info)
        fake.fetchResult = .failure(TestError.fetchFailed)

        do {
            _ = try await source(fake: fake, supportsNativeVP9: true).resolve()
            Issue.record("resolve() unexpectedly succeeded")
        } catch is TestError {
            // Expected.
        } catch {
            Issue.record("resolve() threw an unexpected error: \(error)")
        }

        #expect(fake.trace == ["fetch"])
    }

    @Test("cancellation after native HLS failure prevents fallback")
    func cancellationStopsBeforeFallback() async {
        let info = makeInfo(hlsURL: URL(string: "https://example.com/native.m3u8"))
        let fake = Fake(info: info)
        var task: Task<Bool, Error>?
        fake.onHLS = { task?.cancel() }

        let streamSource = source(fake: fake, supportsNativeVP9: true)
        task = Task { @MainActor in
            try await streamSource.resolve()
        }

        guard let task else {
            Issue.record("resolution task was not created")
            return
        }

        do {
            _ = try await task.value
            Issue.record("resolve() unexpectedly succeeded")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("resolve() threw an unexpected error: \(error)")
        }

        #expect(fake.trace == ["fetch", "hls:VisionOS/Native4K/HLS"])
    }

    private func source(
        fake: Fake,
        supportsNativeVP9: Bool
    ) -> VisionOSNativeStreamSource {
        VisionOSNativeStreamSource(
            supportsNativeVP9: supportsNativeVP9,
            fetch: { try fake.fetch() },
            attemptHLS: { info, label in fake.attemptHLS(info, label: label) },
            attemptFallback: { info, label in fake.attemptFallback(info, label: label) }
        )
    }

    private func makeInfo(hlsURL: URL?) -> PlayerInfo {
        PlayerInfo(
            video: Video(id: "visionos-test", title: "Test", channelTitle: "Channel"),
            formats: [],
            hlsURL: hlsURL,
            dashURL: nil,
            captionTracks: [],
            trackingURLs: nil,
            endCards: []
        )
    }
}
