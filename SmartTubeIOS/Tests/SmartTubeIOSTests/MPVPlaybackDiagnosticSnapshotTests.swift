import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("MPV diagnostic snapshots")
struct MPVPlaybackDiagnosticSnapshotTests {
    @Test func creationFailureIsReportedWithoutInventingALibraryErrorCode() {
        let failureTime = Date(timeIntervalSince1970: 1_000)
        let event = MPVPlaybackDiagnosticSnapshot(
            reportID: "test", videoID: "test", errorEventCount: 1, errorTimestamp: failureTime
        ).deliveryEvent()
        #expect(event.itemStatus == "failed")
        #expect(event.playbackStatus == "paused")
        #expect(event.errorEventCount == 1)
        #expect(event.errorCode == nil)
        #expect(event.errorTimestamp == failureTime)
    }

    @Test(arguments: [1.5, 2.0])
    func reportsViewingHeadroomAndMPVCacheThroughput(speed: Double) {
        let event = MPVPlaybackDiagnosticSnapshot(
            reportID: "report-test", videoID: "LopfSWVa19s",
            currentTime: 123, rate: speed, bufferSeconds: 100,
            isPlaying: true, isReady: true, videoWidth: 3840, videoHeight: 2160,
            downloadMbps: 80
        ).deliveryEvent()
        #expect(event.streamRoute == "MPV/FFmpeg/HLS")
        #expect(event.resolution == "3840x2160")
        #expect(event.bufferViewingSeconds == 100 / speed)
        #expect(event.observedBitrateBps == 80_000_000)
        #expect(event.advertisedBitrateBps == nil)
        #expect(event.nativeSegment == nil)
        #expect(event.nativeVariantSwitch == nil)
    }

    @Test func errorsRemainDistinctFromCoreMediaAndContainNoStreamURL() {
        let event = MPVPlaybackDiagnosticSnapshot(
            reportID: "test", videoID: "test", errorEventCount: 1, errorCode: -13
        ).deliveryEvent()
        #expect(event.errorDomain == "MPV")
        #expect(event.errorCode == -13)
        #expect(event.errorEventCount == 1)
        #expect(event.errorResource == "unknown")
        #expect(event.errorComment == "Details redacted")
    }

    @Test func invalidValuesCannotBreakJSONOrLeakIdentifiers() throws {
        let event = MPVPlaybackDiagnosticSnapshot(
            reportID: "https://private.example/test", videoID: "token=secret",
            currentTime: .nan, rate: .infinity, bufferSeconds: -1,
            videoWidth: -1, videoHeight: 0, downloadMbps: Double.greatestFiniteMagnitude
        ).deliveryEvent()
        #expect(event.reportID == "unknown")
        #expect(event.videoID == "unknown")
        #expect(event.playbackPositionSeconds == nil)
        #expect(event.rate == nil)
        #expect(event.bufferMediaSeconds == nil)
        #expect(event.observedBitrateBps == nil)
        #expect(event.resolution == "unknown")
        _ = try JSONEncoder().encode(event)
    }

    @Test func cacheWaitUsesTheExistingCollectorStatusContract() {
        let event = MPVPlaybackDiagnosticSnapshot(
            reportID: "test", videoID: "test", isPlaying: true, isBuffering: true, isReady: true
        ).deliveryEvent()
        #expect(event.itemStatus == "ready")
        #expect(event.playbackStatus == "waiting")
        #expect(event.waitingReason == "unknown")
        #expect(event.errorComment == "—")
    }
}
