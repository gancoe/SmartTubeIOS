import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("Playback native diagnostics model")
struct PlaybackNativeDiagnosticsModelTests {
    @Test
    func boundsAndUnavailableFieldsAreSanitised() throws {
        let segment = PlaybackNativeSegment(
            mediaType: "invalid", itag: 0, isMap: false, segmentDurationSeconds: .infinity,
            resourceAvailable: false, transactionsAvailable: false, readFromCache: true,
            resourceRequestDurationSeconds: 1, errorDomain: "secret", errorCode: Int.max,
            transactions: [
                .init(
                    index: -1, responseState: "response_absent", httpStatus: 999, networkProtocol: "secret",
                    reusedConnection: false, requestToResponseSeconds: 4, requestToCompletionSeconds: 5)
            ])
        let data = try JSONEncoder().encode(segment)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["media_type"] as? String == "unknown")
        #expect(object["itag"] == nil)
        #expect(object["read_from_cache"] == nil)
        #expect(object["resource_request_duration_seconds"] == nil)
        #expect(object["error_domain"] == nil)
        #expect((object["transactions"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test
    func noResponseRetainsCompletionDuration() {
        let transaction = PlaybackNativeSegment.Transaction(
            index: 0, responseState: "response_absent", httpStatus: nil, networkProtocol: nil,
            reusedConnection: false, requestToResponseSeconds: 3, requestToCompletionSeconds: 7)
        #expect(transaction.requestToResponseSeconds == nil)
        #expect(transaction.requestToCompletionSeconds == 7)
    }

    @Test func reconcilesPathAndQueryItagsWithoutRetainingURLs() {
        #expect(
            PlaybackNativeDiagnosticsMapper.itag(
                from: URL(string: "https://example.test/itag/625/segment?token=secret")) == 625)
        #expect(
            PlaybackNativeDiagnosticsMapper.itag(from: URL(string: "https://example.test/itag/625/segment?itag=625"))
                == 625)
        #expect(
            PlaybackNativeDiagnosticsMapper.itag(from: URL(string: "https://example.test/itag/625/segment?itag=620"))
                == nil)
        #expect(
            PlaybackNativeDiagnosticsMapper.itag(
                from: URL(string: "https://example.test/itag/625/segment?itag=invalid")) == nil)
        #expect(PlaybackNativeDiagnosticsMapper.itag(from: URL(string: "https://example.test/itag")) == nil)
    }

    @Test func transactionBoundsAndAbsentResponseRemainConsistent() throws {
        let transaction = PlaybackNativeSegment.Transaction(
            index: 0, responseState: "response_absent", httpStatus: 200, networkProtocol: "secret",
            reusedConnection: false, requestToResponseSeconds: 3, requestToCompletionSeconds: 7)
        #expect(transaction.httpStatus == nil)
        #expect(transaction.networkProtocol == nil)
        let segment = PlaybackNativeSegment(
            mediaType: "video", itag: 625, isMap: false, segmentDurationSeconds: 5,
            resourceAvailable: true, transactionsAvailable: true, readFromCache: false,
            resourceRequestDurationSeconds: 13, errorDomain: "secret", errorCode: -12_889,
            transactions: Array(repeating: transaction, count: 10))
        #expect(segment.transactions.count == 8)
        #expect(segment.errorDomain == "other")
        let encoded = try #require(String(data: JSONEncoder().encode(segment), encoding: .utf8))
        #expect(!encoded.contains("secret"))
        #expect(!encoded.contains("https://"))
    }
}
