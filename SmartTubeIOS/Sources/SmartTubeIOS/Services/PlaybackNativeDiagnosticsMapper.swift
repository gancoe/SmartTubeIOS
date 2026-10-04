import AVFoundation
import Foundation

enum PlaybackNativeDiagnosticsMapper {
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
    static func segment(from event: AVMetricHLSMediaSegmentRequestEvent) -> PlaybackNativeSegment {
        segmentResult(from: event).segment
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
    static func segmentResult(
        from event: AVMetricHLSMediaSegmentRequestEvent
    ) -> (segment: PlaybackNativeSegment, droppedTransactions: Int) {
        let resource = event.mediaResourceRequestEvent
        var transactions: [PlaybackNativeSegment.Transaction] = []
        if let metrics = resource?.networkTransactionMetrics?.transactionMetrics {
            for (index, metric) in metrics.enumerated().prefix(8) {
                let response = metric.response as? HTTPURLResponse
                let responseAvailable = metric.response != nil
                transactions.append(
                    PlaybackNativeSegment.Transaction(
                        index: index,
                        responseState: responseAvailable ? "received" : "response_absent",
                        httpStatus: response?.statusCode,
                        networkProtocol: safeProtocol(metric.networkProtocolName),
                        reusedConnection: metric.isReusedConnection,
                        requestToResponseSeconds: responseAvailable
                            ? duration(from: metric.requestStartDate, to: metric.responseStartDate) : nil,
                        requestToCompletionSeconds: duration(from: metric.requestStartDate, to: metric.responseEndDate))
                )
            }
        }
        let error = resource?.errorEvent?.error as NSError?
        return (
            PlaybackNativeSegment(
                mediaType: mediaType(event.mediaType),
                itag: itag(from: event.url),
                isMap: event.isMapSegment,
                segmentDurationSeconds: event.segmentDuration,
                resourceAvailable: resource != nil,
                transactionsAvailable: resource?.networkTransactionMetrics != nil,
                readFromCache: resource.map(\.wasReadFromCache),
                resourceRequestDurationSeconds: duration(
                    from: resource?.requestStartTime, to: resource?.requestEndTime),
                errorDomain: errorDomain(error?.domain),
                errorCode: error?.code,
                transactions: transactions),
            max(0, (resource?.networkTransactionMetrics?.transactionMetrics.count ?? 0) - 8)
        )
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
    static func variantSwitch(from event: AVMetricPlayerItemVariantSwitchEvent) -> PlaybackNativeVariantSwitch {
        let from = event.fromVariant
        let to = event.toVariant
        let fromSize = from?.videoAttributes?.presentationSize ?? .zero
        let toSize = to.videoAttributes?.presentationSize ?? .zero
        return PlaybackNativeVariantSwitch(
            succeeded: event.didSucceed,
            fromWidth: dimension(fromSize.width),
            fromHeight: dimension(fromSize.height),
            toWidth: dimension(toSize.width),
            toHeight: dimension(toSize.height),
            fromBitrateBps: from.flatMap { bitrate($0.peakBitRate) },
            toBitrateBps: bitrate(to.peakBitRate))
    }

    private static func mediaType(_ value: AVMediaType) -> String {
        switch value {
        case .video: return "video"
        case .audio: return "audio"
        case .muxed: return "muxed"
        default: return "unknown"
        }
    }

    static func itag(from url: URL?) -> Int? {
        guard let url else { return nil }
        var values: [String?] =
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .filter { $0.name.lowercased() == "itag" }.map(\.value) ?? []
        let components = url.path.split(separator: "/").map(String.init)
        for index in components.indices where components[index].lowercased() == "itag" {
            let next = components.index(after: index)
            values.append(next < components.endIndex ? components[next] : nil)
        }
        guard !values.isEmpty else { return nil }
        var parsed: [Int] = []
        for value in values {
            guard let value, (1...5).contains(value.utf8.count),
                value.utf8.allSatisfy({ (48...57).contains($0) }),
                let number = Int(value), (1...99_999).contains(number)
            else { return nil }
            parsed.append(number)
        }
        let unique = Set(parsed)
        return unique.count == 1 ? unique.first : nil
    }

    private static func safeProtocol(_ value: String?) -> String? {
        guard let value else { return nil }
        switch value.lowercased() {
        case "h3": return "h3"
        case "h2": return "h2"
        case "http/1.1": return "http/1.1"
        case "http/1.0": return "http/1.0"
        default: return "other"
        }
    }

    private static func errorDomain(_ value: String?) -> String? {
        switch value {
        case "CoreMediaErrorDomain": return value
        case "AVFoundationErrorDomain": return value
        case "NSURLErrorDomain": return value
        case "NSOSStatusErrorDomain": return value
        case nil: return nil
        default: return "other"
        }
    }

    private static func duration(from start: Date?, to end: Date?) -> Double? {
        guard let start, let end else { return nil }
        let value = end.timeIntervalSince(start)
        return value.isFinite && value >= 0 ? value : nil
    }

    private static func dimension(_ value: CGFloat) -> Int? {
        guard value.isFinite, value >= 1, value <= 20_000 else { return nil }
        let rounded = Int(value.rounded())
        return (1...20_000).contains(rounded) ? rounded : nil
    }

    private static func bitrate(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
